<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# config/ — configuración de usuario

Ficheros de ejemplo para una sesión **Hyprland (configuración en Lua) + Caelestia Shell + UWSM** en CachyOS o Arch.
Parten de los [dots de Caelestia](https://github.com/caelestia-dots/caelestia) y solo contienen lo que cambia
respecto a ellos. Revise cada fichero antes de copiarlo: son preferencias, no requisitos.

| Fichero | Destino | Qué hace |
|---|---|---|
| `hypr/hypr-user.lua` | `~/.config/caelestia/hypr-user.lua` | Escala, teclado español, touchpad natural, sin logotipo, cierre de sesión que vuelve al gestor de inicio, vidrio de los reproductores sin desenfoque, volumen/micrófono/brillo con aceleración (`estacion-ajuste`), y las aplicaciones que piden el foco solo quedan como urgentes (salvo el navegador). |
| `hypr/hypr-vars.lua` | `~/.config/caelestia/hypr-vars.lua` | Navegador de SUPER + W. |
| `caelestia/shell.json` | `~/.config/caelestia/shell.json` | Fuentes, inactividad (bloqueo a los 10 min aunque otra app lo inhiba, pantalla a los 11, suspensión a los 30), pasos de volumen y brillo del 1 %, unidades decimales, barra lateral al pasar el ratón, botón de cerrar sesión con `estacion-cerrar-sesion`. |
| `caelestia/cli.json` | `~/.config/caelestia/cli.json` | Spotify como reproductor y Mission Center como monitor del sistema. |
| `applications/ocultar/*.desktop` | `~/.local/share/applications/` | Ocultan del lanzador entradas que sobran (borrar el fichero las vuelve a mostrar). |
| `applications/autofirma.desktop` | `~/.local/share/applications/` | AutoFirma con el almacén NSS del navegador (ver `guias/autofirma-nss-firefox-zen.md`). |
| `autostart/telegram-bandeja.desktop` | `~/.config/autostart/` | Telegram minimizado en la bandeja al iniciar sesión. |
| `uwsm/env.example`, `uwsm/env-hyprland` | `~/.config/uwsm/` | PATH sin duplicados, tema Qt, editor, carpetas XDG en español, AutoFirma; variables Wayland de Hyprland. |
| `zen/user.js` | perfil del navegador | Permite `userChrome.css` (lo genera `estacion-zen-tema` con los colores de Caelestia). |
| `nvim/init.lua` | `~/.config/nvim/init.lua` | Neovim con el tema de Caelestia. |
| `spotify/spotify-flags.conf` | `~/.config/spotify-flags.conf` | Spotify en Wayland nativo. |
| `spotify/config-xpui.ini.example` | `~/.config/spicetify/config-xpui.ini` | spicetify con el tema de Caelestia (permisos: `spotify-spicetify-acl` en `sistema/`). |
| `vscode/` | `~/.config/Code/User/settings.json`, `~/.config/code-flags.conf` | VS Code en Wayland con el tema de Caelestia. |
| `mise/config.toml` | `~/.config/mise/config.toml` | chezmoi, Node y gitleaks como herramientas de usuario. |
| `mimeapps.list` | `~/.config/mimeapps.list` | Navegador, gestor de archivos y el esquema `afirma://`. |
| `chezmoi/` | repositorio de chezmoi | `.chezmoiignore` que deja fuera secretos, certificados y cachés; plantilla `.chezmoi.toml.tmpl` con los datos del equipo; dos plantillas de ejemplo; gancho `pre-commit` con gitleaks. |

Los ficheros JSON no admiten comentarios: su licencia es la de `LICENSE` en la raíz (GPL-3.0-or-later).

## Dotfiles con chezmoi (resumen)

```bash
mise use -g chezmoi gitleaks
chezmoi init                                   # crea el repositorio local
cp config/chezmoi/dot_chezmoiignore.example "$(chezmoi source-path)/.chezmoiignore"
cp config/chezmoi/chezmoi.toml.tmpl "$(chezmoi source-path)/.chezmoi.toml.tmpl"
install -m 755 config/chezmoi/pre-commit-gitleaks "$(chezmoi source-path)/.git/hooks/pre-commit"
chezmoi add ~/.config/caelestia/hypr-user.lua  # y lo demás que quiera guardar
chezmoi managed                                 # compruebe que no entra nada sensible
```

Mantenga el repositorio privado si guarda en él algo propio, y no añada nunca claves, certificados, bóvedas de
contraseñas ni ficheros `.env`.
