import 'package:slint/slint_core.dart';
import 'package:test/test.dart';

void main() {
  late List<Object?> store;
  late SlintListModel<String> model;

  setUp(() {
    store = <Object?>['a', 'b'];
    model = SlintListModel<String>(
      () => store,
      (snapshot) => store = List<Object?>.from(snapshot as List),
      (wire) => wire as String,
      (value) => value,
    );
  });

  test('reads the current snapshot', () {
    expect(model.toList(), ['a', 'b']);
    expect(model.length, 2);
    expect(model[0], 'a');
  });

  test('insert, remove, and replaceAll write the whole list back', () {
    model.add('c');
    expect(store, ['a', 'b', 'c']);
    model.insert(1, 'x');
    expect(model.toList(), ['a', 'x', 'b', 'c']);
    expect(model.removeAt(0), 'a');
    model.replaceAll(['only']);
    expect(model, ['only']);
  });
}
