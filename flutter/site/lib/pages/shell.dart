import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../content/catalog.dart';

const _iconSun = '''
<svg class="theme-toggle-icon icon-sun" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true">
  <circle cx="12" cy="12" r="4"></circle>
  <path d="M12 2v2M12 20v2M4.93 4.93l1.41 1.41M17.66 17.66l1.41 1.41M2 12h2M20 12h2M4.93 19.07l1.41-1.41M17.66 6.34l1.41-1.41"></path>
</svg>''';

const _iconMoon = '''
<svg class="theme-toggle-icon icon-moon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true">
  <path d="M21 14.5A8.5 8.5 0 1 1 9.5 3a7 7 0 0 0 11.5 11.5z"></path>
</svg>''';

const _iconSystem = '''
<svg class="theme-toggle-icon icon-system" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true">
  <rect x="3" y="4" width="18" height="12" rx="2"></rect>
  <path d="M8 20h8M12 16v4"></path>
</svg>''';

/// Path without leading slash for use under Document(base: 'slint_dart').
String hrefOf(String route) {
  if (route == '/') return './';
  return route.startsWith('/') ? route.substring(1) : route;
}

Component siteHeader({required String active}) {
  final links = [
    ('Guides', 'guides'),
    ('Packages', 'packages'),
    ('Examples', 'examples'),
    ('Contributing', 'contributing'),
    ('GitHub', 'https://github.com/listepo/slint_dart'),
  ];
  return header(classes: 'site-header', [
    div(classes: 'wrap site-header-inner', [
      a(classes: 'brand', href: './', [
        img(src: 'images/logo.svg', alt: '', width: 28, height: 28),
        span([.text('slint_dart')]),
      ]),
      nav(classes: 'nav', attributes: {'aria-label': 'Primary'}, [
        for (final (label, href) in links)
          a(
            href: href,
            classes: active == label.toLowerCase() ? 'is-active' : null,
            [.text(label)],
          ),
        button(
          type: ButtonType.button,
          id: 'theme-toggle',
          classes: 'theme-toggle',
          attributes: {
            'data-theme': 'system',
            'aria-label': 'Theme: system (follows OS)',
          },
          [
            RawText(_iconSun),
            RawText(_iconMoon),
            RawText(_iconSystem),
            span(attributes: {'data-theme-label': ''}, [.text('system')]),
          ],
        ),
      ]),
    ]),
  ]);
}

Component siteFooter() {
  return footer(classes: 'site-footer', [
    div(classes: 'wrap site-footer-inner', [
      span([.text('Listepo / slint_dart')]),
      span([
        a(href: 'https://github.com/listepo/slint_dart', [.text('GitHub')]),
        .text(' · '),
        a(href: 'https://github.com/listepo/slint_dart#readme', [.text('README')]),
      ]),
    ]),
  ]);
}

Component docsSidebar({required String currentRoute}) {
  DocPage? sectionOf(String prefix) {
    for (final p in docPages) {
      if (p.route == prefix) return p;
    }
    return null;
  }

  List<DocPage> childrenOf(String prefix) {
    return [
      for (final p in docPages)
        if (p.route != prefix &&
            p.route.startsWith('$prefix/') &&
            p.route != '/')
          p,
    ];
  }

  Component navSection(String title, String prefix) {
    final kids = childrenOf(prefix);
    return div([
      h4([.text(title)]),
      a(
        href: hrefOf(prefix),
        classes: currentRoute == prefix ? 'is-active' : null,
        [.text(sectionOf(prefix)?.title ?? title)],
      ),
      for (final p in kids)
        a(
          href: hrefOf(p.route),
          classes: currentRoute == p.route ? 'is-active' : null,
          [.text(p.title)],
        ),
    ]);
  }

  return aside(classes: 'sidebar', attributes: {'aria-label': 'Docs'}, [
    navSection('Guides', '/guides'),
    navSection('Packages', '/packages'),
    navSection('Examples', '/examples'),
    h4([.text('Meta')]),
    a(
      href: 'contributing',
      classes: currentRoute == '/contributing' ? 'is-active' : null,
      [.text('Contributing')],
    ),
  ]);
}
