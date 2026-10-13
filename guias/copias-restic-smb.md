<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# Copias de seguridad con restic en un NAS por SMB 3.1.1 cifrado

Copia diaria de `/home`, `/etc` y unas listas del sistema en un repositorio **restic** (cifrado por restic) dentro de
una carpeta compartida de un NAS, montada por **SMB 3.1.1 con cifrado de transporte** (`seal`). La copia sale de
**instantáneas btrfs/snapper**, así que es consistente aunque esté trabajando. Componente: `estacion-copia`
(sistema/), con sus unidades y avisos.

## Requisitos

- `restic` y `cifs-utils`: `sudo pacman -S --needed restic cifs-utils`.
- Un NAS en la red de casa con SMB 3.1.1 y cifrado SMB disponible, una carpeta compartida para las copias y un
  **usuario dedicado** del NAS, **sin** privilegios de administrador, con acceso solo a esa carpeta y solo por SMB.
- Recomendado: `/` y `/home` en btrfs, con una configuración de snapper llamada `home`.
- Portátil: las copias automáticas solo se hacen **con el cargador** (`ConditionACPower=true`).

## Cómo comprobar si le afecta

```bash
findmnt -no FSTYPE / /home                           # btrfs → copia desde instantáneas
snapper list-configs                                 # ¿existe «home»?
timeout 5 bash -c 'exec 3<>/dev/tcp/nas.local/445' && echo "el NAS responde en 445"
smbclient -L //nas.local -U usuario-copias -m SMB3   # (paquete smbclient) lista recursos
```

## Diseño

| Pieza | Qué hace |
|---|---|
| `/usr/local/bin/estacion-copia` | `copia`, `--ahora`, `mantener`, `hace-falta`, `restic <args>` (monta, ejecuta restic y desmonta). |
| `estacion-copia.timer` | Diario a las 20:30 (`Persistent=true`, `RandomizedDelaySec=30min`): si el equipo estaba apagado, lo hace al encender. |
| `90-estacion-copia-cargador.rules` + `estacion-copia-cargador.service` | Al enchufar el cargador, copia **si hoy aún no hay copia correcta** (`ExecCondition=estacion-copia hace-falta`), tras 2 min de margen para la red. |
| `estacion-copia-mantener.timer` | Domingos: `forget --prune` (7 diarias, 4 semanales, 12 mensuales) y `check`; la primera semana del mes, además `check --read-data-subset=10%`. |
| `estacion-copia-aviso@.service` | `OnFailure=` de las unidades: notificación crítica en la sesión y entrada en el journal. |
| `estacion-copia-vigilar.timer` (usuario) | Cada día a las 11:00: avisa si hace **más de 3 días** que no hay copia correcta. |

Si el NAS no responde, la copia **no da error**: se registra y se reintenta en el siguiente disparo (no tiene sentido
una alerta crítica cada vez que está fuera de casa). La vigilancia de 3 días cubre ese caso.

## Pasos

1. Configuración en `/etc/estacion/estacion.conf` (vea `sistema/estacion.conf.example`):
   ```bash
   COPIA_MODO="smb"
   COPIA_NAS="nas.local"                 # o una IP, p. ej. 192.0.2.10
   COPIA_PUERTO="445"
   COPIA_RECURSO="//nas.local/copias"
   COPIA_PUNTO_MONTAJE="/mnt/estacion-nas"
   COPIA_REPOSITORIO="/mnt/estacion-nas/restic"
   COPIA_CREDENCIALES="/etc/estacion/smb-credenciales"
   COPIA_CLAVE_RESTIC="/etc/estacion/restic-clave"
   COPIA_EXCLUIR="/etc/estacion/excluir.txt"
   ```
2. **Secretos**, root y `0600`, creados por usted y **nunca** publicados ni copiados a dotfiles:
   ```bash
   sudo install -d -m 755 /etc/estacion
   # Contraseña del repositorio (guárdela TAMBIÉN en su gestor de contraseñas: sin ella la copia es ilegible)
   sudo sh -c 'umask 077; head -c 48 /dev/urandom | base64 -w0 > /etc/estacion/restic-clave'
   # Credenciales SMB (teclee la contraseña sin eco)
   # (printf es interno de bash: la contraseña no aparece en la lista de procesos)
   read -rsp "Contraseña SMB: " pw; echo
   printf 'username=%s\npassword=%s\n' usuario-copias "$pw" \
     | sudo install -m 600 -o root -g root /dev/stdin /etc/estacion/smb-credenciales; unset pw
   sudo stat -c '%U:%G %a %n' /etc/estacion/*
   ```
3. Montaje que usa el script (compruébelo una vez a mano):
   ```bash
   sudo install -d -m 700 /mnt/estacion-nas
   sudo mount -t cifs //nas.local/copias /mnt/estacion-nas \
     -o credentials=/etc/estacion/smb-credenciales,vers=3.1.1,seal,uid=0,gid=0,file_mode=0600,dir_mode=0700,noperm
   findmnt -no OPTIONS /mnt/estacion-nas | tr ',' '\n' | grep -E '^(vers|seal)'   # vers=3.1.1 y seal
   sudo umount /mnt/estacion-nas
   ```
   `seal` exige cifrado SMB3 (AES-GCM) de todo el tráfico; si el NAS no lo admite, el montaje falla en vez de ir en
   claro. `error(13)` = usuario o contraseña incorrectos.
4. Exclusiones (`/etc/estacion/excluir.txt`, una ruta o patrón por línea): la contraseña del repositorio y las
   credenciales SMB (no tiene sentido guardarlas dentro de la copia), cachés (`~/.cache`, cachés de Electron y VS
   Code), lo regenerable (`node_modules`, `__pycache__`, `*.pkg.tar.zst`, `src/` y `pkg/` de makepkg, papelera), los
   binarios que se autodescargan (p. ej. `~/.parsec/parsecd-*.so`, vea [parsec.md](parsec.md)) y, si cifra el disco,
   `/etc/cryptsetup-keys.d` (el fichero de clave de `/home` no sale del equipo). Además restic omite los directorios
   con `CACHEDIR.TAG` (`--exclude-caches`).
5. Inicialice el repositorio y active los temporizadores (lo hace `instalar.sh`; a mano):
   ```bash
   sudo estacion-copia restic init
   sudo systemctl enable --now estacion-copia.timer estacion-copia-mantener.timer
   systemctl --user enable --now estacion-copia-vigilar.timer
   ```

### Origen consistente: instantáneas

En cada copia, `estacion-copia`:

1. crea una instantánea de snapper de `/home` (`--cleanup-algorithm number`) y una instantánea btrfs **de solo
   lectura** de `/` (fuera de snapper, para no añadir entradas al menú de Limine);
2. en un **espacio de montaje privado** (`unshare -m --propagation private`) monta la de `/home` sobre `/home` y la
   `/etc` de la raíz sobre `/etc`, de modo que restic ve rutas normales y el resto del sistema no ve nada;
3. ejecuta `restic backup /home /etc /var/lib/estacion-copia/sistema --exclude-file … --exclude-caches --compression auto`;
4. borra las dos instantáneas al salir (también si falla: `trap EXIT`) y desmonta el NAS.

`/var/lib/estacion-copia/sistema` contiene listas regeneradas en cada copia: `pacman -Qqe`, `pacman -Qqm`,
`pacman -Qqen`, `pacman -Q`, `limine.conf`, `lsblk -f`, subvolúmenes y configuraciones de snapper. Sirven para
reconstruir el equipo ([reinstalar.md](reinstalar.md)).

### snapper y UNIQUE_NUMBERS

Con snapper reciente (`UNIQUE_NUMBERS`, activo por defecto), al borrar la instantánea de **número más alto** snapper
conserva **a propósito** su directorio vacío (`/home/.snapshots/N/`) para no reutilizar el número. Tras cada copia
puede quedar ese directorio vacío: **es normal; no lo borre**. Solo es un problema si contiene algo (borrado
incompleto); el script lo avisa en el journal.

```bash
sudo ls -A /home/.snapshots/<N>      # vacío = normal
```

### Aviso al pulsar

Las notificaciones de fallo llevan el hint `x-caelestia-log` con valor `journal:<unidad>`: con el parche 10 de
Caelestia (caelestia/), pulsarlas abre el registro de la unidad.

## Verificación

```bash
systemctl list-timers 'estacion-copia*'; systemctl --user list-timers estacion-copia-vigilar.timer
sudo estacion-copia --ahora                    # copia manual (exige el cargador), sin límite diario
journalctl -u estacion-copia -n 30
sudo estacion-copia restic snapshots
sudo estacion-copia restic check
udevadm test --action=change /sys/class/power_supply/AC* 2>&1 | grep estacion   # la regla casa (ACAD, ADP1…)
```

**Restauración de prueba** (hágala al instalar y de vez en cuando; nunca encima de los originales):

```bash
sudo estacion-copia restic restore latest --target /var/tmp/prueba-restaurar --include /etc/fstab \
  --include /home/usuario/.config
diff -r /var/tmp/prueba-restaurar/home/usuario/.config /home/usuario/.config | head
sudo estacion-copia restic check --read-data   # lectura completa: tarda; hágalo con el cargador
sudo rm -r /var/tmp/prueba-restaurar
```

### Si llega un aviso

- **«La copia de seguridad ha fallado»**: `journalctl -u estacion-copia -n 50`. Causas típicas: contraseña del
  usuario del NAS cambiada (`error(13)`: rehaga `smb-credenciales`), repositorio bloqueado tras un corte
  (`sudo estacion-copia restic unlock`). Reintente con `sudo estacion-copia --ahora`.
- **«Hace N días sin copia»**: el equipo no estuvo enchufado con el NAS encendido. Enchúfelo en casa: la copia
  arranca a los 2 minutos.
- **Fallo del mantenimiento**: si `check` encuentra errores, **no borre nada** y ejecute
  `sudo estacion-copia restic check --read-data` para ver el alcance.

## Recomendaciones del NAS

- Cortafuegos del NAS: SMB solo desde la red de casa (p. ej. `192.168.0.0/24`), denegar el resto.
- Verificación en dos pasos para el administrador; el usuario de copias sin acceso remoto.
- SMB1 y NetBIOS desactivados si el NAS lo permite.
- Algunos NAS solo admiten claves SSH para administradores: por eso aquí se usa SMB y no SFTP.

## Marcha atrás

```bash
sudo systemctl disable --now estacion-copia.timer estacion-copia-mantener.timer
systemctl --user disable --now estacion-copia-vigilar.timer
sudo rm /etc/udev/rules.d/90-estacion-copia-cargador.rules && sudo udevadm control --reload
```

Las copias del NAS no se tocan. Para borrar también los secretos: `sudo rm /etc/estacion/restic-clave
/etc/estacion/smb-credenciales` (asegúrese antes de tener la contraseña del repositorio en su gestor si quiere
seguir leyendo las copias).
