import 'package:jaspr/jaspr.dart';
import 'package:jaspr_router/jaspr_router.dart';

import 'content/catalog.dart';
import 'content/markdown_doc.dart';
import 'pages/home.dart';

/// Root app — multi-page Router for static generation.
/// Not annotated @client: markdown is read from disk at build time.
class App extends StatelessComponent {
  const App({super.key});

  @override
  Component build(BuildContext context) {
    return Router(
      routes: [
        Route(path: '/', builder: (_, __) => const HomePage()),
        for (final page in docPages)
          if (page.route != '/')
            Route(
              path: page.route,
              builder: (_, __) => MarkdownDocPage(route: page.route),
            ),
      ],
    );
  }
}
