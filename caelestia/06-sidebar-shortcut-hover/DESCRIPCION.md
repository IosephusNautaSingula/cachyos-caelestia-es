<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# fix(drawers): keep the sidebar open when opened by shortcut with sidebar.showOnHover

**Target:** upstream (caelestia-dots/shell). Base: v2.5.0. Independent of the other patches.

## What

With `sidebar.showOnHover: true`, opening the sidebar with its keyboard shortcut (the `sidebar` global shortcut, or
`toggle sidebar` on the `drawers` IPC target) shows it, but it closes as soon as the pointer moves anywhere outside it, or immediately if
the pointer is not over it. The OSD, dashboard and utilities already avoid this with a "shortcut active" flag in
`modules/drawers/Interactions.qml`.

This patch applies the same pattern to the sidebar:

- new `sidebarShortcutActive` and `sidebarPointerOpening` properties;
- every place where the pointer (hover or drag) opens the sidebar sets `sidebarPointerOpening` first;
- `onSidebarChanged()` marks the sidebar as shortcut-opened when it became visible without the pointer;
- while shortcut-opened, leaving the area does not close it; once the pointer enters the sidebar it switches back to
  normal hover control, exactly like the OSD.

## Why

The shortcut is unusable with hover mode enabled: the panel flashes and disappears.

## How to test

```bash
patch -p1 < 06-sidebar-shortcut-hover.patch
```

1. Set `"sidebar": { "showOnHover": true }` in `shell.json` and build/run the shell.
2. Press the sidebar shortcut with the pointer elsewhere: the sidebar stays open.
3. Move the pointer into the sidebar and out again: it now closes, as with hover.
4. Hover the right edge as before: behaviour unchanged. With `showOnHover: false` nothing changes.

Transparency: prepared with AI assistance and reviewed by a person.

---

# fix(drawers): la barra lateral abierta por atajo no se cierra con showOnHover

**Destino:** upstream. Base: v2.5.0. Independiente de los demás parches.

## Qué

Con `sidebar.showOnHover` activado, la barra lateral abierta con su atajo de teclado se cierra en cuanto el ratón no
está sobre ella. El parche aplica el mismo patrón que ya usan el OSD, el panel y las utilidades en `Interactions.qml`
(`sidebarShortcutActive`): abierta por atajo, la salida del ratón no la cierra; al entrar con el ratón pasa al control
normal por hover.

## Por qué

Con el modo hover, el atajo no sirve: el panel aparece y desaparece al instante.

## Cómo probar

Active `showOnHover`, compile y arranque; pulse el atajo con el ratón en otra zona (la barra se queda abierta), entre
y salga con el ratón (se cierra). Con `showOnHover: false` no cambia nada.
