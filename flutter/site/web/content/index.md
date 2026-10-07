# Slint UI toolkit ↔ Flutter

One typed API over interpreter and AOT backends — plus headless and on-device UI testing.

Start here: **[Getting started](/guides/getting-started)**.

## Explore

| Section | Contents |
|---|---|
| [Guides](/guides) | Getting started, backends, testing |
| [Packages](/packages) | What each package does and when to use it |
| [Examples](/examples) | Todo apps on each backend |
| [Contributing](/contributing) | Workflow, commands, and PR checklist |

## Layout

A melos monorepo: a pub workspace (root `pubspec.yaml`) plus a Cargo workspace
(root `Cargo.toml`). Packages live under `packages/`, apps under `examples/`.

One typed API, two independent backends behind it:

```
                    ┌─ slint_generator ──▶ foo.g.dart (typed API + embedded source)
.slint file ──▶ ────┤
                    ├─ runtime:      SlintInterpreterFactory
                    └─ compile-time: slint_compiler ──▶ foo.aot.g.dart + app hooks
```

`SlintComponent.load('ui/…')` returns the generated wrapper after one
`register()` at startup. Debug ships the interpreter; release/profile ships
the AOT dylib. App code names neither backend.

Continue with the [package reference](/packages) and the
[backends guide](/guides/backends).
