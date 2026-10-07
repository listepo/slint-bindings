import 'dart:io';

import 'package:slint_compiler/src/rust_glue.dart' show slintVersion;
import 'package:test/test.dart';

void main() {
  // The generated AOT crate sits outside the Cargo workspace, so it pins
  // Slint itself. A bump (Dependabot's Slint PR touches only the root file)
  // must reach it too, or release builds link a different Slint than debug.
  test('slintVersion is the Slint the Cargo workspace pins', () {
    final root = File('../../Cargo.toml').readAsStringSync();
    expect(root, contains('slint = { version = "=$slintVersion"'));
  });
}
