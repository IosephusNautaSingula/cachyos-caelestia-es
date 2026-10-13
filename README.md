<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# cachyos-caelestia-es

**CachyOS + Hyprland + Caelestia: mejoras, arreglos y adaptación al español.**

Mejoras, arreglos, scripts, servicios, configuración y guías nacidos de poner a punto un portátil de trabajo con
**CachyOS**, **Hyprland** (configuración en Lua) y **Caelestia Shell**, con sesión **UWSM**, arranque **Limine**,
instantáneas **snapper** y disco cifrado **LUKS2 con TPM2 + PIN**. Todo está pensado para reutilizarse en otros
equipos y escrito, sobre todo, para la comunidad hispanohablante. Los comandos, servicios y ficheros que instala
llevan el prefijo `estacion-`.

> **English summary.** Patches, fixes, scripts, systemd units, configuration and step-by-step guides (in Spanish)
> for a CachyOS + Hyprland (Lua config) + Caelestia Shell desktop with UWSM, Limine, snapper and in-place LUKS2
> encryption with TPM2 + PIN. Highlights: a full Spanish (es_ES) translation of Caelestia Shell and locale fixes
> ready as upstream PRs (`caelestia/`, descriptions in English and Spanish); a restic-over-SMB backup service with
> btrfs snapshots; a fix for ELAN I²C touchpads whose controller IRQ gets disabled at boot ("nobody cared");
> AutoFirma (Spanish e-signature) with Firefox/Zen NSS stores; and a guarded toolkit to encrypt an existing btrfs
> install in place. Hardware-specific fixes only apply when the hardware is detected. Everything installs with
> `sistema/instalar.sh` (try `--prueba` first: dry run, touches nothing). License: GPL-3.0-or-later.

## Qué hay

| Directorio | Contenido |
|---|---|
| [`caelestia/`](caelestia/) | Parches para Caelestia Shell, uno por arreglo y listos como PR (descripción en inglés y en español): traducción completa al español, fechas y números según el idioma, notificaciones que llevan a su aplicación, indicador de ventana urgente, «Mantener activo» que manda sobre la inactividad, barra lateral con atajo… y tres personalizaciones de color opcionales. Incluye un `PKGBUILD.example` para construir la shell con los parches que elija. |
| [`sistema/`](sistema/) | Scripts y servicios con su **instalador** y **desinstalador**: copias restic al NAS, avisos, touchpad ELAN, Bluetooth que recuerda su estado y reconecta, cortafuegos solo en la red de casa, endurecimiento, permisos de RAPL, avisos de actualización y de recompilar tras Qt6, ajustes de volumen y brillo con aceleración, tema de Zen con los colores de Caelestia, AutoFirma, herramientas de prueba. |
| [`sistema/cifrado/`](sistema/cifrado/) | Cifrado LUKS2 **en el sitio** (sin reinstalar) con TPM2 + PIN y Limine. **Riesgo de pérdida de datos:** nada se ejecuta por defecto. |
| [`config/`](config/) | Configuración de Hyprland, Caelestia, UWSM, entradas `.desktop`, navegador, Neovim, Spotify, VS Code y plantillas de chezmoi. |
| [`guias/`](guias/) | Guías paso a paso: reinstalar, restaurar, cifrado LUKS2 con TPM2 + PIN, copias restic por SMB, AutoFirma con NSS, Parsec, Bluetooth multipunto, touchpad ELAN con la IRQ desactivada, snapper con Limine, endurecimiento y Spotify en Hyprland. |
| [`paquetes/`](paquetes/) | Lista de paquetes por función (repositorios y AUR). |

## Requisitos

- **CachyOS** (o Arch Linux con los mismos paquetes) con systemd.
- **Hyprland** con configuración en Lua y los **dots de Caelestia** (Caelestia Shell sobre Quickshell).
- **UWSM** para la sesión, **SDDM** (u otro gestor de inicio de sesión).
- **Limine** con `limine-mkinitcpio-hook` y **limine-snapper-sync**; **btrfs** con **snapper** (configuraciones de `/` y `/home`).
- Para las copias: **restic** y un NAS con SMB 3.
- Para el cifrado: TPM 2.0, `cryptsetup` 2.4 o posterior, `systemd-cryptenroll`, un USB con un sistema en vivo y una
  copia completa comprobada.

## Instalación

```bash
git clone https://github.com/<usuario>/cachyos-caelestia-es.git && cd cachyos-caelestia-es

# 1. Configuración del equipo (todo lo que depende de su equipo está aquí; nada va fijo en los scripts)
sudo install -d -m 755 /etc/estacion
sudo install -m 644 sistema/estacion.conf.example /etc/estacion/estacion.conf
sudoedit /etc/estacion/estacion.conf

# 2. Ver qué haría, sin tocar nada (no necesita root)
bash sistema/instalar.sh --prueba
bash sistema/instalar.sh --prueba --usuario

# 3. Instalar (pide confirmación; con --solo elige componentes, p. ej. --solo copia,bluetooth)
sudo bash sistema/instalar.sh
bash sistema/instalar.sh --usuario

# Desinstalar: sistema/desinstalar.sh (mismas opciones, también --prueba)
```

Los arreglos de hardware (touchpad ELAN, por ejemplo) solo se instalan si el instalador detecta ese hardware. Los
parches de Caelestia se construyen con `caelestia/PKGBUILD.example` (`makepkg -si`, revisando cada paso). La
configuración de `config/` se copia a mano o con chezmoi.

## Seguridad y privacidad

- Ningún fichero contiene datos de un equipo concreto: IP, nombres del NAS, usuarios, UUID, números de serie y demás
  son variables de `/etc/estacion/estacion.conf` o de `sistema/cifrado/cifrado.conf`, con ejemplos ficticios.
- Las credenciales (SMB, clave de restic, claves LUKS, certificados) **nunca** forman parte del proyecto: cada
  usuario las crea en su equipo con permisos 0600, como explican las guías.
- Ningún comando usa `--noconfirm`, y nada abre permisos (`chmod a+rw`).

## Licencia

GPL-3.0-or-later (ver [`LICENSE`](LICENSE)). Cada fichero lleva su identificador SPDX, salvo los JSON, que no admiten
comentarios. Caelestia Shell es software de sus autores bajo GPL-3.0-only; los parches de `caelestia/` se ofrecen
bajo GPL-3.0-or-later, que es compatible: el proyecto puede incorporarlos bajo su propia licencia.
