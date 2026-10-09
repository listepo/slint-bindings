# Slint Bindings

Вбудовує інтерфейси [Slint](https://slint.dev) у нативні застосунки: `NSView` / SwiftUI
на macOS і елемент WinUI 3 на Windows. Цикл подій належить хосту.
Пізніше те саме ядро малює дерева Weft (сусідній проєкт `weft`) нативно, а вебзбірка
використовує його знову через WebAssembly.

У Slint немає офіційної інтеграції зі Swift чи WinUI (див. [research.md](../../research.md)).
Підтримуваний спосіб вбудовування — власна платформа (`slint::platform`); на ній і зібрано проєкт.

**Статус:** M2. Ядро малює на CPU в буфер, яким володіє хост.
macOS-хост збирається, а шлях демо покритий тестами без вікна, включно з клавіатурою
та композицією IME. WinUI-хост збирається в CI: віртуальні клавіші, композиція IME
(коли ОС дає `CoreTextEditContext`) і нативна DLL на кожен RID.
Вікно WinUI тут не запускалося.

## Склад

| Шлях | Що це |
| --- | --- |
| `crates/slint-bindings-core` | Платформа Slint, якою керує хост: програмний рендерер у RGBA-буфер викликача, введення, таймери. Тут живе демо-компонент. |
| `crates/slint-bindings-ffi` | C ABI `sb_*` поверх ядра (статична бібліотека для Swift, DLL для WinUI). Лише пересилає виклики. |
| `flutter/` | Копія [slint_dart](https://github.com/listepo/slint_dart). Крейт `slint-embed` (`flutter/packages/slint/rust/embed`) — спільна програмна платформа, карта подій Dart FFI і перевірка UI-потоку. |
| `swift/` | Пакунок SwiftPM: `CSlintBindings` (модуль C над згенерованим заголовком), `SlintBindings` (`SlintHost`, `SlintNSView`, `SlintDemoView`), застосунок `SlintDemo`. |
| `windows/` | Елемент WinUI 3 `SlintPanel` і демо-застосунок. |

```text
SwiftUI / AppKit ─┐                       ┌─ WinUI 3 (C#)
  SlintDemoView   │   sb_* C ABI          │   SlintPanel
  SlintNSView     ├──▶ slint-bindings-ffi ◀┤   SlintHost (P/Invoke)
  SlintHost       │         │             │
                  │   slint-bindings-core │
                  │   (slint-embed        │
                  │    SoftwareRenderer)  │
```

## Як виходить кадр

1. Хост стежить за розміром і масштабом і викликає `sb_host_resize`.
2. На кожному тіку (`CADisplayLink` на macOS, `CompositionTarget.Rendering` у WinUI)
   хост викликає `sb_tick`, потім `sb_host_render`. Slint перемальовує кадр лише коли щось змінилось.
3. Хост показує кадр (вміст шару `CGImage` на macOS — RGBA8;
   `WriteableBitmap` у WinUI — BGRA8 з `sb_host_render_bgra`).
4. Миша, прокрутка, клавіатура і фокус повертаються через `sb_host_*`
   у логічних точках від лівого верхнього кута.

Усі виклики йдуть з UI-потоку хоста: об'єкти Slint однопотокові.

## Збірка і запуск (macOS, Apple Silicon)

```sh
mise install      # Rust 1.99, cargo-nextest, just; cbindgen через `cargo install cbindgen`
just check        # fmt, clippy, тести, дрейф заголовка, дрейф P/Invoke, swift build, swift test
just swift-run    # відкриває вікно демо SwiftUI
```

Windows: див. [windows/README.md](windows/README.md).

## Документи

- [plan.md](../../plan.md): етапи й поточні задачі
- [research.md](../../research.md): як можна вбудувати Slint, з джерелами
- [toolchain.md](../../toolchain.md): програми й пакунки
- [English](../../README.md), [Русский](../ru/README.md)

## Ліцензія

Apache-2.0. Див. [LICENSE](../../LICENSE).
