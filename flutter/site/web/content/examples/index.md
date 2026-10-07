Working apps in the monorepo. Same typed API; different backends and layouts.

| Example | What it shows |
|---|---|
| [todo](/examples/todo) | Interpreter + AOT on one typed `TodoApp`, hooks, tree-shaking canary |
| [todo_shared](/examples/todo_shared) | Shared list UI + `TodoStore` imported by the app examples |
| [todo_skia](/examples/todo_skia) | Same shared list on the experimental Skia GPU backend |
