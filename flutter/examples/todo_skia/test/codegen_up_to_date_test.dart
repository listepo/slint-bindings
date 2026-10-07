import 'package:test/test.dart';
import 'package:todo_shared/testing.dart';
import 'package:todo_skia_example/todo.g.dart';

/// Runs only where `slint-skia-ffi` can be built (CI with Skia cached):
/// `flutter test` runs every dependency's build hook first, and this app
/// depends on `slint_skia`.
void main() {
  testWrapperEmbedsCurrentSlint(TodoApp.slintSource, TodoApp.slintFiles);

  test('the Skia example carries no tree-shaking canary', () {
    // UnusedGadget proves AOT tree-shaking in examples/todo; there is no AOT
    // here, and the Skia engine enumerates a single definition anyway.
    expect(TodoApp.slintSource, isNot(contains('UnusedGadget')));
  });
}
