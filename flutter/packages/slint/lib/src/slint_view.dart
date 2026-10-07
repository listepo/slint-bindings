import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'events.dart';
import 'render_target.dart';

/// A Flutter widget that displays a software-rendered Slint component with
/// pointer and keyboard input handling.
///
/// Backend-agnostic: works with any [SlintSoftwareRenderTarget] — the
/// interpreter path (`slint_interpreter`) or the compiled path (`slint_compiler`).
///
/// Sizing follows the layout: each frame the view resizes the target to the
/// laid-out size in physical pixels. Under unbounded constraints (a `Row`, a
/// scrollable) there is no size to report, so nothing is resized or rendered
/// until the layout is bounded — give the view an explicit size there.
///
/// Example:
/// ```dart
/// SlintView(target: component.renderTarget)
/// ```
class SlintView extends StatefulWidget {
  const SlintView({super.key, required this.target});

  final SlintSoftwareRenderTarget target;

  @override
  State<SlintView> createState() => _SlintViewState();
}

class _SlintViewState extends State<SlintView>
    with SingleTickerProviderStateMixin, TextInputClient {
  late final Ticker _ticker;
  final FocusNode _focusNode = FocusNode();
  ui.Image? _image;
  bool _decoding = false;
  Uint8List? _pixelScratch;
  double _dpr = 1;

  /// Physical size last passed to [SlintSoftwareRenderTarget.resize].
  int _appliedWidth = 0;
  int _appliedHeight = 0;

  /// Bumped whenever the render target changes, so an in-flight decode from
  /// the old target cannot overwrite the new target's image when it lands.
  int _generation = 0;

  /// Size the layout asked for, in physical pixels; applied on the next tick
  /// rather than inside `build`, which must stay free of side effects.
  int _wantedWidth = 0;
  int _wantedHeight = 0;

  /// Button held since the last down event; up/cancel events carry none.
  SlintPointerButton _pressedButton = SlintPointerButton.none;

  TextInputConnection? _connection;
  TextEditingValue _editing = _padValue;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void didUpdateWidget(SlintView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.target != oldWidget.target) {
      _generation++;
      _decoding = false;
      _image?.dispose();
      _image = null;
      _pressedButton = SlintPointerButton.none;
      // The next tick sizes and renders the new target.
    }
  }

  void _applyResize(int width, int height) {
    if (width <= 0 || height <= 0) return;
    if (width == _appliedWidth && height == _appliedHeight) return;
    widget.target.resize(width, height);
    _appliedWidth = width;
    _appliedHeight = height;
  }

  void _onDprChanged() {
    _generation++;
    _decoding = false;
    _image?.dispose();
    _image = null;
    _appliedWidth = 0;
    _appliedHeight = 0;
  }

  void _onTick(Duration elapsed) {
    if (_decoding) return;
    final target = widget.target;
    _applyResize(_wantedWidth, _wantedHeight);
    if (target.render() || _image == null) {
      _decodeImage();
    }
  }

  void _decodeImage() {
    final target = widget.target;
    final w = target.width;
    final h = target.height;
    if (w <= 0 || h <= 0) return;
    final generation = _generation;

    _decoding = true;
    try {
      // Copy into a reused scratch so a concurrent resize cannot free the
      // native buffer while decodeImageFromPixels is still reading it.
      final needed = w * h * 4;
      final scratch = _pixelScratch;
      final pixels = (scratch != null && scratch.length == needed)
          ? scratch
          : (_pixelScratch = Uint8List(needed));
      pixels.setRange(0, needed, target.pixels);
      ui.decodeImageFromPixels(pixels, w, h, ui.PixelFormat.rgba8888, (image) {
        // The target may have changed while the decode was in flight:
        // a stale frame must not replace the new target's image.
        if (!mounted || generation != _generation) {
          image.dispose();
          if (generation == _generation) _decoding = false;
          return;
        }
        _image?.dispose();
        setState(() {
          _image = image;
          _decoding = false;
        });
      });
    } catch (_) {
      _decoding = false;
      rethrow;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _closeConnection();
    _focusNode.dispose();
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final dpr = MediaQuery.devicePixelRatioOf(context);
        var dprChanged = false;
        if (dpr != _dpr) {
          _dpr = dpr;
          dprChanged = true;
          _onDprChanged();
        }
        // Unbounded constraints (a Row, a scrollable, an unconstrained box)
        // report infinite sizes; resizing the native buffer to infinity
        // would throw in toInt(). Report 0 instead — the tick skips
        // resize/render until the layout is bounded.
        final logicalW = constraints.biggest.width;
        final logicalH = constraints.biggest.height;
        _wantedWidth = logicalW.isFinite
            ? (logicalW * _dpr).toInt().clamp(0, 1 << 30)
            : 0;
        _wantedHeight = logicalH.isFinite
            ? (logicalH * _dpr).toInt().clamp(0, 1 << 30)
            : 0;

        if (dprChanged) {
          // A DPR-only change does not always schedule another tick before input
          // arrives; resize immediately so pointer coords and the buffer agree.
          _applyResize(_wantedWidth, _wantedHeight);
        }

        return Focus(
          focusNode: _focusNode,
          onKeyEvent: _handleKeyEvent,
          child: MouseRegion(
            onExit: (_) => _sendPointer(SlintPointerEventKind.exit, null),
            child: Listener(
              onPointerDown: (event) {
                _focusNode.requestFocus();
                // Already focused: re-open a keyboard the user dismissed, or a
                // connection the platform closed. Otherwise the focus change
                // opens it.
                if (_focusNode.hasFocus) _openConnection();
                _pressedButton = _buttonOf(event.buttons);
                _sendPointer(
                  SlintPointerEventKind.down,
                  event,
                  button: _pressedButton,
                );
              },
              onPointerMove: (event) =>
                  _sendPointer(SlintPointerEventKind.move, event),
              onPointerHover: (event) =>
                  _sendPointer(SlintPointerEventKind.move, event),
              onPointerUp: (event) => _release(event),
              // The gesture went elsewhere (a scroll view took it, the OS
              // interrupted): Slint must not stay pressed.
              onPointerCancel: (event) {
                _release(event);
                _sendPointer(SlintPointerEventKind.exit, null);
              },
              onPointerSignal: _handlePointerSignal,
              child: SizedBox.expand(
                child: _image != null
                    ? RawImage(image: _image, fit: BoxFit.fill)
                    : Container(color: Colors.grey[300]),
              ),
            ),
          ),
        );
      },
    );
  }

  static SlintPointerButton _buttonOf(int buttons) {
    if (buttons & kSecondaryButton != 0) return SlintPointerButton.right;
    if (buttons & kMiddleMouseButton != 0) return SlintPointerButton.middle;
    return SlintPointerButton.left;
  }

  void _release(PointerEvent event) {
    _sendPointer(SlintPointerEventKind.up, event, button: _pressedButton);
    _pressedButton = SlintPointerButton.none;
  }

  void _sendPointer(
    SlintPointerEventKind kind,
    PointerEvent? event, {
    SlintPointerButton button = SlintPointerButton.none,
  }) {
    final offset = event?.localPosition ?? Offset.zero;
    widget.target.dispatchPointerEvent(
      SlintPointerEvent(
        kind: kind,
        x: offset.dx * _dpr,
        y: offset.dy * _dpr,
        button: button,
      ),
    );
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      final offset = event.localPosition;
      widget.target.dispatchPointerEvent(
        SlintPointerEvent(
          kind: SlintPointerEventKind.scroll,
          x: offset.dx * _dpr,
          y: offset.dy * _dpr,
          scrollDeltaX: -event.scrollDelta.dx * _dpr,
          scrollDeltaY: -event.scrollDelta.dy * _dpr,
        ),
      );
    }
  }

  void _dispatchKey(String text, {required bool pressed}) {
    widget.target.dispatchKeyEvent(SlintKeyEvent(text: text, pressed: pressed));
  }

  void _sendKey(String text) {
    _dispatchKey(text, pressed: true);
    _dispatchKey(text, pressed: false);
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    // With a text input connection open, text, backspace and enter arrive
    // through the editing value: the platform's text input plugin interprets
    // the key events the framework leaves unhandled (macOS NSTextInputClient,
    // Windows WM_CHAR, GTK IM context) and reports them as edits, just as a
    // soft keyboard does. The raw path below is the fallback for a
    // connection the platform closed.
    if (_connection != null) return KeyEventResult.ignored;

    final named = slintKeyText(event.logicalKey);
    if (named != null) {
      if (event is KeyDownEvent || event is KeyRepeatEvent) {
        _dispatchKey(named, pressed: true);
        return KeyEventResult.handled;
      }
      if (event is KeyUpEvent) {
        _dispatchKey(named, pressed: false);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      if (event.character != null && event.character!.isNotEmpty) {
        _sendKey(event.character!);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.backspace) {
        _sendKey(_backspace);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.enter) {
        _sendKey('\n');
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  // --- Text input / IME ----------------------------------------------------
  //
  // Like EditableText, a focused view holds a text input connection on every
  // platform: a soft keyboard where there is one, the platform's text input
  // plugin behind a hardware keyboard elsewhere. Slint does not tell us which
  // of its elements has focus, so the connection follows the view's focus.
  // The platform edits a mirror string; the difference between two editing
  // values is replayed into Slint as backspaces and inserted text.
  // ponytail: assumes Slint's caret is at the end of its text; no selection
  // or cursor sync. Slint's `input_method_request` would give the real state.

  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      _openConnection();
    } else {
      _closeConnection();
    }
  }

  void _openConnection() {
    if (_connection == null) {
      _editing = _padValue;
      _connection = TextInput.attach(
        this,
        const TextInputConfiguration(
          inputType: TextInputType.multiline,
          inputAction: TextInputAction.newline,
          autocorrect: false,
          enableSuggestions: false,
        ),
      )..setEditingState(_editing);
    }
    _connection!.show();
  }

  void _closeConnection() {
    _connection?.close();
    _connection = null;
  }

  @override
  TextEditingValue get currentTextEditingValue => _editing;

  @override
  AutofillScope? get currentAutofillScope => null;

  @override
  void updateEditingValue(TextEditingValue value) {
    for (final key in editsBetween(_editing.text, value.text)) {
      _sendKey(key);
    }
    _editing = value;
    // Keep the mirror in the one shape the replay understands: caret at the
    // end, nothing selected (a select-all followed by typing would otherwise
    // replay as deleting the whole pad), something to delete in front of the
    // caret, and a bounded length. Never reset mid-composition — that would
    // cancel the IME's candidate.
    final text = value.text;
    final selection = value.selection;
    final caretAtEnd =
        selection.isCollapsed && selection.extentOffset == text.length;
    if (!value.composing.isValid &&
        (!caretAtEnd || text.length < 2 || text.length > 256)) {
      _editing = _padValue;
      _connection?.setEditingState(_editing);
    }
  }

  @override
  void performAction(TextInputAction action) {
    if (action != TextInputAction.newline) _sendKey('\n');
  }

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {}

  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {}

  @override
  void showAutocorrectionPromptRect(int start, int end) {}

  @override
  void connectionClosed() {
    // The platform closed it; tell TextInput so it forgets the connection
    // too. The hardware key path takes over until the next tap re-attaches.
    _connection?.connectionClosedReceived();
    _connection = null;
  }
}

/// Slint named-key codes (`i-slint-common` key_codes, mirrored in
/// `slint-dart-core`'s `events::key_codes`).
const _backspace = '\u0008';
const _tab = '\u0009';
const _escape = '\u001b';
const _shift = '\u0010';
const _control = '\u0011';
const _alt = '\u0012';
const _shiftRight = '\u0015';
const _controlRight = '\u0016';
const _meta = '\u0017';
const _metaRight = '\u0018';
const _upArrow = '\uF700';
const _downArrow = '\uF701';
const _leftArrow = '\uF702';
const _rightArrow = '\uF703';

/// Maps a Flutter [LogicalKeyboardKey] to Slint's key-event `text` for named
/// keys (arrows, tab, escape, modifiers). Returns null for keys Slint expects
/// as plain characters (letters, digits, backspace, enter).
@visibleForTesting
String? slintKeyText(LogicalKeyboardKey key) {
  if (key == LogicalKeyboardKey.tab) return _tab;
  if (key == LogicalKeyboardKey.escape) return _escape;
  if (key == LogicalKeyboardKey.arrowUp) return _upArrow;
  if (key == LogicalKeyboardKey.arrowDown) return _downArrow;
  if (key == LogicalKeyboardKey.arrowLeft) return _leftArrow;
  if (key == LogicalKeyboardKey.arrowRight) return _rightArrow;
  if (key == LogicalKeyboardKey.shiftLeft) return _shift;
  if (key == LogicalKeyboardKey.shiftRight) return _shiftRight;
  if (key == LogicalKeyboardKey.controlLeft) return _control;
  if (key == LogicalKeyboardKey.controlRight) return _controlRight;
  if (key == LogicalKeyboardKey.altLeft) return _alt;
  if (key == LogicalKeyboardKey.altRight) return _alt;
  if (key == LogicalKeyboardKey.metaLeft) return _meta;
  if (key == LogicalKeyboardKey.metaRight) return _metaRight;
  return null;
}

const _pad = '\u200B\u200B\u200B\u200B\u200B\u200B\u200B\u200B';
const _padValue = TextEditingValue(
  text: _pad,
  selection: TextSelection.collapsed(offset: _pad.length),
);

/// Key texts that turn [before] into [after] when replayed into Slint at the
/// end of its text: one backspace per removed character, then the inserted
/// text. Exposed for tests.
@visibleForTesting
List<String> editsBetween(String before, String after) {
  var prefix = 0;
  while (prefix < before.length &&
      prefix < after.length &&
      before.codeUnitAt(prefix) == after.codeUnitAt(prefix)) {
    prefix++;
  }
  var suffix = 0;
  while (suffix < before.length - prefix &&
      suffix < after.length - prefix &&
      before.codeUnitAt(before.length - 1 - suffix) ==
          after.codeUnitAt(after.length - 1 - suffix)) {
    suffix++;
  }
  final removed = before.substring(prefix, before.length - suffix);
  final inserted = after.substring(prefix, after.length - suffix);
  return [
    for (final _ in removed.characters) _backspace,
    if (inserted.isNotEmpty) inserted,
  ];
}
