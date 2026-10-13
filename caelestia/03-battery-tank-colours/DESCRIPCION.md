<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# style(dashboard): neutral track and container fill for the battery tank

**Optional aesthetic customisation (not intended for upstream as is).** Base: v2.5.0. Independent of the other
patches.

## What

In the Performance tab, the battery "tank" (`modules/dashboard/performance/BatteryTank.qml`) is drawn with the
`secondary` colour family. This patch changes it to:

- track (empty part): `m3surfaceContainerHighest` instead of `m3secondaryContainer`;
- fill (charge level): `m3secondaryContainer` instead of `m3secondary`;
- accent and text on the fill: `m3primaryFixed` and `m3onSecondaryContainer`.

## Why

A matter of taste: with some wallpapers the default `secondary` fill is very saturated and competes with the CPU/GPU
gauges. The neutral track keeps the charge level readable while the tank looks calmer. It is a personal palette
choice, so it is published as an optional patch rather than as a pull request.

## How to test

```bash
patch -p1 < 03-battery-tank-colours.patch
```

Build, open the dashboard (Performance tab) on a laptop with a battery and compare with light and dark schemes
(`caelestia scheme set …`). Revert with `patch -R -p1 < 03-battery-tank-colours.patch`.

---

# style(dashboard): pista neutra y relleno «container» en el depósito de batería

**Personalización estética opcional (no pensada para upstream tal cual).** Base: v2.5.0. Independiente.

## Qué

En la pestaña de Rendimiento, el depósito de batería pasa a tener la pista en `m3surfaceContainerHighest` y la carga
en `m3secondaryContainer`, con texto en `m3onSecondaryContainer`.

## Por qué

Cuestión de gusto: con algunos fondos el relleno `secondary` resulta muy saturado. Es una preferencia de paleta, por
eso se publica como parche opcional y no como PR.

## Cómo probar

Aplique el parche, compile y abra el panel (pestaña Rendimiento) en un portátil, con esquemas claro y oscuro. Se
revierte con `patch -R -p1`.
