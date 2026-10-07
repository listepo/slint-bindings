/// Input events forwarded from Flutter into a Slint scene.
///
/// The numeric encodings below cross the FFI boundary — keep them in sync
/// with `slint-dart-core`'s `events` module:
/// kind: 0=move, 1=down, 2=up, 3=scroll, 4=exit
/// button: 0=none, 1=left, 2=right, 3=middle
enum SlintPointerEventKind { move, down, up, scroll, exit }

enum SlintPointerButton { none, left, right, middle }

final class SlintPointerEvent {
  const SlintPointerEvent({
    required this.kind,
    required this.x,
    required this.y,
    this.button = SlintPointerButton.none,
    this.scrollDeltaX = 0,
    this.scrollDeltaY = 0,
  });

  final SlintPointerEventKind kind;
  final double x;
  final double y;
  final SlintPointerButton button;
  final double scrollDeltaX;
  final double scrollDeltaY;
}

final class SlintKeyEvent {
  const SlintKeyEvent({required this.text, required this.pressed});

  final String text;
  final bool pressed;
}
