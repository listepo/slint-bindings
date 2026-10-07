/// Content routes for the Jaspr docs site.
/// Paths must not end with `/` (jaspr_router assertion), except `/`.
class DocPage {
  const DocPage({required this.route, required this.file, required this.title});
  final String route;
  final String file;
  final String title;
}

const docPages = <DocPage>[
  DocPage(route: '/', file: 'index.md', title: 'Slint UI toolkit ↔ Flutter'),
  DocPage(route: '/contributing', file: 'contributing.md', title: 'Contributing'),
  DocPage(route: '/examples', file: 'examples/index.md', title: 'Examples'),
  DocPage(route: '/examples/todo', file: 'examples/todo.md', title: 'Todo'),
  DocPage(route: '/examples/todo_shared', file: 'examples/todo_shared.md', title: 'Todo shared'),
  DocPage(route: '/examples/todo_skia', file: 'examples/todo_skia.md', title: 'Todo Skia'),
  DocPage(route: '/guides', file: 'guides/index.md', title: 'Guides'),
  DocPage(route: '/guides/backends', file: 'guides/backends.md', title: 'Backends'),
  DocPage(route: '/guides/getting-started', file: 'guides/getting-started.md', title: 'Getting started'),
  DocPage(route: '/guides/testing', file: 'guides/testing.md', title: 'Testing'),
  DocPage(route: '/packages', file: 'packages/index.md', title: 'Packages'),
  DocPage(route: '/packages/slint', file: 'packages/slint.md', title: 'slint'),
  DocPage(route: '/packages/slint_build', file: 'packages/slint_build.md', title: 'slint_build'),
  DocPage(route: '/packages/slint_compiler', file: 'packages/slint_compiler.md', title: 'slint_compiler'),
  DocPage(route: '/packages/slint_generator', file: 'packages/slint_generator.md', title: 'slint_generator'),
  DocPage(route: '/packages/slint_interpreter', file: 'packages/slint_interpreter.md', title: 'slint_interpreter'),
  DocPage(route: '/packages/slint_patrol', file: 'packages/slint_patrol.md', title: 'slint_patrol'),
  DocPage(route: '/packages/slint_skia', file: 'packages/slint_skia.md', title: 'slint_skia'),
  DocPage(route: '/packages/slint_testing', file: 'packages/slint_testing.md', title: 'slint_testing'),
];
