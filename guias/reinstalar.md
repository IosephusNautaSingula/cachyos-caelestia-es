<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# Reconstruir un equipo desde cero: CachyOS + copia restic + instalar.sh

Para un **disco nuevo**, un equipo nuevo o un sistema irrecuperable. Si el sistema solo no arranca, pruebe antes
lo menos drástico: arrancar una instantánea desde Limine ([restaurar.md](restaurar.md)) o, con disco cifrado, el
rescate desde el live ([cifrado-luks2-tpm2-limine.md](cifrado-luks2-tpm2-limine.md)).

## Requisitos

- Una **copia restic reciente y comprobada** ([copias-restic-smb.md](copias-restic-smb.md)) y, accesibles desde
  **otro dispositivo** (el móvil), la contraseña del repositorio, las credenciales SMB del NAS y, si cifra, la frase.
- Un USB de 4 GB o más para el instalador.
- Este repositorio (el árbol `sistema/`, `config/`, `caelestia/`, `paquetes/`, `guias/`): clónelo o tenga una copia
  en el NAS o en el USB.
- Cargador y red (wifi de casa con el NAS encendido).

## Cómo comprobar si le afecta

Le afecta si no puede arrancar ni la entrada normal, ni la del kernel LTS, ni ninguna instantánea de Limine, y el
rescate del cifrado no lo arregla; o si estrena disco o equipo. Antes de borrar nada, compruebe que la copia es
legible desde otro equipo o desde el live:

```bash
sudo restic -r /mnt/estacion-nas/restic snapshots     # con el NAS montado (vea restaurar.md, apartado D)
```

## 1. Preparar el USB

1. Descargue de la web oficial de CachyOS la ISO *Desktop* con sus ficheros `.sha256` y `.sig` y verifique:
   ```bash
   sha256sum -c cachyos-desktop-linux-*.iso.sha256
   gpg --verify cachyos-desktop-linux-*.iso.sig cachyos-desktop-linux-*.iso   # huella publicada por CachyOS
   ```
2. Identifique el USB **sin margen de error**: `lsblk -o NAME,SIZE,MODEL,TRAN,MOUNTPOINTS` antes y después de
   enchufarlo; el nuevo, con `TRAN=usb`, es el suyo. El disco interno (p. ej. `nvme0n1`) **nunca**.
3. Grábelo (borra el USB; cambie `sdX`):
   ```bash
   sudo dd if=cachyos-desktop-linux-XXXX.iso of=/dev/sdX bs=4M status=progress oflag=sync conv=fsync
   ```

## 2. Instalar CachyOS

| Pantalla | Elección |
|---|---|
| Idioma, zona, teclado | Español (España), su zona, teclado español (pruebe `ñ ç - ¡` en la caja de prueba) |
| Gestor de arranque | **Limine** |
| Particiones | Borrar disco · **btrfs** · sin swap (CachyOS usa zram) · cifrado opcional (vea abajo) |
| Escritorio | **Sin escritorio**: Hyprland, Caelestia y SDDM los instala la reconstrucción, sin ajustes del instalador que pisar |
| Usuario | El **mismo nombre de usuario** que en la copia (simplifica restaurar `/home`) |

Sobre el cifrado: puede marcar «Cifrar el sistema» en el instalador (más sencillo en una instalación nueva) o
instalar sin cifrar y cifrar después en el sitio con la guía de cifrado. La frase: palabras en minúsculas de la *a*
a la *z* separadas por espacios (se teclea igual con teclado español o inglés en la pantalla de arranque).

Revise el resumen (Limine, btrfs, el disco correcto) e instale.

## 3. Primer arranque

1. Inicie sesión en la consola de texto. Wifi: `nmtui` → Activar una conexión. Pruebe: `ping -c2 archlinux.org`.
2. Paquetes mínimos y montaje del NAS:
   ```bash
   sudo pacman -Syu --needed restic cifs-utils rsync git
   sudo install -d -m 700 /mnt/estacion-nas
   sudo mount -t cifs //nas.local/copias /mnt/estacion-nas \
     -o username=usuario-copias,vers=3.1.1,seal,uid=0,gid=0,file_mode=0600,dir_mode=0700
   ```
   `error(13)` = contraseña SMB incorrecta. Si `nas.local` no resuelve, use la IP del NAS.
3. Si trae el repositorio o un script desde el NAS o un USB, **compare su suma sha256** con la que guardó en su
   gestor de contraseñas antes de ejecutarlo. Si no coincide, no lo ejecute.

## 4. Restaurar /home y reinstalar los programas

Siga [restaurar.md](restaurar.md), apartado D: restaure la última copia a `/var/tmp/r`, copie su carpeta personal
con `rsync -aHAX` (sin sesión gráfica abierta) y reinstale los programas desde las listas guardadas
(`paquetes-explicitos-repositorios.txt` con pacman; los de AUR y locales con paru o makepkg, revisando cada
PKGBUILD). Como alternativa a las listas de la copia, `paquetes/paquetes-por-funcion.txt` de este repositorio.

**Nunca** copie `/etc` entero de la copia sobre el sistema nuevo: lleva UUID de discos, `machine-id`, `fstab` y
`crypttab` de la instalación anterior. Tome solo lo personalizado, fichero a fichero.

## 5. instalar.sh

1. Configuración del equipo (sin secretos, `0644`):
   ```bash
   sudo install -d -m 755 /etc/estacion
   sudo install -m 644 sistema/estacion.conf.example /etc/estacion/estacion.conf
   sudoedit /etc/estacion/estacion.conf      # su usuario, NAS, red de casa, touchpad…
   ```
2. Secretos de la copia (root, `0600`; **la misma** contraseña del repositorio para seguir usando las copias
   anteriores). Vea [copias-restic-smb.md](copias-restic-smb.md), paso 2.
3. Ejecute el instalador (consulte antes su ayuda; cada componente se puede instalar por separado y enseña lo que va
   a cambiar):
   ```bash
   sudo bash sistema/instalar.sh --ayuda
   ```
   Componentes: `copia`, `touchpad`, `bluetooth`, `red`, `endurecimiento`, `energia`, `avisos`, `escritorio`. El
   instalador **no** cifra el disco: eso va aparte, con `sistema/cifrado/`.
4. Paquetes de la interfaz: Caelestia Shell con la traducción y los parches de `caelestia/` (paquete local
   `caelestia-shell-es`, con `makepkg` como usuario) y su configuración de `config/`.
5. Reinicie: SDDM → sesión **Hyprland (uwsm)**.

## 6. Después

- Instantáneas y menú: `sudo limine-snapper-sync` y, si falta, la configuración `home` de snapper
  ([snapper-limine.md](snapper-limine.md)).
- Primera copia en el sistema nuevo: `sudo estacion-copia --ahora` y `sudo estacion-copia restic check`.
- Si cifró en el instalador y quiere TPM2 + PIN, clave de recuperación y copias de cabeceras: apartado 5 de la guía
  de cifrado. Las órdenes de ese apartado (`systemd-cryptenroll`, `luksHeaderBackup`) valen igual sobre un cifrado
  hecho por el instalador; antes de usar `cifrado-primer-arranque.sh` en ese caso, lea su ayuda y compruebe que los
  nombres de los mapeos y los UUID de `cifrado.conf` coinciden con los de su `crypttab`.
- AutoFirma: abrirlo una vez y ejecutar `estacion-autofirma-nss` con el navegador cerrado
  ([autofirma-nss-firefox-zen.md](autofirma-nss-firefox-zen.md)).
- Limpieza: `sudo umount /mnt/estacion-nas && sudo rm -r /var/tmp/r`.

## Verificación

```bash
systemctl --failed
systemctl list-timers 'estacion-*'; systemctl --user list-timers 'estacion-*'
sudo estacion-copia restic snapshots | tail -3
sudo snapper list-configs
pacman -Qqe | wc -l       # comparable al de paquetes-explicitos.txt de la copia
```

## Si algo falla

- **No arranca el USB:** elíjalo en el menú de arranque del firmware (F12, F2 o Esc según el fabricante).
- **No hay wifi en la consola:** `nmcli device wifi list` y `nmcli device wifi connect "RED" --ask`.
- **No aparece SDDM tras reiniciar:** Ctrl+Alt+F3, inicie sesión y `sudo systemctl enable --now sddm`.
- **Una etapa del instalador falla:** corrija y relance solo ese componente; son idempotentes.

## Marcha atrás

Una reinstalación no tiene marcha atrás sobre el disco: por eso se exige la copia comprobada. Mientras no haya
borrado el disco antiguo (si cambia de disco), consérvelo intacto hasta comprobar que todo está en el nuevo.
