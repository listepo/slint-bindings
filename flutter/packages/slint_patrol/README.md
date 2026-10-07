# slint_patrol

Drive Slint UIs from [Patrol](https://patrol.leancode.co) tests. Slint paints
into one Flutter widget, so Patrol's `$(...)` alone is not enough — this
package adds `$.slint(...)` finders over the live accessibility tree and
real Flutter gestures.

```yaml
dev_dependencies:
  slint_patrol: ^0.0.1
```

**Full docs:** [slint_patrol package page](https://listepo.github.io/slint_dart/packages/slint_patrol/), [Testing guide](https://listepo.github.io/slint_dart/guides/testing/).
