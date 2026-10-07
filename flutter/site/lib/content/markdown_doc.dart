import 'dart:io';

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:markdown/markdown.dart' as md;

import '../pages/shell.dart';
import 'catalog.dart';

String _readMarkdown(String file) {
  // jaspr build CWD is site/
  return File('web/content/$file').readAsStringSync();
}

String renderMarkdownFile(String file) {
  return md.markdownToHtml(
    _readMarkdown(file),
    extensionSet: md.ExtensionSet.gitHubFlavored,
  );
}

DocPage? pageForRoute(String route) {
  for (final p in docPages) {
    if (p.route == route) return p;
  }
  return null;
}

class MarkdownDocPage extends StatelessComponent {
  const MarkdownDocPage({required this.route, super.key});

  final String route;

  String get _section {
    if (route.startsWith('/guides')) return 'guides';
    if (route.startsWith('/packages')) return 'packages';
    if (route.startsWith('/examples')) return 'examples';
    if (route.startsWith('/contributing')) return 'contributing';
    return 'home';
  }

  @override
  Component build(BuildContext context) {
    final page = pageForRoute(route);
    final htmlBody = page == null
        ? '<p>Page not found.</p>'
        : renderMarkdownFile(page.file);
    final title = page?.title ?? 'Not found';
    final hasH1 = htmlBody.contains('<h1');

    return Component.fragment([
      siteHeader(active: _section),
      div(classes: 'wrap layout', [
        docsSidebar(currentRoute: route),
        main_(classes: 'doc-body', [
          if (!hasH1) h1([.text(title)]),
          RawText(htmlBody),
        ]),
      ]),
      siteFooter(),
    ]);
  }
}
