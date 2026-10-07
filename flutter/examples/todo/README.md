# Todo Example

A Slint UI driven through one generated typed API (`TodoApp`), running on
either backend: **interpreter** in debug (`slint_interpreter`) or **AOT** in
release/profile (`slint_compiler`). The list UI (`ui/todo_view.slint`, which
`ui/todo.slint` imports), list state, page scaffolding and codegen test it
shares with `examples/todo_skia` live in `examples/todo_shared`.

```bash
cd examples/todo && mise exec -- flutter run
```

**Full docs:** see the docs site (`just docs-serve`) — Examples → Todo, plus
[Getting started](../../site/content/guides/getting-started.md) and
[Backends](../../site/content/guides/backends.md).
