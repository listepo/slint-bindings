import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import 'shell.dart';

class HomePage extends StatelessComponent {
  const HomePage({super.key});

  static const cards = [
    ('Guides', 'guides', 'Getting started, backends, and testing'),
    ('Packages', 'packages', 'What each package does and when to use it'),
    ('Examples', 'examples', 'Todo apps on each backend'),
    ('Contributing', 'contributing', 'Workflow, commands, and PR checklist'),
  ];

  @override
  Component build(BuildContext context) {
    return Component.fragment([
      siteHeader(active: 'home'),
      div(classes: 'wrap', [
        section(classes: 'hero', [
          span(classes: 'hero-badge', [.text('Melos · pub · Cargo')]),
          h1([.text('Slint UI toolkit ↔ Flutter')]),
          p(classes: 'hero-sub', [
            .text(
              'One typed API over interpreter and AOT backends — plus headless and on-device UI testing.',
            ),
          ]),
          a(classes: 'cta cta-filled', href: 'guides/getting-started', [
            .text('Getting started'),
          ]),
        ]),
        h2([.text('Explore')]),
        div(classes: 'card-grid', [
          for (final (title, href, sub) in cards)
            a(classes: 'card', href: href, [
              h3([.text(title)]),
              p([.text(sub)]),
            ]),
        ]),
        h2([.text('Layout')]),
        p([
          .text(
            'A melos monorepo: a pub workspace (root pubspec.yaml) plus a Cargo workspace (root Cargo.toml). Packages live under packages/, apps under examples/.',
          ),
        ]),
        p([
          .text('One typed API, two independent backends behind it.'),
        ]),
        pre([
          .text(
            '                    ┌─ slint_generator ──▶ foo.g.dart (typed API + embedded source)\n'
            '.slint file ──▶ ────┤\n'
            '                    ├─ runtime:      SlintInterpreterFactory\n'
            '                    └─ compile-time: slint_compiler ──▶ foo.aot.g.dart + app hooks',
          ),
        ]),
        p([
          .text('Start with '),
          a(href: 'guides/getting-started', [.text('Getting started')]),
          .text(', then the '),
          a(href: 'packages', [.text('package reference')]),
          .text(' and '),
          a(href: 'guides/backends', [.text('backends guide')]),
          .text('.'),
        ]),
      ]),
      siteFooter(),
    ]);
  }
}
