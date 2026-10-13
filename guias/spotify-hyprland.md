<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# Spotify en Hyprland: spicetify con ACL mínima, vidrio con opacidad y Wayland nativo

## Requisitos

- `spotify` (AUR), `spicetify-cli` (AUR) y, si quiere la tienda, `spicetify-marketplace-bin` (AUR); `acl` para
  `setfacl`.
- Hyprland (aquí, con la configuración Lua de los dots de Caelestia, que etiqueta los reproductores como
  `music_player`).
- `ESTACION_USUARIO` en `/etc/estacion/estacion.conf`.

## Cómo comprobar si le afecta

```bash
pacman -Q spotify spicetify-cli 2>/dev/null
getfacl -p /opt/spotify /opt/spotify/Apps | grep -E '^(# file|user:)'
stat -c '%a %U %n' /opt/spotify /opt/spotify/Apps
hyprctl clients | grep -B2 -A12 'class: [Ss]potify' | grep -E 'xwayland|tags'
sudo ss -ltnp | grep -i spotify          # ¿hay un puerto de depuración 9222 abierto?
```

## 1. spicetify con ACL mínima

spicetify necesita escribir en `/opt/spotify`. Muchas guías proponen dar permiso de escritura a todos los usuarios (cualquier usuario y
cualquier programa podría modificar Spotify): **no lo haga**. Conceda escritura **solo a su usuario** con ACL:

```bash
sudo setfacl -m "u:usuario:rwx" /opt/spotify                 # solo el directorio, no recursivo
sudo setfacl -R -m "u:usuario:rwX" /opt/spotify/Apps          # Apps y su contenido
sudo setfacl -R -d -m "u:usuario:rwX" /opt/spotify/Apps       # lo que se cree después hereda la ACL
```

Cada actualización de `spotify` reinstala `/opt/spotify` y pierde las ACL. El hook
`/etc/pacman.d/hooks/spotify-spicetify.hook` (PostTransaction, `Install`/`Upgrade` de `spotify`) ejecuta
`/usr/local/bin/spotify-spicetify-acl`, que las vuelve a poner y le recuerda aplicar spicetify **como usuario, no
root**:

```bash
spicetify backup apply
```

Al cambiar el esquema de colores de Caelestia (`caelestia scheme set …`) se reescribe el `color.ini` del tema
`caelestia` de spicetify, pero Spotify no se entera solo: `spicetify refresh` y reinicie Spotify (`refresh` no lo
reinicia).

**No** lance Spotify con `spicetify watch -s`: abre un puerto de depuración en `127.0.0.1:9222`. Lance `spotify` a
secas (en los dots de Caelestia: `~/.config/caelestia/cli.json` → `toggles.music.spotify.command = ["spotify"]`).

## 2. Efecto vidrio solo con opacidad

Spotify por XWayland declara toda la ventana «dañada» unas 25 veces por segundo mientras suena y está visible, y
Hyprland recompone y **recalcula el desenfoque** en cada fotograma. Con desenfoque, la GPU integrada sube mucho. Use
solo opacidad, sin desenfoque ni sombra (regla de la etiqueta `music_player`, en `config/hypr/hypr-user.lua`):

```lua
hl.window_rule({ match = { tag = "music_player", fullscreen = false },
  opacity = "0.85 override 0.80 override", no_blur = true, no_shadow = true })
```

Se probó `decoration:blur:special = true` y no hubo diferencia visible ni medible: no compensa.

Medir sin root (GPU Intel): la residencia en RC6 y la frecuencia real de la GPU,
`/sys/class/drm/card*/gt/gt0/rc6_residency_ms` y `gt_act_freq_mhz`, durante 20 s con y sin el cambio.
(`intel_gpu_top` necesita `CAP_PERFMON`.)

## 3. Wayland nativo

`/usr/bin/spotify` lee `~/.config/spotify-flags.conf`:

```
--enable-features=UseOzonePlatform,WaylandWindowDecorations
--ozone-platform=wayland
```

En la medición de referencia (visible y sonando), el uso de GPU bajó aproximadamente a la mitad y desapareció el
proceso Xwayland de la ecuación.

Qué vigilar unos días: que no se cuelgue ni se quede en negro al volver de suspensión o al mostrar/ocultar su espacio
especial; que el atajo siga abriéndolo y la ventana caiga en su espacio (si la regla casa por `initial_title`
«Spotify|Spotify Free», compruébelo); menús contextuales en su sitio; teclas multimedia y la tarjeta MPRIS de la
barra; el tema de spicetify tras `refresh`; y que tras actualizar Spotify el fichero se siga leyendo.

## Verificación

```bash
getfacl -p /opt/spotify/Apps | grep "user:usuario:rwx"
hyprctl clients | grep -A12 'class: [Ss]potify' | grep -E 'xwayland: 0|music_player'
sudo ss -ltnp | grep ':9222' || echo "sin puerto de depuración"
```

## Marcha atrás

```bash
rm ~/.config/spotify-flags.conf                       # vuelve a XWayland (cierre y abra Spotify)
spicetify restore                                     # Spotify original
sudo setfacl -R -b /opt/spotify
sudo rm /etc/pacman.d/hooks/spotify-spicetify.hook /usr/local/bin/spotify-spicetify-acl
```
