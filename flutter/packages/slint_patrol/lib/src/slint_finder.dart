import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol_finders/patrol_finders.dart';
import 'package:slint/slint.dart';
import 'package:slint_testing/slint_testing.dart';

/// Thrown when a Slint element cannot be found, cannot be acted on, or the
/// widget tree holds no inspectable Slint view.
class SlintPatrolException implements Exception {
  SlintPatrolException(this.message);

  final String message;

  @override
  String toString() => 'SlintPatrolException: $message';
}

/// How a [SlintFinder] matches elements.
enum SlintMatch {
  /// The accessible label — a button's text, a checkbox's caption.
  label,

  /// An element id qualified by its component, `TodoView::edit`.
  id,

  /// The element's type, `Button`, `LineEdit`.
  type,

  /// The accessible role, `Button`, `Checkbox`, `TextInput`.
  role,

  /// Every element in the tree; the matched text is ignored.
  all,
}

/// A lazy query for elements inside a live Slint component.
///
/// Slint draws its whole UI into one Flutter widget, so Flutter's own finders
/// see a single opaque box. This finds elements in the component's
/// accessibility tree instead, and acts on them through real Flutter gestures
/// aimed at where the element actually sits on screen — the same path a
/// user's finger takes, not a test-only side door.
///
/// Like a [PatrolFinder], it is lazy: nothing is queried until you await it.
class SlintFinder {
  SlintFinder({
    required this.tester,
    required this.match,
    required this.value,
    this.view,
    this.index,
  });

  /// The Patrol tester this finder pumps and gestures through.
  final PatrolTester tester;

  /// Which [SlintView] to search, when the tree holds more than one.
  final Finder? view;

  /// Which match to narrow to, if [at] or [first] was used.
  final int? index;

  /// What this finder matches on.
  final SlintMatch match;

  /// The text being matched.
  final String value;

  /// Narrows this finder to the element at [index] among the matches.
  SlintFinder at(int index) => SlintFinder(
    tester: tester,
    match: match,
    value: value,
    view: view,
    index: index,
  );

  /// Narrows this finder to the first match.
  SlintFinder get first => at(0);

  /// Restricts the search to the [SlintView] found by [view], for a screen
  /// showing more than one.
  SlintFinder inView(Finder view) => SlintFinder(
    tester: tester,
    match: match,
    value: value,
    view: view,
    index: index,
  );

  Finder get _viewFinder => view ?? find.byType(SlintView);

  /// The live component behind the [SlintView] this finder searches.
  SlintInspectableComponent get component {
    final views = tester.tester.widgetList<SlintView>(_viewFinder).toList();
    if (views.isEmpty) {
      throw SlintPatrolException(
        'no SlintView in the widget tree — pump the app first',
      );
    }
    if (views.length > 1 && view == null) {
      throw SlintPatrolException(
        'the widget tree holds ${views.length} SlintViews — say which one '
        'with inView()',
      );
    }
    final component = views.first.target.component;
    if (component is! SlintInspectableComponent) {
      throw SlintPatrolException(
        'this Slint backend does not support element queries '
        '(${component.runtimeType}). The interpreter backend does, which is '
        'what debug builds — including flutter test — use; the AOT backend '
        'of release and profile builds does not.',
      );
    }
    return component;
  }

  /// The matches as of right now, without pumping or waiting.
  List<SlintElementInfo> get current {
    final found = switch (match) {
      SlintMatch.label => component.queryElements('label', value),
      SlintMatch.id => component.queryElements('id', value),
      SlintMatch.type => component.queryElements('type', value),
      // Slint has no role query; filter the whole tree the way
      // `slint_testing` does.
      SlintMatch.role =>
        component
            .queryElements('all')
            .where((e) => e['role'] == value)
            .toList(),
      SlintMatch.all => component.queryElements('all'),
    };
    final elements = found.map(SlintElementInfo.fromJson).toList();
    final index = this.index;
    if (index == null) return elements;
    return index < elements.length ? [elements[index]] : const [];
  }

  /// Whether anything matches right now.
  bool get exists => current.isNotEmpty;

  /// How many elements match right now.
  int get count => current.length;

  /// Waits until at least one element matches and has a non-zero size, then
  /// returns every match.
  ///
  /// Size matters because Slint lays out during rendering: an element found
  /// before the first frame reports a zero rect, which is not yet somewhere
  /// you can click.
  Future<List<SlintElementInfo>> waitUntilVisible({Duration? timeout}) async {
    final limit = timeout ?? tester.config.visibleTimeout;
    // The test clock is fake, so wall-clock waiting would hang; spend the
    // timeout as frames instead.
    final frames = (limit.inMilliseconds / 16).ceil().clamp(1, 100000);
    List<SlintElementInfo> found = const [];
    for (var frame = 0; frame < frames; frame++) {
      found = current;
      if (found.isNotEmpty && found.every((e) => e.hasSize)) return found;
      await tester.tester.pump(const Duration(milliseconds: 16));
    }
    throw SlintPatrolException(
      found.isEmpty
          ? 'found no Slint element with ${match.name} "$value" within $limit'
          : 'the Slint element with ${match.name} "$value" is still zero-sized '
                'after $limit — is it laid out?',
    );
  }

  /// Waits for the single element this finder resolves to.
  ///
  /// Throws when several match, so a test never silently acts on an arbitrary
  /// one; narrow with [first] or [at] when that is what you mean.
  Future<SlintElementInfo> resolve({Duration? timeout}) async {
    final found = await waitUntilVisible(timeout: timeout);
    if (found.length > 1) {
      throw SlintPatrolException(
        '${found.length} Slint elements match ${match.name} "$value" — '
        'narrow with first or at(index): ${found.join(', ')}',
      );
    }
    return found.single;
  }

  /// Taps the element's centre with a real Flutter gesture.
  Future<void> tap({Duration? timeout}) async {
    final element = await resolve(timeout: timeout);
    await tester.tester.tapAt(_globalCentre(element));
    await settle();
  }

  /// Taps the element, then types [text] the way the platform would.
  ///
  /// The tap is what gives the element focus, and a focused [SlintView] holds
  /// a text input connection on every platform (a soft keyboard, or the
  /// desktop text input plugin behind a hardware keyboard). Text goes in
  /// through that connection, as it would from either — the app's real input
  /// path, not key events, which [SlintView] ignores while the connection is
  /// open so a physical keyboard never types twice.
  Future<void> enterText(String text, {Duration? timeout}) async {
    await tap(timeout: timeout);
    final ime = tester.tester.testTextInput;
    if (!ime.hasAnyClients) {
      throw SlintPatrolException(
        'the tap did not give SlintView a text input connection — is the '
        'view focusable?',
      );
    }
    // Replace the field contents rather than append to whatever the IME still holds.
    ime.updateEditingValue(TextEditingValue(text: text));
    await settle();
  }

  /// Pumps a few frames so Slint can react and redraw.
  ///
  /// Deliberately not `pumpAndSettle`: [SlintView] drives a [Ticker] that
  /// renders every frame, so the tree never goes quiescent and settling would
  /// always time out. A fixed handful of frames is what "let it catch up"
  /// means for a continuously rendering view.
  Future<void> settle([int frames = 3]) async {
    for (var frame = 0; frame < frames; frame++) {
      await tester.tester.pump(const Duration(milliseconds: 16));
    }
  }

  /// Where the element's centre sits in Flutter's global coordinates.
  ///
  /// Slint reports geometry in its own logical pixels, and [SlintView] scales
  /// Flutter's logical coordinates by the device pixel ratio on the way in, so
  /// dividing by that ratio converts back. Reading the ratio from the view's
  /// own context keeps this in step with whatever [SlintView] used.
  Offset _globalCentre(SlintElementInfo element) {
    final rect = tester.tester.getRect(_viewFinder);
    final dpr = MediaQuery.devicePixelRatioOf(
      tester.tester.element(_viewFinder),
    );
    return rect.topLeft +
        Offset(
          (element.x + element.width / 2) / dpr,
          (element.y + element.height / 2) / dpr,
        );
  }

  @override
  String toString() => 'SlintFinder(${match.name}: "$value")';
}
