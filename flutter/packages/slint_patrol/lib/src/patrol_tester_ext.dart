import 'package:flutter_test/flutter_test.dart';
import 'package:patrol_finders/patrol_finders.dart';
import 'package:slint/slint.dart';

import 'slint_finder.dart';

/// Slint queries on Patrol's tester, alongside its own `$(...)` finders.
///
/// ```dart
/// await $.slint('Add').tap();
/// await $.slintById('TodoView::edit').enterText('buy milk');
/// expect(TodoApp($.slintComponent()).todoModel, isNotEmpty);
/// ```
extension SlintPatrolTester on PatrolTester {
  /// Finds elements by accessible label — a button's text, a checkbox's
  /// caption. The one to reach for: it matches what a user reads.
  SlintFinder slint(String label, {Finder? view}) => SlintFinder(
    tester: this,
    match: SlintMatch.label,
    value: label,
    view: view,
  );

  /// Finds elements by id, qualified by component: `TodoView::edit`.
  SlintFinder slintById(String id, {Finder? view}) =>
      SlintFinder(tester: this, match: SlintMatch.id, value: id, view: view);

  /// Finds elements by type, e.g. `Button` or `LineEdit`.
  SlintFinder slintByType(String typeName, {Finder? view}) => SlintFinder(
    tester: this,
    match: SlintMatch.type,
    value: typeName,
    view: view,
  );

  /// Finds elements by accessible role, e.g. `Button`, `Checkbox`,
  /// `TextInput`.
  SlintFinder slintByRole(String role, {Finder? view}) => SlintFinder(
    tester: this,
    match: SlintMatch.role,
    value: role,
    view: view,
  );

  /// Every element in the live component's accessibility tree — for exploring
  /// an unfamiliar UI, or for a custom matcher.
  SlintFinder slintAll({Finder? view}) =>
      SlintFinder(tester: this, match: SlintMatch.all, value: '', view: view);

  /// The live component behind the [SlintView], for reading and writing
  /// properties and invoking callbacks.
  SlintInspectableComponent slintComponent({Finder? view}) =>
      slintAll(view: view).component;

  /// Pumps a few frames so Slint can lay out and redraw.
  ///
  /// Use this where a Flutter-only test would call `pumpAndSettle`: a
  /// [SlintView] renders on every frame, so the tree never settles and
  /// `pumpAndSettle` times out.
  Future<void> slintSettle([int frames = 3]) => slintAll().settle(frames);
}
