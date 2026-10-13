<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# Cifrar en el sitio / y /home (btrfs) con LUKS2, TPM2 + PIN y Limine

> ## ⚠️ AVISO DE RIESGO: LEA ESTO ANTES DE NADA
>
> - Cifrar **en el sitio** reescribe cada bloque de las particiones. Un error de configuración, un fallo del disco,
>   un corte de corriente mal gestionado o una frase que luego no sepa teclear pueden suponer **la pérdida de TODOS
>   sus datos**.
> - Es **obligatorio** tener antes una **copia completa, reciente y comprobada** (por ejemplo con
>   [copias-restic-smb.md](copias-restic-smb.md): copia nueva + `restic check` + una restauración de prueba) y saber
>   reinstalar desde ella ([reinstalar.md](reinstalar.md)). Si no la tiene, **no siga**.
> - Haga **primero el modo de prueba**: el ensayo en una imagen loop (`cifrado-prueba-loop.sh`) y
>   `cifrado-live.sh --prueba`, que no escriben en su disco. El modo real de los scripts que escriben en el disco solo
>   se activa con `--ejecutar --acepto-perdida-de-datos`.
> - Portátil **siempre con el cargador**; no cierre la tapa ni apague durante el cifrado.
> - Esta guía y los scripts se ofrecen **sin ninguna garantía** (GPL-3.0-or-later). Usted es responsable de sus datos.

## Qué se consigue

- La raíz (`/`) y `/home`, cada una en su partición btrfs, pasan a ser contenedores **LUKS2** (aes-xts-plain64 de 512
  bits, argon2id) **sin reinstalar**: dentro sigue el mismo btrfs, con sus subvolúmenes e instantáneas de snapper.
- La raíz se abre al arrancar con **TPM2 + PIN** (atado al PCR 7), con una **frase** de reserva y una **clave de
  recuperación**.
- `/home` se abre sola con un **fichero de clave** guardado dentro de la raíz cifrada (además de la frase y la misma
  clave de recuperación).
- El initramfs usa el hook **sd-encrypt** y Limine pasa `rd.luks.name=` al kernel, también en las entradas de
  instantáneas de `limine-snapper-sync`.
- Copias de las **cabeceras LUKS** fuera del disco, con una regla clara para sustituirlas al rotar claves.
- Procedimientos de **reanudación tras un corte** y de **rescate desde un live**.

La ESP (FAT32, con Limine, kernels e initramfs) **no** se cifra. Sin Secure Boot, alguien con acceso físico podría
manipularla; el TPM atado al PCR 7 no lo impide del todo. Valore si eso entra en su modelo de amenazas.

## Requisitos

- CachyOS o Arch con **Limine** + `limine-mkinitcpio-hook` (orden `limine-mkinitcpio`) y, si las usa,
  `limine-snapper-sync`.
- Initramfs **basado en systemd** (HOOKS con `systemd` y `sd-vconsole`). Con el esquema clásico (`udev`, `encrypt`)
  esta guía no vale tal cual.
- `/` y `/home` en **particiones separadas**, ambas **btrfs** sin cifrar, en el mismo disco (adáptelo si no).
- `cryptsetup` 2.8 o posterior (también en el live), `systemd-cryptenroll`, `tpm2-tss` y un **TPM 2.0** visible
  (`/dev/tpmrm0`).
- Un **USB** con un live de CachyOS (o Arch) y sitio para los scripts y sus registros (p. ej. un USB multiarranque con
  una partición de datos exFAT).
- Copia completa y comprobada (vea el aviso). Cargador. Entre 1 y 2 horas según el tamaño y la velocidad del disco.
- Un gestor de contraseñas accesible desde **otro dispositivo** (el móvil) para la frase, el PIN y la clave de
  recuperación.

## Cómo comprobar si le afecta

```bash
findmnt -no SOURCE,FSTYPE / /home          # dos particiones distintas, ambas btrfs (p. ej. /dev/nvme0n1p2[/@])
lsblk -o NAME,FSTYPE,SIZE,MOUNTPOINTS       # que no haya ya crypto_LUKS
grep -E '^HOOKS=' /etc/mkinitcpio.conf      # debe contener «systemd» y «sd-vconsole»
ls /etc/mkinitcpio.conf.d/ 2>/dev/null
command -v limine-mkinitcpio && cat /etc/default/limine | grep -E '^KERNEL_CMDLINE'
cryptsetup --version                        # 2.8 o posterior
systemd-cryptenroll --tpm2-device=list      # debe aparecer /dev/tpmrm0
bootctl status 2>/dev/null | grep -i 'secure boot'
```

Si `/home` está dentro de la misma partición que `/` (un único btrfs), cifre esa única partición y omita lo que esta
guía dice del fichero de clave de `/home`.

## Los scripts (sistema/cifrado/)

Todos leen `cifrado.conf` (copie `cifrado.conf.example` y rellénelo; los scripts se niegan a funcionar mientras
sigan los UUID de ejemplo y comprueban disco, número de serie, PARTUUID y tamaños antes de tocar nada). Sin
argumentos muestran su ayuda. Nunca guardan la frase, el PIN ni claves en registros.

| Script | Dónde | Qué hace |
|---|---|---|
| `cifrado-inventario.sh` | sistema instalado | Lee el equipo y propone un `cifrado.conf` (`--conf`). Solo lectura. |
| `cifrado-prueba-loop.sh` | cualquier equipo | Ensayo completo en una imagen loop, con cortes simulados y medida de velocidad. No toca su disco. |
| `cifrado-preparar.sh` | sistema instalado | Comprobaciones, fichero de clave de `/home`, `crypttab.initramfs` provisional, sd-encrypt, copia nueva, instantáneas y copia de los scripts a la ESP y al NAS. **No cifra.** |
| `cifrado-live.sh` | live | `--prueba` (no escribe) y `--ejecutar --acepto-perdida-de-datos` (cifra y configura el arranque). |
| `cifrado-reanudar.sh` | live | Reanuda tras un corte o un error. |
| `cifrado-rescate.sh` | live | Abre con la frase o la clave de recuperación y rehace el arranque, o monta para mirar. |
| `cifrado-primer-arranque.sh` | sistema cifrado | Inscribe TPM2 + PIN, crea la clave de recuperación, copia las cabeceras; `--comprobar` verifica el arranque. |
| `cifrado-cambiar-pin.sh` | sistema cifrado | Cambia el PIN dejando un único hueco TPM2. |
| `cifrado-nueva-recuperacion.sh` | sistema cifrado | Sustituye la clave de recuperación y las copias viejas de las cabeceras. |
| `cifrado-copiar.sh` | sistema | Copia los scripts, cifrado.conf y el README al USB, la ESP y el NAS, con sus sumas sha256. |

A continuación se explica **qué hace cada paso y por qué**, con las órdenes equivalentes, para que pueda auditarlo
o hacerlo a mano. Sustituya `/dev/nvme0n1p2` (raíz) y `/dev/nvme0n1p3` (`/home`) por las suyas.

## 1. Antes de empezar

1. Copia completa nueva y comprobada:
   ```bash
   sudo estacion-copia --ahora
   sudo estacion-copia restic check
   ```
2. Cree en su gestor de contraseñas la **frase**: 6 palabras corrientes en **minúsculas**, solo letras de la *a* a la
   *z*, separadas por **un espacio**. En la pantalla de arranque el teclado puede cargarse en inglés: esas teclas
   están en el mismo sitio en la distribución española y en la estadounidense, así que la frase se teclea igual.
   Compruebe que la ve en el móvil.
3. Genere de antemano los **UUID de los futuros contenedores LUKS** (así se puede escribir `crypttab` antes de
   cifrar):
   ```bash
   cat /proc/sys/kernel/random/uuid      # uno para la raíz, otro para /home → cifrado.conf
   ```
4. Ensaye en una imagen loop (no toca el disco):
   ```bash
   sudo bash cifrado-prueba-loop.sh --ejecutar --acepto-perdida-de-datos   # solo escribe en su imagen loop
   ```

## 2. Preparar el sistema instalado (todavía sin cifrar)

`cifrado-preparar.sh` hace, en resumen:

```bash
# Fichero de clave de /home (vive dentro de la raíz, que quedará cifrada). Nunca sale del equipo.
sudo install -d -m 700 /etc/cryptsetup-keys.d
sudo sh -c 'umask 077; head -c 64 /dev/urandom > /etc/cryptsetup-keys.d/crypthome.key'
sudo chmod 400 /etc/cryptsetup-keys.d/crypthome.key
# Y excluirlo de la copia: añada /etc/cryptsetup-keys.d a /etc/estacion/excluir.txt

# crypttab.initramfs PROVISIONAL: con nofail y 15 s de espera, este arranque (sin cifrar) no cambia y las
# instantáneas que se hagan desde ahora arrancarán también ya cifradas.
echo "cryptroot UUID=<UUID-LUKS-RAIZ> none luks,discard,nofail,x-systemd.device-timeout=15s" \
  | sudo tee /etc/crypttab.initramfs
sudo chmod 600 /etc/crypttab.initramfs

# sd-encrypt en HOOKS, antes de filesystems (con .bak):
sudo cp -a /etc/mkinitcpio.conf /etc/mkinitcpio.conf.bak.$(date +%F)-cifrado
sudo sed -i -E '/^HOOKS=/ s/\bfilesystems\b/sd-encrypt filesystems/' /etc/mkinitcpio.conf
sudo limine-mkinitcpio
```

Además hace una copia nueva, instantáneas `important=yes` de root y home («Antes del cifrado») y copia los scripts a
la ESP (plan B por si el live no puede montar el USB) y al NAS.

**Reinicio de prueba recomendado:** puede tardar hasta 15 s más (espera al contenedor que aún no existe). Si no
arranca, elija en Limine *Snapshots* → la instantánea anterior y no siga.

## 3. Cifrar desde el live

Arranque el USB, ponga el teclado en español y abra una terminal. **No** abra el instalador ni monte las particiones
internas en el gestor de archivos.

```bash
sudo mkdir -p /mnt/usb && sudo mount /dev/disk/by-label/<ETIQUETA-USB> /mnt/usb
cd /mnt/usb/estacion-cifrado
sha256sum -c SHA256SUMS                 # todo OK; compare además la suma de SHA256SUMS con la de su gestor
sudo bash cifrado-live.sh --prueba      # no escribe nada: debe terminar en «TODO CORRECTO»
sudo bash cifrado-live.sh --ejecutar --acepto-perdida-de-datos
```

Por cada partición (primero la raíz, que es más pequeña y reconstruible, y además guarda el fichero de clave de
`/home`), el script hace:

```bash
btrfs check --readonly /dev/nvme0n1p2                       # si hay errores: PARE
mount /dev/nvme0n1p2 /mnt/bruto
btrfs filesystem resize -"$REDUCIR_BTRFS" /mnt/bruto          # REDUCIR_BTRFS de cifrado.conf: sitio para LUKS2
umount /mnt/bruto
cd /mnt/usb/estacion-cifrado/trabajo                         # cryptsetup deja aquí LUKS2-temp-<UUID>.new:
                                                             # DEBE estar fuera del disco que se cifra (USB o ESP)
cryptsetup --batch-mode reencrypt --encrypt --type luks2 --cipher aes-xts-plain64 --key-size 512 \
  --hash sha256 --pbkdf argon2id --reduce-device-size 32M --uuid <UUID-LUKS-RAIZ> \
  --key-file /run/frase --progress-frequency 20 /dev/nvme0n1p2
cryptsetup open --allow-discards --persistent --key-file /run/frase /dev/nvme0n1p2 cryptroot   # TRIM en la cabecera
mount /dev/mapper/cryptroot /mnt/bruto
btrfs filesystem resize max /mnt/bruto
btrfs scrub start -B /mnt/bruto                              # sin errores
```

La frase se pide dos veces y solo vive en RAM (`/run`). Notas:

- `--reduce-device-size 32M` desplaza los datos (*datashift*) para hacer sitio a la cabecera: por eso el btrfs se
  reduce antes **más** de 32 MiB y se vuelve a crecer al final.
- Use siempre `--batch-mode`, la clave por `--key-file` y la entrada estándar desde `/dev/null` en los pasos
  automáticos: así ninguna orden se queda esperando una respuesta que no llega.
- El UUID del **btrfs** no cambia: `fstab` sigue igual.

Después, en chroot sobre el sistema abierto, configura el arranque:

```bash
mount -o subvol=@ /dev/mapper/cryptroot /mnt/sistema   # y el resto de subvolúmenes, la ESP en /mnt/sistema/boot
cryptsetup luksAddKey --key-file /run/frase /dev/nvme0n1p3 /mnt/sistema/etc/cryptsetup-keys.d/crypthome.key

# /etc/crypttab (sistema): /home con su fichero de clave
echo "crypthome UUID=<UUID-LUKS-HOME> /etc/cryptsetup-keys.d/crypthome.key luks,discard" >> /mnt/sistema/etc/crypttab
# /etc/crypttab.initramfs DEFINITIVO (sin nofail): la raíz se abre en el initramfs
echo "cryptroot UUID=<UUID-LUKS-RAIZ> none luks,discard" > /mnt/sistema/etc/crypttab.initramfs
chmod 600 /mnt/sistema/etc/crypttab /mnt/sistema/etc/crypttab.initramfs

# /etc/default/limine: rd.luks.name delante de root= en KERNEL_CMDLINE
sed -i 's|root=UUID=<UUID-BTRFS-RAIZ>|rd.luks.name=<UUID-LUKS-RAIZ>=cryptroot root=UUID=<UUID-BTRFS-RAIZ>|' \
  /mnt/sistema/etc/default/limine

arch-chroot /mnt/sistema limine-mkinitcpio        # initramfs con sd-encrypt + entradas de Limine
arch-chroot /mnt/sistema limine-snapper-sync      # entradas de instantáneas (si lo usa)
```

Compruebe que cada initramfs lleva `systemd-cryptsetup` y `etc/crypttab`, y que las entradas principales de
`limine.conf` (normal y LTS) llevan `rd.luks.name`:

```bash
lsinitcpio /boot/<machine-id>/linux-cachyos/initramfs-linux-cachyos | grep -E 'systemd-cryptsetup|etc/crypttab'
grep -c 'cmdline:.*rd.luks.name' /boot/limine.conf
```

## 4. Primer arranque cifrado

Quite el USB y arranque: Limine → pide la **frase** de `cryptroot`; `/home` se abre sola con el fichero de clave.
Si no llega a SDDM, vaya a «Rescate desde el live».

## 5. TPM2 + PIN, clave de recuperación y cabeceras

`cifrado-primer-arranque.sh` (después, `--comprobar` tras reiniciar con el PIN) hace:

```bash
# TPM2 + PIN atado al PCR 7 (estado de Secure Boot; no cambia con cada actualización del kernel)
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 --tpm2-with-pin=yes /dev/nvme0n1p2
# Referencia para detectar más tarde un cambio del PCR 7 (no es secreta)
sudo install -d /var/lib/estacion-tpm
systemd-analyze pcrs 7 | awk 'NR==2{print $3}' | sudo tee /var/lib/estacion-tpm/pcr >/dev/null

# Clave de recuperación (la genera systemd; se muestra UNA vez: cópiela en su gestor, con los guiones)
sudo systemd-cryptenroll --recovery-key /dev/nvme0n1p2
# La MISMA clave en /home (autorizando con el fichero de clave; teclee la clave de recuperación como clave nueva)
sudo cryptsetup luksAddKey --key-file /etc/cryptsetup-keys.d/crypthome.key /dev/nvme0n1p3

sudo systemd-cryptenroll /dev/nvme0n1p2       # huecos: password, recovery, tpm2
sudo cryptsetup luksDump /dev/nvme0n1p3 | grep -A1 'Keyslots'
```

- **PIN**: 6 caracteres o más, solo letras sin tilde ni ñ y números (por el teclado de la pantalla de arranque).
  Evite 123456 y similares.
- El desbloqueo con TPM2 + PIN aplica argon2id al PIN: en el initrd puede usar más de 2 GiB de memoria durante unos
  segundos. Es normal.
- El TPM tiene protección contra ataques de diccionario: tras muchos PIN fallidos solo admite un intento cada cierto
  tiempo (depende del TPM). La **frase** sigue sirviendo siempre: si el PIN falla, el arranque acaba pidiéndola.

### Cabeceras LUKS

Una cabecera dañada hace ilegible la partición entera. Guarde copias **fuera del disco**:

```bash
sudo install -d -m 700 /var/lib/estacion-copia/sistema/luks
sudo cryptsetup luksHeaderBackup /dev/nvme0n1p2 --header-backup-file /var/lib/estacion-copia/sistema/luks/raiz-cabecera.img
sudo cryptsetup luksHeaderBackup /dev/nvme0n1p3 --header-backup-file /var/lib/estacion-copia/sistema/luks/home-cabecera.img
sudo chmod 600 /var/lib/estacion-copia/sistema/luks/*.img
cd /var/lib/estacion-copia/sistema/luks && sudo sh -c 'sha256sum *.img > SHA256SUMS'
```

Ese directorio entra en la copia diaria (cifrada por restic); copie también los `.img` y `SHA256SUMS` al NAS.

> **Regla de las cabeceras:** una copia de cabecera sigue aceptando **las claves que tenía cuando se hizo**. Si
> cambia la **frase** o la **clave de recuperación** (por ejemplo porque quedó expuesta), **sustituya todas las
> copias viejas**: las del equipo, las del NAS y las que estén dentro de instantáneas restic anteriores
> (`restic rewrite --exclude /var/lib/estacion-copia/sistema/luks …`, `restic prune --max-unused 0` y `restic check`).
> `cifrado-nueva-recuperacion.sh` hace las dos primeras y ofrece la de restic. El PIN del TPM no afecta a las
> cabeceras (solo vale con ese TPM concreto).

## Verificación

```bash
sudo bash cifrado-primer-arranque.sh --comprobar     # «COMPROBADO: arranque cifrado correcto»
findmnt -no SOURCE / /home                           # /dev/mapper/cryptroot y /dev/mapper/crypthome
sudo dmsetup table cryptroot | grep -o allow_discards
sudo systemd-cryptenroll /dev/nvme0n1p2              # recovery y tpm2 presentes
journalctl -b | grep -E 'Finished Cryptography Setup|systemd-cryptsetup@'
sudo limine-snapper-sync && grep -c 'cmdline:.*rd.luks.name' /boot/limine.conf
```

Pruebe también a arrancar una entrada de *Snapshots* en Limine: debe pedir el PIN y arrancar.

## Secure Boot, BIOS y el PCR 7

El PCR 7 mide la política de Secure Boot (claves, dbx, estado activado o no). **Actualizar la BIOS, actualizar el
dbx con fwupd o tocar Secure Boot en la configuración del firmware cambia el PCR 7**: el TPM deja de entregar la
clave y el arranque pide la **frase**. Es lo esperado. Ya dentro, vuelva a inscribir el TPM:

```bash
sudo systemd-cryptenroll --wipe-slot=tpm2 --tpm2-device=auto --tpm2-pcrs=7 --tpm2-with-pin=yes /dev/nvme0n1p2
systemd-analyze pcrs 7 | awk 'NR==2{print $3}' | sudo tee /var/lib/estacion-tpm/pcr >/dev/null
```

(o `cifrado-cambiar-pin.sh`, que deja un único hueco TPM2). Para detectarlo antes de reiniciar, compare
`systemd-analyze pcrs 7` con `/var/lib/estacion-tpm/pcr`.

## Reanudar tras un corte

Si se va la corriente o se apaga **durante** `reencrypt`, no está todo perdido: LUKS2 registra el avance en la
cabecera (y en el fichero `LUKS2-temp-*.new` del directorio de trabajo, por eso tiene que estar en el USB).

```bash
sudo bash cifrado-reanudar.sh --ejecutar --acepto-perdida-de-datos
```

Según el estado de cada partición: **a medias** → `cryptsetup repair` y `cryptsetup reencrypt --resume-only`
(continúa donde iba); **en claro** → empieza esa partición; **cifrada** → solo la abre y la comprueba.
Equivalente manual:

```bash
cd /mnt/usb/estacion-cifrado/trabajo
sudo cryptsetup --batch-mode repair --key-file /run/frase /dev/nvme0n1p2
sudo cryptsetup --batch-mode reencrypt --resume-only --key-file /run/frase --progress-frequency 20 /dev/nvme0n1p2
```

Si el mismo error se repite dos veces, pare y restaure desde la copia.

## Rescate desde el live

Si después de cifrar no arranca (la frase no se acepta, consola de emergencia, error de Limine):

```bash
sudo bash cifrado-rescate.sh --ejecutar --acepto-perdida-de-datos   # 1) rehacer el arranque · 2) montar para mirar
```

A mano:

```bash
sudo cryptsetup open /dev/nvme0n1p2 cryptroot      # frase o clave de recuperación
sudo cryptsetup open /dev/nvme0n1p3 crypthome
sudo mount -o subvol=@ /dev/mapper/cryptroot /mnt
sudo mount /dev/mapper/crypthome /mnt/home
sudo mount /dev/nvme0n1p1 /mnt/boot                 # la ESP
sudo arch-chroot /mnt limine-mkinitcpio
```

**Cabecera dañada** («no es un dispositivo LUKS válido» en una partición que lo era): restaure la copia más reciente
tras comprobar su suma. Una cabecera antigua abre con la frase y la clave de recuperación **de su fecha**.

```bash
sha256sum -c SHA256SUMS
sudo cryptsetup luksHeaderRestore /dev/nvme0n1p2 --header-backup-file raiz-cabecera.img
```

## Marcha atrás

- **Antes de cifrar** (tras `cifrado-preparar.sh`): restaure los `.bak` de `mkinitcpio.conf`, borre
  `/etc/crypttab.initramfs` y el fichero de clave, y ejecute `sudo limine-mkinitcpio`; o arranque la instantánea
  «Antes del cifrado».
- **Ya cifrado:** `cryptsetup reencrypt --decrypt` existe, pero para un contenedor creado con `--reduce-device-size`
  requiere de nuevo desplazar datos y es tan delicado como cifrar. La marcha atrás recomendada es **reinstalar sin
  cifrado y restaurar la copia** ([reinstalar.md](reinstalar.md)).
- **Quitar solo el TPM2** (volver a la frase): `sudo systemd-cryptenroll --wipe-slot=tpm2 /dev/nvme0n1p2`.
