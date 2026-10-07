# slint_dart docs site

Static docs site built with [Jaspr](https://docs.jaspr.site/) (Dart SSG).

```bash
cd site
dart pub get
dart pub global activate jaspr_cli
jaspr build
```

Output: `build/jaspr/`. Project Pages base path: `/slint_dart/`.

Content lives in `web/content/` as Markdown. Routes are listed in `lib/content/catalog.dart`.
