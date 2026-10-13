<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# Instantáneas arrancables con snapper y Limine

Con btrfs + snapper + `limine-snapper-sync`, cada transacción de pacman deja una instantánea *pre* y *post* de `/`
que aparece en el menú de Limine (**Snapshots**) y se puede **arrancar**. `/home` tiene su propia línea temporal.

## Requisitos

- `/` en btrfs (subvolumen `@`, instantáneas en `/.snapshots`) y Limine.
- `snapper`, `snap-pac`, `limine-snapper-sync`, `limine-mkinitcpio-hook` (en CachyOS vienen con
  `cachyos-snapper-support`) y, recomendado, un kernel de respaldo (p. ej. `linux-cachyos-lts`) y `downgrade`.

## Cómo comprobar si le afecta

```bash
sudo snapper list-configs
systemctl is-active limine-snapper-sync.service        # vigilante que regenera el menú
cat /etc/mkinitcpio.conf.d/10-limine-snapper-sync.conf  # HOOKS+=(sd-btrfs-overlayfs)
grep -cE '^\s*///' /boot/limine.conf                    # entradas de instantáneas
```

## Pasos

1. **Formato del menú** (`/etc/limine-snapper-sync.conf`): `SNAPSHOT_FORMAT_CHOICE=7` muestra «ID│descripción»,
   más útil que la fecha. Haga `.bak` antes y regenere:
   ```bash
   sudo cp -a /etc/limine-snapper-sync.conf /etc/limine-snapper-sync.conf.bak.$(date +%F)-formato
   sudo sed -i 's/^SNAPSHOT_FORMAT_CHOICE=.*/SNAPSHOT_FORMAT_CHOICE=7/' /etc/limine-snapper-sync.conf
   sudo limine-snapper-sync
   ```
2. El hook `sd-btrfs-overlayfs` (fragmento `10-limine-snapper-sync.conf`) monta la instantánea en solo lectura con
   una capa overlay en RAM: puede arrancarla y usarla sin modificarla. **No lo quite.**
3. **Configuración `home`** con su propia línea temporal y sin pre/post en cada pacman:
   ```bash
   sudo snapper -c home create-config /home
   sudo snapper -c home set-config TIMELINE_CREATE=yes TIMELINE_CLEANUP=yes TIMELINE_LIMIT_HOURLY=5 \
     TIMELINE_LIMIT_DAILY=7 TIMELINE_LIMIT_WEEKLY=4 TIMELINE_LIMIT_MONTHLY=3 NUMBER_LIMIT=5 \
     NUMBER_LIMIT_IMPORTANT=5 SPACE_LIMIT=0.2 FREE_LIMIT=0.2
   printf '\n[home]\nsnapshot = no\n' | sudo tee -a /etc/snap-pac.ini     # con .bak antes
   sudo systemctl enable --now snapper-timeline.timer snapper-cleanup.timer
   ```
   Deje `TIMELINE_CREATE=no` en `root`: allí bastan las de pacman.
4. **Instantáneas manuales importantes** (antes de un cambio delicado), sin algoritmo de limpieza para que no se
   borren solas:
   ```bash
   sudo snapper -c root create -d "Antes de <cambio>" --userdata important=yes
   sudo snapper -c home create -d "Antes de <cambio>" --userdata important=yes
   ```
5. **UNIQUE_NUMBERS**: snapper reciente no reutiliza números. Al borrar la instantánea de número más alto deja su
   directorio **vacío** (`/.snapshots/N` o `/home/.snapshots/N`) a propósito. Es normal: no lo borre ni lo cuente como
   huérfano. Solo es anómalo un directorio de una instantánea borrada que **conserve contenido**.

## Verificación

- Reinicie, elija **Snapshots → <ID>│<descripción>** y arranque: `findmnt /` debe mostrar `overlay` y
  `cat /proc/cmdline` el `subvol=/@/.snapshots/<ID>/snapshot`. Reinicie para volver a la normal.
- Arranque también la entrada del **kernel LTS** una vez.
- Al arrancar una instantánea, `systemd-remount-fs.service` sale *failed* («overlay: No changes allowed in
  reconfigure»): es inofensivo.
- Si usa disco cifrado, las entradas de instantáneas deben llevar `rd.luks.name` igual que las normales
  ([cifrado-luks2-tpm2-limine.md](cifrado-luks2-tpm2-limine.md)).

## Volver atrás de verdad

- Un paquete: `sudo downgrade <paquete>`.
- Todo el sistema: arranque la instantánea, compruebe y, si la normal está rota, **Restore now** en el menú o
  `sudo limine-snapper-restore`. Detalle en [restaurar.md](restaurar.md).

## Marcha atrás

```bash
sudo cp -a /etc/limine-snapper-sync.conf.bak.<fecha>-formato /etc/limine-snapper-sync.conf && sudo limine-snapper-sync
sudo snapper -c home delete-config         # borra la configuración home y SUS instantáneas
```
