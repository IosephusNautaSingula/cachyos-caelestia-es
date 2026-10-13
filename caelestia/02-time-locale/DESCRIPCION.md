<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# fix(services): respect the system locale in Time.format

**Target:** upstream (caelestia-dots/shell). Base: v2.5.0. Independent of the other patches.

## What

`Time.format()` calls `Qt.formatDateTime(date, fmt)`. With a format string, Qt 6 uses the C locale, so the lock
screen date (`dddd • d MMM`), the bar day (`ddd`) and the desktop clock (`MMMM`, `dddd`) are always in English, while
the calendar and weather dates already follow `Qt.locale()`.

This switches it to `Qt.locale().toString(clock.date, fmt)` (one line in `services/Time.qml`).

## Why

Day and month names stay in English on every non-English system, even with a translation catalog installed.

| Format (es_ES) | Before | After |
|---|---|---|
| `dddd • d MMM` | `Monday • 1 Mar` | `lunes • 1 mar` |
| `ddd` | `Sun` | `dom` |
| `hh:mm:A` | `12:30:PM` | `12:30:P. M.` |

Side effects: English locales see no difference. Locales with native digits (e.g. ar_EG, fa_IR) now show them in the
clock, which is the expected localisation. Nothing parses `Time.format()`/`hourStr`/`minuteStr` as numbers, so this is
display-only. With the 12-hour clock the AM/PM marker becomes localised; `timeStr.split(":")` still works because
localised markers contain no colon.

## How to test

```bash
patch -p1 < 02-time-locale.patch
```

Build and run the shell with `LANG=es_ES.UTF-8` (or any non-English locale): the lock screen shows e.g.
`LUNES • 1 MAR` instead of `MONDAY • 1 MAR`, and the bar shows the localised short day. With `LANG=en_US.UTF-8`
the output is identical to before. Quick offscreen check without the shell:
`Qt.locale("es_ES").toString(new Date(), "dddd • d MMM")` in any QML file run with `QT_QPA_PLATFORM=offscreen`.

Transparency: prepared with AI assistance and reviewed by a person.

---

# fix(services): respetar el locale del sistema en Time.format

**Destino:** upstream. Base: v2.5.0. Independiente de los demás parches.

## Qué

`Time.format()` usa `Qt.formatDateTime(date, fmt)`, que con cadena de formato emplea siempre el locale C en Qt 6: la
fecha de la pantalla de bloqueo, el día de la barra y el reloj de escritorio salen en inglés. El parche usa
`Qt.locale().toString(clock.date, fmt)`.

## Por qué

Los nombres de días y meses quedan en inglés en cualquier sistema que no esté en inglés, aunque haya traducción.
En inglés no cambia nada; en locales con dígitos propios (árabe, persa…) el reloj pasa a mostrarlos, que es lo
esperable.

## Cómo probar

Aplique el parche, compile y arranque la shell con `LANG=es_ES.UTF-8`: la pantalla de bloqueo muestra
`LUNES • 1 MAR` en vez de `MONDAY • 1 MAR`. Con `LANG=en_US.UTF-8` el resultado es idéntico al anterior.
