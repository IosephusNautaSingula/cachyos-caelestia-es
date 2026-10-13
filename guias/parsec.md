<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# Cliente de Parsec en CachyOS o Arch

Parsec (escritorio remoto de baja latencia) como **cliente**, para conectarse a otros equipos. Lo peculiar: el
paquete solo trae un **cargador**; el programa real lo descarga y actualiza **él mismo** en `~/.parsec`, fuera de
pacman. Esta guía explica cómo instalarlo, qué excluir de la copia y cómo enterarse cuando cambia.

## Requisitos

- CachyOS: `parsec-bin` está en el repositorio `cachyos` (firmado). Arch: `parsec-bin` de AUR.
- Para vídeo por hardware con GPU Intel: `intel-media-driver` (VA-API). Audio: PipeWire con `pipewire-alsa`
  (Parsec usa ALSA y PipeWire lo recoge).

## Cómo comprobar si le afecta

```bash
pacman -Qi parsec-bin 2>/dev/null | grep -E '^(Nombre|Name|Repositorio|Repository|Versi)'
ls ~/.parsec/ 2>/dev/null       # parsecd-*.so, appdata.json, config.txt, user.bin, log.txt
```

## Pasos

1. Instalar (confirme usted cada paso, sin respuestas automáticas):
   ```bash
   sudo pacman -S --needed cachyos/parsec-bin     # CachyOS
   paru -S --needed parsec-bin                     # Arch (AUR): revise el PKGBUILD
   ```
   En AUR, el PKGBUILD descarga un `.deb` de una URL **sin versión**: la suma sha256 deja de coincidir en cuanto
   Parsec publica otro, aunque el paquete no haya cambiado. Si `makepkg` falla por la suma, compruebe el origen antes
   de actualizarla.
2. Cómo funciona: `/usr/bin/parsecd` copia `/usr/share/parsec/skel` a `~/.parsec` y carga la
   `parsecd-<versión>.so` que indica `~/.parsec/appdata.json` (con su sha256). Las versiones nuevas las descarga
   Parsec solo a `~/.parsec`; no hay opción documentada para desactivarlo.
3. **Copia de seguridad** (`/etc/estacion/excluir.txt`): fuera lo que se regenera solo; dentro la configuración.
   ```
   /home/*/.parsec/parsecd-*.so
   /home/*/.parsec/appdata.json
   /home/*/.parsec/log.txt
   ```
   `config.txt` y `user.bin` sí entran en la copia (cifrada). `user.bin` es **su sesión**: nunca a dotfiles
   (`.chezmoiignore`: `.parsec/user.bin`).
4. Cortafuegos: como cliente no hay que abrir nada (salida permitida por defecto en ufw).
5. **Vigilancia de cambios**: el comprobador semanal `estacion-comprobar-caelestia` registra las `parsecd-*.so` de
   `~/.parsec` con su sha256 en `${XDG_STATE_HOME:-~/.local/state}/estacion/` y avisa (notificación + registro) si
   cambian, con lo anterior y lo nuevo. Equivalente manual:
   ```bash
   sha256sum ~/.parsec/parsecd-*.so | tee -a "${XDG_STATE_HOME:-$HOME/.local/state}/estacion/parsec-so.txt"
   ```
   Cuando avise: abra Parsec y compruebe que inicia sesión, conecta y que la imagen y el sonido funcionan.

## Verificación

```bash
parsecd &                                  # o desde el lanzador; inicie sesión y conéctese a un equipo
grep -iE 'vaapi|decoder|audio' ~/.parsec/log.txt | tail     # decodificador por hardware y audio
hyprctl clients | grep -A8 'class: parsecd' | grep -E 'xwayland|class'   # en Hyprland va por XWayland
```

Que Parsec pruebe primero VDPAU de NVIDIA y siga si no hay es normal en equipos Intel.

## Marcha atrás

```bash
sudo pacman -Rns parsec-bin
rm -r ~/.parsec            # borra también su sesión y su configuración
```
