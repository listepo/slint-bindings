import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:slint/slint_core.dart'
    show
        SlintPointerButton,
        SlintPointerEvent,
        SlintPointerEventKind,
        SlintSourceTree,
        writeSlintTree;
import 'package:slint_skia/slint_skia.dart';
import 'package:todo_shared/todo_shared.dart';

import 'todo.g.dart';

// The same ui/todo.slint as examples/todo, on the slint_skia backend: the
// Skia engine compiles the source todo.g.dart embeds, the Dart side owns the
// list and pushes it into `todo-model`, and slint-skia-ffi renders the frame
// on the GPU into a Flutter external texture shown with `Texture`. What the
// backend does not do yet — deliver callbacks — the page says on screen
// instead of pretending (see the slint_skia package page, "Shortcuts &
// Ceilings").

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TodoExampleApp(title: 'Slint Todo (Skia)', home: TodoPage()));
}

class TodoPage extends StatefulWidget {
  const TodoPage({super.key});

  @override
  State<TodoPage> createState() => _TodoPageState();
}

// The list, its callbacks and the page chrome live in examples/todo_shared;
// this page drives the Skia engine and talks to it only through the generated
// TodoApp wrapper, mapping entries to the generated TodoItem.
class _TodoPageState extends State<TodoPage>
    with TodoPageStateMixin, SingleTickerProviderStateMixin {
  SkiaSlintEngine? _engine;
  SkiaSlintComponent? _component;
  TodoApp? _app;
  SkiaTextureRenderTarget? _target;
  SlintSourceTree? _sourceTree;
  Ticker? _ticker;

  /// The texture is being created; its callbacks own the component.
  bool _creating = false;

  /// The GPU path failed; the reason is in [_ceilings].
  bool _stopped = false;

  /// Where the backend stopped short, in the words of its own exceptions.
  final List<String> _ceilings = [];

  /// The layout's size in physical pixels (Slint's scale factor stays 1),
  /// applied on the next tick.
  double _dpr = 1;
  int _wantedWidth = 0;
  int _wantedHeight = 0;

  /// Button held since the last down event; up/cancel events carry none.
  SlintPointerButton _pressedButton = SlintPointerButton.none;

  @override
  void initState() {
    super.initState();
    try {
      final engine = _engine = SkiaSlintEngine();
      // Compiling is one FFI call. The Skia engine hands back the file's
      // root as a single definition (a documented ceiling), so select by
      // name only once it enumerates them.
      // The source imports the shared list UI, which the compiler resolves
      // from disk: write the tree the wrapper embeds and compile its entry.
      final tree = writeSlintTree(
        TodoApp.slintSource,
        TodoApp.slintFiles,
        name: 'todo.slint',
      );
      _sourceTree = tree;
      final defs = engine.compile(TodoApp.slintSource, path: tree.path);
      final def = defs.length == 1
          ? defs.single
          : defs.firstWhere((d) => d.name == TodoApp.componentName);
      final component = _component = def.instantiate() as SkiaSlintComponent;
      _wire(_app = TodoApp(component));
      syncTodos();
      _ticker = createTicker(_onTick)..start();
    } catch (e) {
      loadError = e;
    }
  }

  void _wire(TodoApp app) {
    // Callbacks are not delivered by the Skia backend yet; keep the list
    // Dart-owned and say so rather than silently dropping taps.
    try {
      app
        ..onAddTodo(addTodo)
        ..onToggleTodo(toggleTodo)
        ..onRemoveDone(removeDone);
    } on UnimplementedError catch (e) {
      _ceilings.add('$e');
    }
  }

  @override
  void pushTodos(List<TodoEntry> items) {
    _app?.todoModel.replaceAll([
      for (final e in items) TodoItem(title: e.title, checked: e.checked),
    ]);
  }

  /// Creates the texture at the first bounded size, then resizes and renders
  /// it once per frame.
  void _onTick(Duration _) {
    final width = _wantedWidth;
    final height = _wantedHeight;
    if (width <= 0 || height <= 0) return;
    final target = _target;
    try {
      if (target == null) {
        _create(width, height);
      } else {
        target.resize(width, height);
        target.render();
      }
    } catch (e) {
      _stop(e);
    }
  }

  void _create(int width, int height) {
    final component = _component;
    if (_creating || component == null) return;
    _creating = true;
    SkiaTextureRenderTarget.create(component, width, height).then(
      (target) {
        _creating = false;
        if (mounted) {
          setState(() => _target = target);
        } else {
          target.dispose(); // disposes the component
        }
      },
      onError: (Object e) {
        _creating = false;
        if (mounted) {
          _stop(e);
        } else {
          component.dispose();
        }
      },
    );
  }

  void _stop(Object error) {
    _ticker?.stop();
    setState(() {
      _stopped = true;
      if (!_ceilings.contains('$error')) _ceilings.add('$error');
    });
  }

  @override
  void dispose() {
    _ticker?.dispose();
    final target = _target;
    if (target != null) {
      target.dispose(); // disposes the component
    } else if (!_creating) {
      _component?.dispose();
    } // else _create's callbacks dispose it when the texture lands.
    _engine?.dispose();
    _sourceTree?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => buildTodoScaffold(
    backend: 'SkiaSlintEngine',
    body: () => Column(
      children: [
        Expanded(child: LayoutBuilder(builder: _texture)),
        for (final c in _ceilings)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(c, style: Theme.of(context).textTheme.bodySmall),
          ),
      ],
    ),
  );

  Widget _texture(BuildContext context, BoxConstraints constraints) {
    _dpr = MediaQuery.devicePixelRatioOf(context);
    _wantedWidth = _physical(constraints.maxWidth);
    _wantedHeight = _physical(constraints.maxHeight);
    final target = _target;
    if (target == null) {
      return _stopped
          ? const SizedBox.shrink()
          : const Center(child: CircularProgressIndicator());
    }
    // ponytail: pointer input only. SlintView's Focus + TextInputClient is
    // the pattern to copy once typing into the texture matters.
    return MouseRegion(
      onExit: (_) => _pointer(SlintPointerEventKind.exit, null),
      child: Listener(
        onPointerDown: (event) {
          _pressedButton = _buttonOf(event.buttons);
          _pointer(SlintPointerEventKind.down, event, button: _pressedButton);
        },
        onPointerMove: (event) => _pointer(SlintPointerEventKind.move, event),
        onPointerHover: (event) => _pointer(SlintPointerEventKind.move, event),
        onPointerUp: _release,
        onPointerCancel: (event) {
          _release(event);
          _pointer(SlintPointerEventKind.exit, null);
        },
        onPointerSignal: (event) {
          if (event is PointerScrollEvent) {
            _pointer(
              SlintPointerEventKind.scroll,
              event,
              scroll: -event.scrollDelta,
            );
          }
        },
        child: SizedBox.expand(child: Texture(textureId: target.textureId)),
      ),
    );
  }

  int _physical(double logical) =>
      logical.isFinite ? (logical * _dpr).toInt().clamp(0, 1 << 30) : 0;

  static SlintPointerButton _buttonOf(int buttons) {
    if (buttons & kSecondaryButton != 0) return SlintPointerButton.right;
    if (buttons & kMiddleMouseButton != 0) return SlintPointerButton.middle;
    return SlintPointerButton.left;
  }

  void _release(PointerEvent event) {
    _pointer(SlintPointerEventKind.up, event, button: _pressedButton);
    _pressedButton = SlintPointerButton.none;
  }

  void _pointer(
    SlintPointerEventKind kind,
    PointerEvent? event, {
    SlintPointerButton button = SlintPointerButton.none,
    Offset scroll = Offset.zero,
  }) {
    final at = (event?.localPosition ?? Offset.zero) * _dpr;
    _target?.dispatchPointerEvent(
      SlintPointerEvent(
        kind: kind,
        x: at.dx,
        y: at.dy,
        button: button,
        scrollDeltaX: scroll.dx * _dpr,
        scrollDeltaY: scroll.dy * _dpr,
      ),
    );
  }
}
