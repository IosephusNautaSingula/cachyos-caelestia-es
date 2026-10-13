<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# Restaurar ficheros o el sistema (restic, snapper y Limine)

Tres niveles, de más rápido a más completo:

1. **Instantáneas locales de snapper** (horas o días atrás, en el propio disco).
2. **Arrancar una instantánea desde Limine** (el sistema no arranca o falla tras una actualización).
3. **Copia restic del NAS** (ficheros borrados hace tiempo, disco dañado o equipo nuevo).

## Requisitos

- Para snapper/Limine: btrfs + snapper + `limine-snapper-sync` ([snapper-limine.md](snapper-limine.md)).
- Para restic: `estacion-copia` configurado ([copias-restic-smb.md](copias-restic-smb.md)) o, en un equipo nuevo,
  `restic` y `cifs-utils`, el NAS encendido en la red y la **contraseña del repositorio** y las **credenciales SMB**
  (en su gestor de contraseñas). Sin la contraseña del repositorio la copia es ilegible: está cifrada.

## Cómo comprobar si le afecta

```bash
sudo snapper list-configs                 # root y home
sudo snapper -c home list | tail -5
sudo estacion-copia restic snapshots      # copias en el NAS
grep -c '^\s*///' /boot/limine.conf       # entradas de instantáneas en el menú de Limine
```

## A. Un fichero o una carpeta de hace poco: snapper

```bash
sudo snapper -c home list
# Compare y copie desde la instantánea (solo lectura); <N> es el número de la lista
sudo ls /home/.snapshots/<N>/snapshot/usuario/Documentos/
sudo snapper -c home diff <N>..0 /home/usuario/Documentos/carta.odt     # qué cambió desde entonces
cp -a /home/.snapshots/<N>/snapshot/usuario/Documentos/carta.odt ~/carta-restaurada.odt
```

Para ficheros del sistema, lo mismo con `-c root` y `/.snapshots/<N>/snapshot/…`. `snapper undochange <N>..0
<fichero>` deshace cambios en sitio; úselo solo si sabe exactamente qué deshace.

## B. El sistema no arranca o falla tras actualizar: Limine → Snapshots

1. Reinicie. En Limine baje a **Snapshots** y elija la instantánea **anterior** a la actualización (snap-pac hace
   una *pre* y una *post* por cada transacción de pacman) y, dentro, su kernel.
2. Arranca esa instantánea **en solo lectura con una capa overlay** (los cambios se pierden al reiniciar). Compruebe
   que todo va bien.
3. Si la normal está rota de verdad, hágala permanente con **Restore now** (en el menú) o, ya dentro:
   ```bash
   sudo limine-snapper-restore
   ```
4. Alternativas más suaves: la entrada del **kernel LTS** del menú (si el problema es el kernel nuevo) o
   `sudo downgrade <paquete>` para un paquete concreto (responda **no** a fijarlo en IgnorePkg salvo que lo quiera).

Al arrancar desde una instantánea es normal que `systemd-remount-fs.service` salga *failed* («overlay: No changes
allowed in reconfigure»): systemd intenta volver a montar `/` con las opciones de `fstab` y el overlay lo rechaza.
Es inofensivo.

## C. Desde la copia restic, en el mismo equipo

`estacion-copia restic …` monta el NAS, ejecuta restic con la configuración guardada y desmonta.

```bash
sudo estacion-copia restic snapshots
sudo estacion-copia restic find 'carta.odt'                  # busca en todas las copias
sudo estacion-copia restic ls latest /home/usuario/Documentos
# Restaure SIEMPRE a una carpeta aparte, nunca encima
sudo estacion-copia restic restore latest --target /var/tmp/restaurado \
  --include /home/usuario/Documentos/carta.odt --include /home/usuario/.config/hypr
sudo chown -R usuario: /var/tmp/restaurado
# Compare y copie lo que necesite; después:
sudo rm -r /var/tmp/restaurado
```

Use el ID de una copia concreta (columna izquierda de `snapshots`) en lugar de `latest` para ir más atrás.
Las copias guardan 7 diarias, 4 semanales y 12 mensuales.

## D. Equipo o disco nuevo: el sistema entero

El camino recomendado es [reinstalar.md](reinstalar.md) con `instalar.sh`. A mano:

```bash
sudo pacman -Syu --needed restic cifs-utils rsync
sudo install -d -m 700 /mnt/estacion-nas
sudo mount -t cifs //nas.local/copias /mnt/estacion-nas \
  -o username=usuario-copias,vers=3.1.1,seal,uid=0,gid=0,file_mode=0600,dir_mode=0700   # pide la contraseña SMB
sudo restic -r /mnt/estacion-nas/restic snapshots                     # pide la contraseña del repositorio
sudo restic -r /mnt/estacion-nas/restic restore latest --target /var/tmp/r
```

Quedan `/var/tmp/r/home`, `/var/tmp/r/etc` y `/var/tmp/r/var/lib/estacion-copia/sistema`.

1. **Carpeta personal** (con la sesión gráfica cerrada: consola con Ctrl+Alt+F3):
   ```bash
   sudo rsync -aHAX /var/tmp/r/home/usuario/ /home/usuario/
   sudo chown -R usuario: /home/usuario
   ```
2. **Programas** desde las listas:
   ```bash
   S=/var/tmp/r/var/lib/estacion-copia/sistema
   sudo pacman -S --needed $(cat "$S/paquetes-explicitos-repositorios.txt")
   cat "$S/paquetes-ajenos-aur-locales.txt"     # instálelos con paru (revisando cada PKGBUILD) o makepkg
   ```
   Si pacman se queja de un paquete que ya no existe, quítelo de la lista y repita.
3. **/etc**: **no** lo copie entero encima (lleva UUID de discos, `machine-id`, `fstab`, `crypttab`… de la
   instalación anterior). Compare y copie solo lo personalizado: `pacman.conf` (opciones, no repositorios),
   `paru.conf`, `snapper/configs/`, `default/limine`, `limine-snapper-sync.conf`, `sddm.conf.d/`,
   `pacman.d/hooks/`, `estacion/` (salvo los secretos, que no están en la copia), reglas `udev` y unidades propias.
4. Vuelva a crear los secretos de la copia (`/etc/estacion/restic-clave` con **la misma** contraseña del
   repositorio y `smb-credenciales`), active las copias y limpie:
   ```bash
   sudo umount /mnt/estacion-nas && sudo rm -r /var/tmp/r
   ```

En `/etc` restaurado faltan a propósito los dos ficheros de secretos de la copia (están excluidos). No es un error.

## E. Disco cifrado

Abrir desde un live, rescatar el arranque, restaurar una cabecera LUKS o volver a inscribir el TPM tras actualizar la
BIOS: vea [cifrado-luks2-tpm2-limine.md](cifrado-luks2-tpm2-limine.md) («Rescate desde el live» y «Secure Boot,
BIOS y el PCR 7»).

## Verificación

- Fichero restaurado: `sha256sum` del restaurado frente al de la instantánea o la copia.
- Sistema restaurado: `systemctl --failed` vacío, `sudo estacion-copia restic snapshots` funciona y la siguiente
  copia diaria termina bien (`journalctl -u estacion-copia -n 20`).

## Marcha atrás

Restaurar a una carpeta aparte no cambia nada: basta con borrarla. Tras `limine-snapper-restore`, snapper deja una
instantánea del estado anterior: puede volver a ella de la misma forma (Limine → Snapshots).
