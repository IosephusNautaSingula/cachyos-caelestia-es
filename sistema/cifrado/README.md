<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# Cifrado en el sitio: LUKS2 + TPM2 + PIN con btrfs y Limine

> [!CAUTION]
> **RIESGO DE PÉRDIDA TOTAL DE DATOS.** Estos scripts cifran la raíz y /home **en el sitio**, sin reinstalar
> (`cryptsetup reencrypt`). Un error de configuración, un fallo de hardware o un corte mal recuperado pueden dejar
> **todos** los datos ilegibles.
>
> - Tenga una **copia de seguridad completa y comprobada** (restaurada de prueba) fuera de este disco.
> - Pase antes la **prueba en seco** (`cifrado-prueba-loop.sh`) y el **modo de prueba** (`cifrado-live.sh --prueba`)
>   sin ninguna línea `MAL`.
> - **Cargador conectado** todo el tiempo. No cierre la tapa ni apague.
> - Guarde la frase, el PIN y la clave de recuperación en **su gestor de contraseñas**, accesible desde **otro
>   dispositivo** (el móvil).
>
> Se distribuye SIN NINGUNA GARANTÍA (GPL-3.0-or-later). Úselo bajo su responsabilidad.

La guía completa, paso a paso, está en [`guias/cifrado-luks2-tpm2-limine.md`](../../guias/cifrado-luks2-tpm2-limine.md).
Léala entera antes de empezar: los scripts remiten a sus apartados cuando algo falla.

## Qué hace

1. Reduce cada btrfs (raíz y /home) un poco para dejar sitio a la cabecera LUKS2 y lo cifra en el sitio con
   `cryptsetup reencrypt --encrypt --reduce-device-size` desde el entorno live. El btrfs conserva su UUID: `fstab`
   no cambia. Un corte de luz a mitad se recupera (`repair` + `reencrypt --resume-only`).
2. Abre con TRIM persistente, crece el btrfs y lo verifica con `scrub`.
3. Configura el arranque: `crypttab.initramfs` (raíz), `crypttab` con fichero de clave (/home), hook `sd-encrypt` en
   mkinitcpio, `rd.luks.name=` en `/etc/default/limine`, y regenera initramfs y entradas con `limine-mkinitcpio`.
4. Ya en el sistema cifrado: TPM2 + PIN con `systemd-cryptenroll` (PCR 7 por defecto), clave de recuperación (la
   misma en raíz y /home) y copia de las cabeceras LUKS.

Nunca se muestran ni se registran la frase ni el PIN; la clave de recuperación recién generada solo se muestra en el
terminal (`/dev/tty`), fuera del registro, y hay que teclearla entera para confirmar que se ha guardado.

## Requisitos

- **CachyOS o Arch Linux**, arranque UEFI con **Limine** y `limine-mkinitcpio` (paquete `limine-mkinitcpio-hook`).
  **systemd-boot NO** está soportado (ni GRUB).
- Raíz y /home en **dos particiones btrfs distintas** del mismo disco, más la ESP (que no se cifra).
- initramfs basado en systemd (hook `systemd` en `HOOKS` de `/etc/mkinitcpio.conf`), necesario para `sd-encrypt`.
- `cryptsetup` 2.8 o posterior en el live, `jq`, `btrfs-progs`, `arch-chroot`. Opcional: `snapper` y
  `limine-snapper-sync`.
- TPM2 (`/dev/tpmrm0`; compruébelo con `systemd-cryptenroll --tpm2-device=list`). Sin TPM2 se puede cifrar igual y
  usar solo la frase.
- Un USB con el live de CachyOS (por ejemplo, un USB multiarranque creado con ventoy; partición de datos exFAT) donde copiar estos scripts.
- Una copia de seguridad completa y comprobada.

## Ficheros

| Fichero | Dónde se ejecuta | Qué hace | Escribe en disco |
|---|---|---|---|
| `cifrado.conf.example` | — | Todas las variables del equipo, con cómo obtener cada una. Cópielo como `cifrado.conf`. | — |
| `cifrado-comun.sh` | — | Funciones comunes (lo cargan los demás). | — |
| `cifrado-inventario.sh` | sistema instalado | Inventario de solo lectura (ESP, Limine, crypttab, btrfs, EFI, TPM2, Secure Boot) y **propuesta de `cifrado.conf`** (`--conf`). | No |
| `cifrado-prueba-loop.sh` | sistema instalado | Prueba en seco con una imagen en `/var/tmp`: cifra, corta 13 veces con `kill -9`, recupera, descifra. Mide la velocidad. | Solo su imagen |
| `cifrado-limpiar-prueba.sh` | sistema instalado | Limpia los restos de una prueba en seco interrumpida y comprueba que el disco real sigue en claro. | Solo restos de la prueba |
| `cifrado-copiar.sh` | sistema instalado | Rehace `SHA256SUMS` y copia los scripts al USB, a la ESP (plan B) y al destino en red, verificados. | USB, ESP, red |
| `cifrado-preparar.sh` | sistema instalado | Comprobaciones, fichero de clave de /home, `sd-encrypt` y `crypttab.initramfs` (con `nofail`), copia de seguridad, instantáneas. No cifra. | Sí |
| `cifrado-live.sh` | **live** | `--prueba`: lo comprueba todo sin escribir. Modo real: cifra raíz y /home y configura el arranque. | Sí (cifra) |
| `cifrado-reanudar.sh` | **live** | Reanuda tras un corte o un error. | Sí |
| `cifrado-rescate.sh` | **live** | Si ya cifrado no arranca: abre con frase o clave de recuperación y rehace el arranque o monta para mirar. | Sí |
| `cifrado-primer-arranque.sh` | sistema cifrado | TPM2 + PIN, clave de recuperación, copia de cabeceras. `--comprobar`: solo lectura. | Sí (huecos LUKS) |
| `cifrado-cambiar-pin.sh` | sistema cifrado | Sustituye el PIN del TPM2. | Sí (huecos LUKS) |
| `cifrado-nueva-recuperacion.sh` | sistema cifrado | Sustituye la clave de recuperación y rehace las copias de cabeceras. | Sí (huecos LUKS) |

## Salvaguardas

- **Sin argumentos, ningún script hace nada**: muestra su ayuda y sale.
- Los que escriben en disco exigen **a la vez** `--ejecutar` y `--acepto-perdida-de-datos`, muestran un aviso en
  mayúsculas y piden una **confirmación tecleada** (el nombre del disco, p. ej. `nvme0n1`). Si el equipo va con batería,
  se niegan.
- Solo son de solo lectura y se pueden ejecutar directamente: `cifrado-inventario.sh`, `cifrado-live.sh --prueba` y
  `cifrado-primer-arranque.sh --comprobar` (estos dejan solo su registro).
- Antes de tocar nada se comprueba el disco por **número de serie**, cada partición por **PARTUUID** y **tamaño
  exacto**, y el btrfs/LUKS por su **UUID**. Si algo no coincide con `cifrado.conf`, se paran.
- Cada fichero del sistema que se cambia se copia antes (`.bak.cifrado` o `.bak.<fecha>-cifrado`).
- Los registros van a `registros/` junto a los scripts (o a `DIR_REGISTROS`), con permisos 0600.

## Orden de uso

En el **sistema instalado, sin cifrar**:

```bash
sudo bash cifrado-inventario.sh                       # leer el inventario
bash cifrado-inventario.sh --conf > cifrado.conf.propuesta
# revisar la propuesta con lsblk/blkid y guardarla como cifrado.conf
sudo bash cifrado-prueba-loop.sh --ejecutar --acepto-perdida-de-datos     # prueba en seco (10–30 min)
sudo bash cifrado-copiar.sh --ejecutar --acepto-perdida-de-datos          # al USB, la ESP y la red
sudo bash cifrado-preparar.sh --ejecutar --acepto-perdida-de-datos        # no cifra; copia de seguridad incluida
# reiniciar una vez para comprobar que arranca; apagar
```

En el **entorno live** (desde la carpeta de los scripts en el USB; plan B: la misma carpeta en la ESP):

```bash
sha256sum -c SHA256SUMS
sudo bash cifrado-live.sh --prueba                                        # SIEMPRE primero
sudo bash cifrado-live.sh --ejecutar --acepto-perdida-de-datos
# si se corta:   sudo bash cifrado-reanudar.sh --ejecutar --acepto-perdida-de-datos
# si no arranca: sudo bash cifrado-rescate.sh --ejecutar --acepto-perdida-de-datos
```

Ya en el **sistema cifrado** (tras entrar con la frase):

```bash
sudo bash cifrado-primer-arranque.sh --ejecutar --acepto-perdida-de-datos
# reiniciar y teclear el PIN
sudo bash cifrado-primer-arranque.sh --comprobar
```

Más adelante, si hace falta: `cifrado-cambiar-pin.sh` y `cifrado-nueva-recuperacion.sh`.

## Notas

- Las copias de las cabeceras LUKS (`DIR_CABECERAS`) siguen abriendo con las claves que había al hacerlas: trátelas
  como secretos y sustitúyalas si cambia la frase o la clave de recuperación (`cifrado-nueva-recuperacion.sh`).
- El fichero de clave de /home vive dentro de la raíz cifrada y no debe salir del equipo: `cifrado-preparar.sh` lo
  añade a los ficheros de exclusión de `COPIA_EXCLUIR`.
- El TPM2 se ata al PCR 7 (estado de Secure Boot). Si cambia (actualización de firmware, cambios en Secure Boot), el
  PIN deja de valer y el arranque pide la frase: entre con ella y vuelva a inscribir con `cifrado-cambiar-pin.sh`.
