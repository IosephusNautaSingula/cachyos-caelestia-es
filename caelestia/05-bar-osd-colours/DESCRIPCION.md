<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# style(bar,osd): status capsule, power button and OSD fill in secondaryContainer

**Optional aesthetic customisation (not intended for upstream as is).** Base: v2.5.0. Independent of the other
patches.

## What

- `modules/bar/components/StatusIcons.qml`: the status capsule background becomes `m3secondaryContainer` (instead of
  the translucent `surfaceContainer`) and its icons `m3onSecondaryContainer`.
- `modules/bar/components/Power.qml`: the power button gets a round `m3secondaryContainer` background, with the icon
  and the hover layer in `m3onSecondaryContainer` (instead of the `m3error` icon).
- `components/controls/FilledSlider.qml` (OSD volume/brightness sliders): the filled part uses
  `m3secondaryContainer` instead of `m3secondary`.

## Why

Personal taste: it makes the status area of the bar and the OSD match the dashboard's pill style, with the same
container colour and contrast-safe content colour. It changes the look of the default theme, so it is offered as an
optional patch, not as a pull request.

## How to test

```bash
patch -p1 < 05-bar-osd-colours.patch
```

Build and run; look at the bottom of the bar (status icons and power button) and change the volume or brightness to
see the OSD. Try light and dark schemes. Revert with `patch -R -p1`.

---

# style(barra,osd): cápsula de estado, botón de apagado y OSD en secondaryContainer

**Personalización estética opcional (no pensada para upstream tal cual).** Base: v2.5.0. Independiente.

## Qué

La cápsula de iconos de estado y el botón de apagado de la barra pasan a fondo `m3secondaryContainer` con contenido
`m3onSecondaryContainer`, y el relleno de los deslizadores del OSD usa `m3secondaryContainer`.

## Por qué

Preferencia estética: igualar la barra y el OSD con el estilo de píldora del panel. Cambia el aspecto del tema por
defecto, por eso se ofrece como parche opcional.

## Cómo probar

Aplique el parche, compile y observe la parte inferior de la barra y el OSD al cambiar volumen o brillo, con esquema
claro y oscuro. Se revierte con `patch -R -p1`.
