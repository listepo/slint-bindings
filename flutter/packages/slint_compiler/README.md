# slint_compiler

AOT backend for the wrappers `slint_generator` emits: `.slint` files compiled
ahead of time with `slint-build` into the app's own code asset — **no
slint-interpreter at runtime**. The interpreter path is independent.

```yaml
dependencies:
  slint_compiler: ^0.0.1
```

**Full docs:** [slint_compiler package page](https://listepo.github.io/slint_dart/packages/slint_compiler/) (pipeline, tree-shaking, size breakdown), [Backends guide](https://listepo.github.io/slint_dart/guides/backends/).
