<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# fix(i18n): use the locale's decimal separator for data sizes and Ethernet speed

**Target:** upstream (caelestia-dots/shell). Base: v2.5.0. Independent of the other patches (it does not need
`04-weather-locale`).

## What

`Units.formatBytes()`, `Units.formatKibUsage()` (`plugin/src/Caelestia/I18n/Units.qml`) and the Ethernet link speed in
`services/Nmcli.qml` format numbers with `toFixed()`, which always uses a dot. This patch replaces the dot with
`Qt.locale().decimalPoint` through a small private helper, `_localeDecimal()`.

| Where (es_ES) | Before | After |
|---|---|---|
| Storage / memory | `12.5 / 256.0 GB` | `12,5 / 256,0 GB` |
| Network rate | `1.5 MB/s` | `1,5 MB/s` |
| Ethernet speed | `2.5 Gbps` | `2,5 Gbps` |

The digits are exactly the same as before and no thousands grouping is added, so **English output is unchanged**.

## Why a separate PR (and not an extension of 04)

It was first planned as an extension of the weather PR, but it touches different files (the I18n plugin's `Units.qml`
and the network service) and a different feature area. Keeping one fix per PR makes both easier to review and to
revert, and neither depends on the other: `04-weather-locale` adds `Strings.number()` for the UI layer, while this one
stays inside the compiled I18n plugin module, separate from `qs.utils`.

## How to test

```bash
patch -p1 < 09-decimal-separator.patch
```

Build and run with `LANG=es_ES.UTF-8`: the dashboard's Performance tab and the lock screen show `12,5 / 256,0 GB`, and
network rates use a comma. With `LANG=en_US.UTF-8` nothing changes.

Transparency: prepared with AI assistance and reviewed by a person.

---

# fix(i18n): separador decimal del idioma en tamaños de datos y velocidad Ethernet

**Destino:** upstream. Base: v2.5.0. Independiente (no necesita el 04).

## Qué

`formatBytes()`, `formatKibUsage()` y la velocidad Ethernet usan `toFixed()`, que siempre pone punto. El parche lo
sustituye por `Qt.locale().decimalPoint`: «12,5 / 256,0 GB». Mismos dígitos y sin separador de miles, así que en inglés
no cambia nada.

## Por qué va aparte y no como ampliación del 04

Se pensó como ampliación del PR del tiempo, pero toca otros ficheros (`Units.qml` del módulo I18n y `Nmcli.qml`) y otra
área. Un arreglo por PR es más fácil de revisar y de revertir, y ninguno depende del otro.

## Cómo probar

Aplique el parche, compile y arranque con `LANG=es_ES.UTF-8`: el almacenamiento y la memoria se muestran con coma
decimal. Con `LANG=en_US.UTF-8` no cambia nada.
