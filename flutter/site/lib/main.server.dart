/// Server / SSG entry — pre-renders the static docs site.
library;

import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';

import 'app.dart';

/// FOUC-safe boot: apply stored theme before first paint.
const _themeBoot = r'''
(function () {
  try {
    var KEY = 'slint-dart-theme';
    var pref = localStorage.getItem(KEY) || 'system';
    if (pref !== 'light' && pref !== 'dark' && pref !== 'system') pref = 'system';
    var dark = window.matchMedia('(prefers-color-scheme: dark)').matches;
    var resolved = pref === 'system' ? (dark ? 'dark' : 'light') : pref;
    document.documentElement.setAttribute('data-theme', pref);
    document.documentElement.setAttribute('data-theme-resolved', resolved);
    document.documentElement.style.colorScheme = resolved;
  } catch (e) {
    /* private mode / blocked storage */
  }
})();
''';

void main() {
  Jaspr.initializeApp();

  // base: project Pages URL is https://listepo.github.io/slint_dart/
  runApp(Document(
    title: 'slint_dart — Slint UI toolkit ↔ Flutter',
    lang: 'en',
    base: 'slint_dart',
    meta: {
      'description':
          'One typed API over interpreter and AOT backends — plus headless and on-device UI testing.',
      'theme-color': '#0B57D0',
      'color-scheme': 'light dark',
    },
    head: [
      script(content: _themeBoot),
      link(
        href:
            'https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&family=Roboto+Mono:wght@400;500&display=swap',
        rel: 'stylesheet',
      ),
      link(href: 'styles/tokens.css', rel: 'stylesheet'),
      link(href: 'styles/docs.css', rel: 'stylesheet'),
      link(href: 'favicon.svg', rel: 'icon', type: 'image/svg+xml'),
      script(src: 'js/theme.js', defer: true),
    ],
    body: const App(),
  ));
}
