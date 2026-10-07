import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slint/slint.dart';

/// A 2×1 frame with one opaque red and one half-transparent red pixel, both
/// premultiplied the way Slint's software renderer writes them.
final _frame = Uint8List.fromList([255, 0, 0, 255, 128, 0, 0, 128]);

class _FakeTarget implements SlintSoftwareRenderTarget {
  final pointer = <SlintPointerEvent>[];
  final keys = <String>[];
  var _dirty = true;

  @override
  int width = 0;
  @override
  int height = 0;

  @override
  SlintComponent get component => throw UnimplementedError();

  @override
  Uint8List get pixels {
    if (width == 2 && height == 1) return _frame;
    return Uint8List.fromList(List<int>.filled(width * height * 4, 0));
  }

  @override
  void resize(int w, int h) {
    width = w;
    height = h;
  }

  @override
  bool render() {
    final drew = _dirty;
    _dirty = false;
    return drew;
  }

  @override
  void dispatchPointerEvent(SlintPointerEvent event) => pointer.add(event);

  @override
  void dispatchKeyEvent(SlintKeyEvent event) {
    if (event.pressed) keys.add(event.text);
  }

  @override
  void dispose() {}
}

const _bs = '\u0008';

/// A 2×1 logical view at device pixel ratio 1, so it matches [_frame].
Widget _host(SlintSoftwareRenderTarget target) => MediaQuery(
  data: const MediaQueryData(),
  child: Center(
    child: SizedBox(width: 2, height: 1, child: SlintView(target: target)),
  ),
);

Future<_FakeTarget> _pump(WidgetTester tester) async {
  final target = _FakeTarget();
  await tester.pumpWidget(_host(target));
  await tester.pump(); // the first tick sizes the target and renders
  return target;
}

void main() {
  test('editsBetween replays a mirror change as backspaces then text', () {
    expect(editsBetween('abc', 'abcd'), ['d']);
    expect(editsBetween('abcd', 'abc'), [_bs]);
    expect(editsBetween('abc', 'abx'), [_bs, 'x']);
    expect(editsBetween('ab', 'ab'), isEmpty);
    expect(editsBetween('a😀', 'a'), [
      _bs,
    ], reason: 'one backspace per grapheme');
    expect(editsBetween('', 'héllo wörld'), ['héllo wörld']);
  });

  test('slintKeyText maps named hardware keys to Slint codes', () {
    expect(slintKeyText(LogicalKeyboardKey.tab), '\u0009');
    expect(slintKeyText(LogicalKeyboardKey.escape), '\u001b');
    expect(slintKeyText(LogicalKeyboardKey.arrowLeft), '\uF702');
    expect(slintKeyText(LogicalKeyboardKey.shiftLeft), '\u0010');
    expect(slintKeyText(LogicalKeyboardKey.metaRight), '\u0018');
    expect(slintKeyText(LogicalKeyboardKey.keyA), isNull);
    expect(slintKeyText(LogicalKeyboardKey.backspace), isNull);
  });

  testWidgets('sizes the target from layout, on a tick, not in build', (
    tester,
  ) async {
    final target = _FakeTarget();
    await tester.pumpWidget(_host(target));
    expect(target.width, 0, reason: 'build itself must not resize');
    await tester.pump();
    expect((target.width, target.height), (2, 1));
  });

  testWidgets('device pixel ratio scales pointer coords and buffer size', (
    tester,
  ) async {
    final target = _FakeTarget();
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(devicePixelRatio: 2.0),
        child: Center(
          child: SizedBox(
            width: 2,
            height: 1,
            child: SlintView(target: target),
          ),
        ),
      ),
    );
    await tester.pump();
    expect((target.width, target.height), (4, 2));

    final topLeft = tester.getTopLeft(find.byType(SlintView));
    final centre = tester.getCenter(find.byType(SlintView));
    final local = centre - topLeft;
    final touch = await tester.createGesture();
    await touch.down(centre);
    expect(target.pointer.last.x, local.dx * 2.0);
    expect(target.pointer.last.y, local.dy * 2.0);
  });

  testWidgets('a DPR change resizes the target immediately', (tester) async {
    final target = _FakeTarget();
    await tester.pumpWidget(_host(target));
    await tester.pump();
    expect((target.width, target.height), (2, 1));

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(devicePixelRatio: 2.0),
        child: Center(
          child: SizedBox(
            width: 2,
            height: 1,
            child: SlintView(target: target),
          ),
        ),
      ),
    );
    await tester.pump();
    expect((target.width, target.height), (4, 2));
  });

  testWidgets('named hardware keys map to Slint key codes', (tester) async {
    final target = await _pump(tester);
    await tester.tap(find.byType(SlintView));
    await tester.pump();
    tester.testTextInput.closeConnection();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(target.keys, ['\uF702', '\u0009', '\u001b']);
  });

  testWidgets('premultiplied Slint pixels reach Flutter unchanged', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final target = await _pump(tester);
      expect(target.width, 2);
      RawImage? raw;
      for (var i = 0; i < 20 && raw?.image == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
        raw = tester.widget<RawImage>(find.byType(RawImage).first);
      }
      final bytes = await raw!.image!.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      expect(
        bytes!.buffer.asUint8List(),
        _frame,
        reason: 'rgba8888 is premultiplied; nothing may re-divide by alpha',
      );
    });
  });

  testWidgets('pointer: buttons, hover, cancel and exit', (tester) async {
    final target = await _pump(tester);
    final centre = tester.getCenter(find.byType(SlintView));

    final mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(centre);
    await mouse.down(centre);
    await mouse.up();
    await mouse.moveTo(const Offset(-10, -10));

    final touch = await tester.createGesture();
    await touch.down(centre);
    await touch.cancel();

    expect(target.pointer.map((e) => (e.kind, e.button)), [
      (SlintPointerEventKind.move, SlintPointerButton.none), // hover
      (SlintPointerEventKind.down, SlintPointerButton.right),
      (SlintPointerEventKind.up, SlintPointerButton.right),
      (SlintPointerEventKind.exit, SlintPointerButton.none),
      (SlintPointerEventKind.down, SlintPointerButton.left),
      (SlintPointerEventKind.up, SlintPointerButton.left), // cancel releases
      (SlintPointerEventKind.exit, SlintPointerButton.none),
    ]);
  });

  testWidgets(
    'a focused view holds a text input connection on every platform',
    (tester) async {
      // Desktop too: the platform's text input plugin turns hardware keys into
      // edits there, so nothing may branch on the platform (which `flutter
      // test` reports as Android anyway).
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final target = await _pump(tester);
      await tester.tap(find.byType(SlintView));
      await tester.pump();
      expect(tester.testTextInput.hasAnyClients, isTrue);

      final pad = tester.testTextInput.editingState!['text'] as String;
      expect(pad, isNotEmpty, reason: 'the mirror leaves something to delete');

      tester.testTextInput.enterText('${pad}hi');
      tester.testTextInput.enterText('${pad}h');
      tester.testTextInput.enterText(
        pad.substring(1),
      ); // deletes 'h' and a pad char
      tester.testTextInput.enterText('${pad.substring(1)}\n');
      expect(target.keys, ['hi', _bs, _bs, _bs, '\n']);

      // A hardware key while the connection owns input must not be double-sent.
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      expect(target.keys, hasLength(5));
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'a selection in the mirror resets it instead of replaying deletes',
    (tester) async {
      final target = await _pump(tester);
      await tester.tap(find.byType(SlintView));
      await tester.pump();
      final pad = tester.testTextInput.editingState!['text'] as String;

      // Select all (Cmd+A on a hardware keyboard), then type: the platform
      // would replace the whole pad, which must not reach Slint as deletes.
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: pad,
          selection: TextSelection(baseOffset: 0, extentOffset: pad.length),
        ),
      );
      final reset = tester.testTextInput.editingState!;
      expect(reset['text'], pad);
      expect(
        (reset['selectionBase'], reset['selectionExtent']),
        (pad.length, pad.length),
      );
      tester.testTextInput.enterText('${pad}x');
      expect(target.keys, ['x']);
    },
  );

  testWidgets(
    'hardware keys are the fallback once the platform closed the connection',
    (tester) async {
      final target = await _pump(tester);
      await tester.tap(find.byType(SlintView));
      await tester.pump();
      final pad = tester.testTextInput.editingState!['text'] as String;

      tester.testTextInput.closeConnection();
      await tester.pump();
      // The framework forgot the connection: platform edits no longer arrive...
      tester.testTextInput.enterText('${pad}dropped');
      expect(target.keys, isEmpty);
      // ...and hardware keys do.
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(target.keys, ['a', _bs, '\n']);

      // The next tap on the still-focused view re-attaches.
      await tester.tap(find.byType(SlintView));
      await tester.pump();
      tester.testTextInput.enterText('${pad}z');
      expect(target.keys, ['a', _bs, '\n', 'z']);
    },
  );
}
