<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# Estación: parches para Caelestia Shell

> **Summary (English).** Eleven independent patches for [Caelestia Shell](https://github.com/caelestia-dots/shell)
> v2.5.0, one per fix, each ready to be proposed as a pull request: a Spanish translation (all 821 strings), locale-aware dates
> and numbers, two usability fixes (sidebar shortcut with hover mode, "Keep awake" vs. idle timeouts), clicking a
> notification to go to its app, and highlighting urgent workspaces in the bar. Three more (03, 05, 08) are optional
> colour customisations, not meant for upstream as is. Every patch applies cleanly with `patch -p1` on v2.5.0, alone
> or all together in numeric order. Each directory has a `DESCRIPCION.md` with the PR text in English (title, what,
> why, how to test) followed by a Spanish version. `PKGBUILD.example` builds an Arch package, `caelestia-shell-es`,
> with the chosen patches.

Este directorio forma parte de Estación, una configuración libre de escritorio para CachyOS/Arch con Hyprland y
Caelestia Shell pensada para la comunidad hispanohablante. Aquí están los cambios hechos a Caelestia Shell, separados
en un parche por arreglo para poder proponerlos al proyecto original (caelestia-dots/shell) o aplicarlos en local.

## Parches

| N.º | Directorio | Título (estilo conventional commits) | Destino |
|---|---|---|---|
| 01 | `01-i18n-es/` | feat(i18n): add Spanish (es) translation | upstream |
| 02 | `02-time-locale/` | fix(services): respect the system locale in Time.format | upstream |
| 03 | `03-battery-tank-colours/` | style(dashboard): neutral track and container fill for the battery tank | opcional (estético) |
| 04 | `04-weather-locale/` | fix(weather): locale-aware date and number formatting | upstream |
| 05 | `05-bar-osd-colours/` | style(bar,osd): status capsule, power button and OSD fill in secondaryContainer | opcional (estético) |
| 06 | `06-sidebar-shortcut-hover/` | fix(drawers): keep the sidebar open when opened by shortcut with sidebar.showOnHover | upstream |
| 07 | `07-keep-awake-overrides-idle/` | fix(idle): make the "Keep awake" toggle disable every idle timeout | upstream |
| 08 | `08-accent-colours/` | style: replace the secondary accent with primary/neutral colours by area | opcional (estético) |
| 09 | `09-decimal-separator/` | fix(i18n): use the locale's decimal separator for data sizes and Ethernet speed | upstream |
| 10 | `10-notification-click-to-app/` | feat(notifs): clicking a notification takes you to its app | upstream |
| 11 | `11-urgent-workspace/` | feat(bar): highlight workspaces with an urgent window | upstream |

- **Para upstream:** 01, 02, 04, 06, 07, 09, 10 y 11. Son generales: no dependen de este equipo ni de ninguna
  configuración concreta.
- **Opcionales:** 03, 05 y 08 son personalizaciones estéticas de color (no pensadas para upstream tal cual). Cambian
  el aspecto del tema por defecto; aplíquelas solo si le gustan.
- El 09 (separador decimal en tamaños y velocidad) va como PR aparte y no como ampliación del 04: toca otros ficheros
  y otra área, y así cada PR cubre un solo arreglo (véase su `DESCRIPCION.md`).
- El 10 define el hint de notificación `x-caelestia-log` (`journal:<unidad>` o la ruta absoluta de un fichero dentro
  de `${XDG_STATE_HOME:-$HOME/.local/state}`), que usan los avisos de los scripts de Estación para abrir su registro
  al pulsarlos.

Cada directorio contiene:

- `NN-nombre.patch`: diff unificado con rutas `a/` y `b/`, aplicable con `patch -p1` en la raíz de caelestia-shell
  v2.5.0. La primera línea es la licencia (`# SPDX-…`), que `patch` ignora.
- `DESCRIPCION.md`: texto del PR en inglés (título, qué, por qué, cómo probar) y, debajo, en español.

## Cómo probar un parche

Desde la raíz del código fuente de caelestia-shell v2.5.0 (tarball de la versión publicada):

```bash
tar xzf caelestia-shell-v2.5.0.tar.gz
cd caelestia-shell-v2.5.0
patch -p1 --dry-run -F0 < /ruta/a/caelestia/04-weather-locale/04-weather-locale.patch   # comprobar
patch -p1 -F0 < /ruta/a/caelestia/04-weather-locale/04-weather-locale.patch             # aplicar
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_INSTALL_PREFIX=/
cmake --build build
```

Para aplicar todos, hágalo en orden numérico (`for p in /ruta/a/caelestia/*/*.patch; do patch -p1 -F0 < "$p"; done`).
Cada `DESCRIPCION.md` explica qué mirar en la shell después de instalarla; para revertir un parche use
`patch -R -p1 < fichero.patch`.

Comprobación hecha sobre v2.5.0: cada parche aplica por separado sin desplazamientos ni *fuzz* (`-F0`), y los once
juntos en orden numérico también.

## Cómo construir el paquete (Arch/CachyOS)

`PKGBUILD.example` construye `caelestia-shell-es`, que sustituye a `caelestia-shell` (`provides`/`conflicts`). Aplica
los parches de la lista `_apply`; los opcionales (03, 05, 08) están comentados.

```bash
mkdir -p ~/compilar/caelestia-shell-es
cd ~/compilar/caelestia-shell-es
cp /ruta/a/caelestia/PKGBUILD.example PKGBUILD
cp /ruta/a/caelestia/*/*.patch .
less PKGBUILD          # revíselo antes de construir
makepkg -si            # pide confirmación antes de instalar
```

No use nunca `--noconfirm`: lea lo que se va a instalar y confirme a mano. Si cambia algún parche, actualice su
`sha256sums` (`sha256sum *.patch`) o ejecute `updpkgsums` si tiene instalado `pacman-contrib`. Para volver al paquete
oficial basta con reinstalar `caelestia-shell`.

## Licencia

GPL-3.0-or-later (véase `LICENSE` en la raíz del proyecto). Caelestia Shell se distribuye bajo GPL-3.0-only; estos
parches son compatibles con ella.
