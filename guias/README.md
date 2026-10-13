<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# Guías de Estación

Guías prácticas para un escritorio CachyOS (o Arch) con Hyprland, Caelestia Shell, UWSM, Limine, btrfs y snapper.
Están escritas en español de España; los comandos son de bash. Cada guía incluye «Requisitos», «Cómo comprobar si le
afecta», los pasos, la verificación y la marcha atrás.

Los valores de ejemplo son ficticios (red `192.168.0.0/24`, IP `192.0.2.x`, MAC `00:00:5e:00:53:xx`, usuario
«usuario», NAS «nas.local»): sustitúyalos por los suyos, normalmente en `/etc/estacion/estacion.conf`
(ejemplo en `sistema/estacion.conf.example`).

## Recuperación y copias

| Guía | Para qué |
|---|---|
| [copias-restic-smb.md](copias-restic-smb.md) | Copia diaria con restic en un NAS por SMB 3.1.1 cifrado, desde instantáneas, con avisos y mantenimiento. |
| [restaurar.md](restaurar.md) | Recuperar ficheros o el sistema desde snapper, Limine o restic. |
| [reinstalar.md](reinstalar.md) | Reconstruir un equipo desde cero con la copia restic e `instalar.sh`. |
| [snapper-limine.md](snapper-limine.md) | Instantáneas arrancables con `limine-snapper-sync`; UNIQUE_NUMBERS. |

## Seguridad

| Guía | Para qué |
|---|---|
| [cifrado-luks2-tpm2-limine.md](cifrado-luks2-tpm2-limine.md) | **Cifrar en el sitio** `/` y `/home` (LUKS2, TPM2 + PIN, clave de recuperación, cabeceras, rescate). Lea el aviso de riesgo. |
| [endurecimiento.md](endurecimiento.md) | ufw solo en casa, sysctl, LLMNR, DNS cifrado, MAC por red, RAPL sin canal lateral. |
| [perfiles-energia.md](perfiles-energia.md) | Perfiles de energía de Caelestia con power-profiles-daemon: qué cambian, cómo medirlos y aplicarlos desde el arranque. |
| [autofirma-nss-firefox-zen.md](autofirma-nss-firefox-zen.md) | AutoFirma con el almacén de certificados de Firefox o Zen; `afirma://`. |

## Hardware y aplicaciones

| Guía | Para qué |
|---|---|
| [touchpad-elan-irq.md](touchpad-elan-irq.md) | Touchpad ELAN I2C que desaparece al arrancar («nobody cared», «controller timed out»). |
| [bluetooth-multipunto.md](bluetooth-multipunto.md) | Auriculares multipunto, reconexión al encender y recordar el estado del Bluetooth. |
| [parsec.md](parsec.md) | Cliente de Parsec: autoactualización, copia y vigilancia. |
| [spotify-hyprland.md](spotify-hyprland.md) | spicetify con ACL mínima, vidrio solo con opacidad y Wayland nativo. |

## Relacionado

- `sistema/`: `instalar.sh` y sus componentes (`copia`, `touchpad`, `bluetooth`, `red`, `endurecimiento`,
  `energia`, `avisos`, `escritorio`).
- `sistema/cifrado/`: scripts `cifrado-*.sh` y `cifrado.conf.example`.
- `caelestia/`: traducción y parches de Caelestia Shell.
- `paquetes/`: paquetes por función.

Licencia: GPL-3.0-or-later (vea `LICENSE`). Sin garantía de ningún tipo: haga copia antes de cambiar su sistema.
