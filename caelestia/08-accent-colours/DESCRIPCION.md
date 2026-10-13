<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# style: replace the secondary accent with primary/neutral colours by area

**Optional aesthetic customisation (not intended for upstream as is).** Base: v2.5.0. Independent of the other
patches (it also applies on top of all of them, in numeric order).

## What

Removes `m3secondary` as an accent colour across the shell and redistributes it by area (28 QML files):

- **Clock and weather** (desktop clock, dashboard clock, lock clock, weather icons and humidity): `m3onSurface`.
- **Performance, lock and warnings** (storage, GPU, network upload, lock-screen resources and password prompt,
  critical notification bodies, warning toasts): `m3primary` / `m3onPrimary`.
- **Active buttons and cards** (`IconButton`, `TextButton`, `IconTextButton` active state, "Keep awake" and screen
  recorder cards, network filter, scroll bar): `m3primary` with `m3onPrimary` text. Inactive ones keep
  `m3secondaryContainer`.
- **Secondary text** (artist, album, window details): `m3onSurfaceVariant`.

## Why

Personal palette choice: with some wallpapers the generated `secondary` colour clashes with `primary`, and the shell
ends up with three competing accents. Using `primary` for "active/important" and neutral colours for the rest gives a
calmer look. It changes the default theme everywhere, so it is published as an optional patch, not as a pull request.

## How to test

```bash
patch -p1 < 08-accent-colours.patch
```

Build and run, then go through the dashboard (all tabs), the lock screen, a notification sent with
`notify-send -u critical "Test" "Critical body"`, the utilities and the network page, with light and dark schemes.
Revert with `patch -R -p1 < 08-accent-colours.patch`.

---

# style: sustituir el acento secondary por primary o neutros según la zona

**Personalización estética opcional (no pensada para upstream tal cual).** Base: v2.5.0. Independiente (también
aplica encima de todos los demás, en orden).

## Qué

Retira `m3secondary` como color de acento y lo reparte por zonas: reloj y tiempo en `m3onSurface`; rendimiento,
bloqueo y avisos en `m3primary`; botones y tarjetas activos en `m3primary` con texto `m3onPrimary` (los inactivos
siguen en `m3secondaryContainer`); textos secundarios en `m3onSurfaceVariant`.

## Por qué

Preferencia de paleta: con algunos fondos el color `secondary` choca con `primary` y la shell acaba con tres acentos.
Cambia el tema por defecto en todas partes, por eso se publica como parche opcional.

## Cómo probar

Aplique el parche, compile y recorra el panel, la pantalla de bloqueo, una notificación crítica
(`notify-send -u critical "Prueba" "Cuerpo"`), las utilidades y la página de red, con esquema claro y oscuro.
