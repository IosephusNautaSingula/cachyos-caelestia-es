<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# fix(weather): locale-aware date and number formatting

**Target:** upstream (caelestia-dots/shell). Base: v2.5.0. Independent of the other patches.

## What

The weather tab and the lock-screen forecast build dates and numbers with fixed English patterns, so on other locales
they read wrong even though month and day names are already localised:

| Where | Before (es_ES) | After (es_ES) |
|---|---|---|
| Weather tab date — `toLocaleDateString(Qt.locale(), "dddd, MMMM d")` | `lunes, marzo 1` | `lunes, 1 de marzo` |
| 7-day forecast — `toLocaleDateString(Qt.locale(), "MMM d")` | `mar 2` | `2 mar` |
| Wind — `"%1 km/h".arg(Weather.windSpeed)` | `4.5 km/h` | `4,5 km/h` |
| Sunrise/sunset, lock forecast hours (12-hour clock) — `Qt.formatDateTime(…)` | `3:30 PM` | `3:30 P. M.` |

No per-locale patterns are hard-coded. Three helpers in `utils/Strings.qml` derive them from the system locale:

- `longDateNoYear(date)`: the locale's own `Locale.LongFormat` with the year removed;
- `shortDayMonth(date)`: `"d MMM"` or `"MMM d"` following the day/month order of the locale's `Locale.ShortFormat`;
- `number(value)`: `Qt.locale().toString(value, "g", 15)`, i.e. the same digits as before with the locale's separator.

Sunrise/sunset and the lock forecast hours switch from `Qt.formatDateTime()` (C locale) to `Qt.locale().toString()`.

## Why

Day/month order and the decimal separator are part of the locale; fixed English patterns produce dates such as
"marzo 1" that no Spanish (or German, French, Polish…) speaker would write.

**English output is unchanged.** Offscreen QML check (Qt 6.12):

| Locale | Long date | Short date | Number | `h:mm A` / `ha` |
|---|---|---|---|---|
| en_US | `Monday, March 1` (same) | `Mar 2` (same) | `4.5` (same) | `3:30 PM` / `3pm` (same) |
| en_GB | `Monday, 1 March` | `2 Mar` | `4.5` | same |
| es_ES | `lunes, 1 de marzo` | `2 mar` | `4,5` | `3:30 P. M.` |
| de_DE | `Montag, 1. März` | `2. März` | `4,5` | — |
| fr_FR | `lundi 1 mars` | `2 mars` | `4,5` | — |
| pl_PL | `poniedziałek, 1 marca` | `2 mar` | `4,5` | — |

Known limitation: for CJK locales the short date becomes `10月 12`, readable but not ideal.

Data sizes (`Units.qml`) and the Ethernet speed (`Nmcli.qml`) have the same decimal-point problem; they are fixed in a
separate PR (`09-decimal-separator`) so that each PR covers one area.

## How to test

```bash
patch -p1 < 04-weather-locale.patch
```

Build and run with `LANG=es_ES.UTF-8`: the weather tab shows `lunes, 1 de marzo`, the wind `4,5 km/h` and
forecast dates such as `2 mar`. With `LANG=en_US.UTF-8` everything is as before. The helpers can be checked offscreen
(`QT_QPA_PLATFORM=offscreen`) by calling them with different `Qt.locale("xx_YY")` values.

Transparency: prepared with AI assistance and reviewed by a person.

---

# fix(weather): fechas y números del tiempo según el locale

**Destino:** upstream. Base: v2.5.0. Independiente de los demás parches.

## Qué

La pestaña del tiempo y la previsión de la pantalla de bloqueo usan patrones fijos en inglés («marzo 1», «mar 2»,
«4.5 km/h»). El parche añade tres funciones en `utils/Strings.qml` (`longDateNoYear`, `shortDayMonth`, `number`) que
derivan el formato del locale del sistema, y cambia `Qt.formatDateTime()` por `Qt.locale().toString()` en salida y
puesta del sol y en las horas de la previsión.

## Por qué

El orden día/mes y el separador decimal dependen del idioma. En inglés la salida no cambia (comprobado en QML fuera
de pantalla con en_US y en_GB). Los tamaños de datos y la velocidad Ethernet van en un PR aparte (`09`).

## Cómo probar

Aplique el parche, compile y arranque con `LANG=es_ES.UTF-8`: «lunes, 1 de marzo», «4,5 km/h», «2 mar». Con
`LANG=en_US.UTF-8` todo queda igual que antes.
