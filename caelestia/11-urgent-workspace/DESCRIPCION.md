<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# feat(bar): highlight workspaces with an urgent window

**Target:** upstream (caelestia-dots/shell). Base: v2.5.0. Independent of the other patches.

## What

`modules/bar/components/workspaces/Workspace.qml` gets an `urgent` property: true when the workspace is not focused
and Hyprland reports it as urgent (`Hypr.workspaces` → `urgent`). An urgent workspace's indicator is drawn in
`m3primary` and slightly larger (`1/2` scale instead of `1/3`/`1/4`) until the user switches to it; Hyprland clears
the flag on focus.

## Why

When an application requests attention (urgency hint / `xdg-activation` without focus), Hyprland marks its workspace
as urgent, but the bar shows nothing. With `misc:focus_on_activate` disabled (to stop apps stealing focus) this is
the only way to notice that an app on another workspace wants attention.

## How to test

```bash
patch -p1 < 11-urgent-workspace.patch
```

Build and run the shell. In a terminal on workspace 2 run `sleep 3; printf '\a'` and switch to workspace 1 before it
finishes (most terminals set the urgency hint on bell when unfocused), or use any app that requests activation. The workspace-2 indicator turns `primary` and grows; switching to it restores
the normal look.

Transparency: prepared with AI assistance and reviewed by a person.

---

# feat(bar): resaltar los espacios de trabajo con una ventana urgente

**Destino:** upstream. Base: v2.5.0. Independiente de los demás parches.

## Qué

El indicador de un espacio de trabajo que Hyprland marca como urgente (una aplicación pidió atención) se dibuja en
`m3primary` y algo más grande hasta que se entra en él.

## Por qué

Con `misc:focus_on_activate` desactivado (para que las aplicaciones no roben el foco), es el único aviso visible de
que una aplicación de otro espacio de trabajo pide atención.

## Cómo probar

Aplique el parche, compile y arranque. En un terminal del espacio 2 ejecute `sleep 3; printf '\a'` y pase al espacio 1
antes de que termine: el indicador del espacio 2 cambia de color y crece; al entrar en él vuelve a la normalidad.
