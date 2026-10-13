<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# feat(i18n): add Spanish (es) translation

**Target:** upstream (caelestia-dots/shell). Base: v2.5.0. Independent of the other patches.

## What

Adds a Spanish catalog (all 821 strings) for the existing gettext i18n, generated from `raw.pot` with
`scripts/trs.fish es` on v2.5.0.

- `plugin/src/Caelestia/I18n/trs/es.po`: new.
- `plugin/src/Caelestia/I18n/CMakeLists.txt`: `trs/es.po` added to `po_files`.

It is picked automatically on any Spanish system locale (`es_*` falls back to `es` through `uiLanguages()`), or with
`general.language: "es"`.

## Why

There is no Spanish catalog yet, and Spanish is one of the most widely spoken languages among desktop users.

## Notes for reviewers

- Spanish from Spain, formal register, GNOME/KDE Spanish terminology.
- Protocol names, ids and units stay untranslated, as the `TRANSLATORS:` comments ask.
- M3 variant names are kept as the CLI identifiers (`tonalspot`, `fruitsalad`…) so they match
  `caelestia scheme set -v`; only their descriptions are translated.
- Percentages use a U+202F narrow no-break space (`50 %`), per Spanish typography.
- Two strings are deliberately shorter than a literal translation because their widgets elide text:
  - `up %1` (uptime pill on the dashboard, `modules/dashboard/dash/User.qml`) is translated as just `%1`: the pill
    already has an uptime icon, and a literal "encendido desde hace %1" left only "encendido desde h…" visible.
  - `No media` (dashboard media card) is `Sin multimedia` instead of the longer "Sin contenido multimedia", which was
    elided on all three lines.
- The example in the IP/prefix (CIDR) field of the network pages uses an RFC 5737 documentation address
  (`192.0.2.10/24`) in the translation.
- The header carries no translator name or dates; adjust `Last-Translator`/`PO-Revision-Date` as the project prefers
  (`msgfmt -c` only warns about the missing `PO-Revision-Date`).
- Day and month names from `Time.format()` stay in English even with this catalog; that is fixed separately in
  `02-time-locale` (*fix(services): respect the system locale in Time.format*).

## How to test

```bash
patch -p1 --dry-run < 01-i18n-es.patch && patch -p1 < 01-i18n-es.patch
msgfmt --check-format -c -o /dev/null plugin/src/Caelestia/I18n/trs/es.po   # 821 translated, no errors
cmake -B build -G Ninja && cmake --build build
find build -name es.mo                                                     # the catalog is compiled
```

Then run the shell with `LANG=es_ES.UTF-8` (or `general.language: "es"`) and go through the bar, launcher,
notifications, lock screen and every dashboard tab. Checked so far: `msgfmt --check-format -c`, `trs.fish compile es`,
`%1…%9`, `%n` and `<b>` matched between source and translation for every entry, and daily use of the shell in Spanish
(Qt 6.12, quickshell-git, Hyprland) with no missing or overflowing strings beyond the two shortened ones above.

Transparency: the translation was drafted with AI assistance and then fully reviewed by a native Spanish speaker.

---

# feat(i18n): traducción al español (es)

**Destino:** upstream (caelestia-dots/shell). Base: v2.5.0. Independiente de los demás parches.

## Qué

Añade un catálogo en español (las 821 cadenas) para el sistema gettext existente, generado desde `raw.pot` con
`scripts/trs.fish es` sobre la v2.5.0, y lo registra en `plugin/src/Caelestia/I18n/CMakeLists.txt`.

Se usa automáticamente con cualquier locale español (`es_*` cae en `es` mediante `uiLanguages()`) o con
`general.language: "es"`.

## Por qué

No existe catálogo en español; es una de las lenguas más habladas entre los usuarios de escritorio.

## Notas

- Español de España, registro de usted, terminología de GNOME/KDE en español.
- Nombres de protocolos, identificadores y unidades sin traducir, como piden los comentarios `TRANSLATORS:`.
- Los nombres de variantes M3 se mantienen como identificadores del CLI (`tonalspot`, `fruitsalad`…).
- Porcentajes con espacio fino irrompible U+202F (`50 %`), según la ortotipografía española.
- Dos cadenas son más cortas que una traducción literal porque su widget recorta el texto: `up %1` → `%1` y
  `No media` → `Sin multimedia`.
- El ejemplo del campo IP/prefijo (CIDR) de las páginas de red usa en la traducción una dirección de documentación
  de la RFC 5737 (`192.0.2.10/24`).
- La cabecera no lleva nombre de traductor ni fechas; `msgfmt -c` solo avisa de que falta `PO-Revision-Date`.
- Los nombres de días y meses de `Time.format()` se arreglan aparte en `02-time-locale`.

## Cómo probar

Aplique el parche (`patch -p1 < 01-i18n-es.patch`), compruebe el catálogo con
`msgfmt --check-format -c -o /dev/null plugin/src/Caelestia/I18n/trs/es.po`, compile y arranque la shell con
`LANG=es_ES.UTF-8`; recorra la barra, el lanzador, las notificaciones, la pantalla de bloqueo y todas las pestañas del
panel.

Transparencia: la traducción se redactó con ayuda de IA y la revisó íntegramente un hablante nativo.
