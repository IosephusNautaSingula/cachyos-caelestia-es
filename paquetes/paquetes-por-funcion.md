<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# Paquetes por función

Los paquetes instalados explícitamente en un escritorio Estación (CachyOS + Hyprland + Caelestia Shell + UWSM +
Limine + snapper), agrupados por función. La lista plana para instalar está en
[paquetes-por-funcion.txt](paquetes-por-funcion.txt).

**Origen:**

- **oficial**: repositorios de Arch (`core`, `extra`, `multilib`) o sus equivalentes optimizados de CachyOS
  (`cachyos-core-v3`, `cachyos-extra-v3`…). En Arch puro algún paquete concreto puede no existir: pacman le avisará.
- **CachyOS**: solo en los repositorios de CachyOS.
- **CachyOS (en Arch: AUR)**: en CachyOS vienen firmados en su repositorio; en Arch hay que tomarlos de AUR.
- **AUR**: compílelos con un ayudante (paru) **revisando cada PKGBUILD** y confirmando usted cada paso.
- **local**: PKGBUILD de este proyecto.

Los paquetes `lib32-*` necesitan el repositorio `multilib` activado. Los marcados como específicos de Intel
(microcódigo, vídeo, Vulkan, audio SOF, `intel-lpmd`) se sustituyen en equipos AMD por `amd-ucode`,
`vulkan-radeon`, `lib32-vulkan-radeon` y `libva-mesa-driver`.

Se han dejado fuera los paquetes locales que no son reutilizables. En su lugar, el paquete de la interfaz es **`caelestia-shell-es`**: el PKGBUILD de `caelestia/`,
que aplica la traducción al español y los parches sobre Caelestia Shell.

## Núcleo, arranque y firmware

Kernel (con uno LTS de respaldo), Limine con sus ganchos de mkinitcpio y de snapper, firmware y energía.

| Paquete | Origen | Nota |
|---|---|---|
| `alsa-firmware` | oficial |  |
| `base` | oficial |  |
| `base-devel` | oficial |  |
| `chwd` | CachyOS |  |
| `cpupower` | oficial |  |
| `efibootmgr` | oficial |  |
| `efitools` | oficial |  |
| `fwupd` | oficial |  |
| `hwdetect` | oficial |  |
| `hwinfo` | oficial |  |
| `intel-lpmd` | oficial | específico de Intel |
| `intel-ucode` | oficial | específico de Intel |
| `limine` | oficial |  |
| `limine-mkinitcpio-hook` | CachyOS (en Arch: AUR) |  |
| `limine-snapper-sync` | CachyOS (en Arch: AUR) |  |
| `linux-cachyos` | CachyOS |  |
| `linux-cachyos-headers` | CachyOS |  |
| `linux-cachyos-lts` | CachyOS |  |
| `linux-cachyos-lts-headers` | CachyOS |  |
| `linux-firmware` | oficial |  |
| `mkinitcpio` | oficial |  |
| `os-prober` | oficial |  |
| `plymouth` | oficial |  |
| `power-profiles-daemon` | oficial |  |
| `realtime-privileges` | oficial |  |
| `sof-firmware` | oficial | específico de Intel |

## Propios de CachyOS

Configuración, ganchos, claves y espejos de CachyOS. Solo tienen sentido en CachyOS.

| Paquete | Origen | Nota |
|---|---|---|
| `cachyos-fish-config` | CachyOS |  |
| `cachyos-hooks` | CachyOS |  |
| `cachyos-keyring` | CachyOS |  |
| `cachyos-mirrorlist` | CachyOS |  |
| `cachyos-plymouth-bootanimation` | CachyOS |  |
| `cachyos-plymouth-theme` | CachyOS |  |
| `cachyos-rate-mirrors` | CachyOS |  |
| `cachyos-settings` | CachyOS |  |
| `cachyos-snapper-support` | CachyOS |  |
| `cachyos-v3-mirrorlist` | CachyOS |  |
| `cachyos-v4-mirrorlist` | CachyOS |  |
| `cachyos-wallpapers` | CachyOS |  |

## Discos, cifrado e instantáneas

btrfs, snapper, cryptsetup, restic y herramientas de sistemas de ficheros.

| Paquete | Origen | Nota |
|---|---|---|
| `btrfs-assistant` | oficial |  |
| `btrfs-progs` | oficial |  |
| `cryptsetup` | oficial |  |
| `device-mapper` | oficial |  |
| `dmraid` | oficial |  |
| `dosfstools` | oficial |  |
| `e2fsprogs` | oficial |  |
| `exfatprogs` | oficial |  |
| `f2fs-tools` | oficial |  |
| `fsarchiver` | oficial |  |
| `hdparm` | oficial |  |
| `jfsutils` | oficial |  |
| `lsscsi` | oficial |  |
| `lvm2` | oficial |  |
| `mdadm` | oficial |  |
| `mtools` | oficial |  |
| `nfs-utils` | oficial |  |
| `nilfs-utils` | oficial |  |
| `restic` | oficial |  |
| `rsync` | oficial |  |
| `sg3_utils` | oficial |  |
| `smartmontools` | oficial |  |
| `snapper` | oficial |  |
| `xfsprogs` | oficial |  |

## Escritorio (Hyprland y Caelestia)

Hyprland con UWSM, Caelestia Shell (quickshell), SDDM, portales, llavero y utilidades de Wayland.

| Paquete | Origen | Nota |
|---|---|---|
| `accountsservice` | oficial |  |
| `adw-gtk-theme` | oficial |  |
| `caelestia-cli` | AUR | trae como dependencias de AUR qt6-m3shapes-git, python-materialyoucolor, libcava y ttf-rubik-vf |
| `caelestia-shell-es` | local | PKGBUILD de `caelestia/` (traducción y parches); `makepkg -si` como usuario |
| `cliphist` | oficial |  |
| `darkly-bin` | AUR |  |
| `foot` | oficial |  |
| `frameworkintegration` | oficial |  |
| `gnome-keyring` | oficial |  |
| `hyprland` | oficial |  |
| `hyprpicker` | oficial |  |
| `mission-center` | oficial |  |
| `papirus-folders` | AUR |  |
| `papirus-icon-theme` | oficial |  |
| `polkit-gnome` | oficial |  |
| `qt6-wayland` | oficial |  |
| `qtengine` | AUR |  |
| `quickshell-git` | AUR | conviene recompilarlo tras cada actualización de Qt6 (aviso `qt6-rebuild-aviso`) |
| `sddm` | oficial |  |
| `thunar` | oficial |  |
| `uwsm` | oficial |  |
| `wl-clipboard` | oficial |  |
| `xdg-desktop-portal-gtk` | oficial |  |
| `xdg-desktop-portal-hyprland` | oficial |  |
| `xdg-user-dirs` | oficial |  |
| `ydotool` | oficial |  |

## Fuentes

Tipografías de la interfaz, del terminal (Nerd Fonts) y de compatibilidad.

| Paquete | Origen | Nota |
|---|---|---|
| `awesome-terminal-fonts` | oficial |  |
| `cantarell-fonts` | oficial |  |
| `inter-font` | oficial |  |
| `noto-fonts` | oficial |  |
| `noto-fonts-cjk` | oficial |  |
| `noto-fonts-emoji` | oficial |  |
| `ttf-bitstream-vera` | oficial |  |
| `ttf-dejavu` | oficial |  |
| `ttf-jetbrains-mono-nerd` | oficial |  |
| `ttf-liberation` | oficial |  |
| `ttf-meslo-nerd` | oficial |  |
| `ttf-opensans` | oficial |  |

## Audio, vídeo y gráficos

PipeWire, códecs de GStreamer, Mesa/Vulkan y aceleración de vídeo.

| Paquete | Origen | Nota |
|---|---|---|
| `alsa-plugins` | oficial |  |
| `alsa-utils` | oficial |  |
| `ffmpegthumbnailer` | oficial |  |
| `gst-libav` | oficial |  |
| `gst-plugin-pipewire` | oficial |  |
| `gst-plugin-va` | oficial |  |
| `gst-plugins-bad` | oficial |  |
| `gst-plugins-ugly` | oficial |  |
| `intel-media-driver` | oficial | específico de Intel |
| `lib32-mesa` | oficial |  |
| `lib32-opencl-mesa` | oficial |  |
| `lib32-vulkan-intel` | oficial | específico de Intel |
| `libdvdcss` | oficial |  |
| `libgsf` | oficial |  |
| `libopenraw` | oficial |  |
| `mesa-utils` | oficial |  |
| `opencl-mesa` | oficial |  |
| `pipewire` | oficial |  |
| `pipewire-alsa` | oficial |  |
| `pipewire-audio` | oficial |  |
| `pipewire-jack` | oficial |  |
| `pipewire-pulse` | oficial |  |
| `poppler-glib` | oficial |  |
| `pwvucontrol` | oficial |  |
| `vlc-plugins-all` | oficial |  |
| `vpl-gpu-rt` | oficial | específico de Intel |
| `vulkan-headers` | oficial |  |
| `vulkan-intel` | oficial | específico de Intel |
| `wireplumber` | oficial |  |

## Red, Bluetooth y cortafuegos

NetworkManager, BlueZ con blueman como agente, ufw y utilidades de red.

| Paquete | Origen | Nota |
|---|---|---|
| `bind` | oficial |  |
| `blueman` | oficial | agente de Bluetooth: [guía](../guias/bluetooth-multipunto.md) |
| `bluez` | oficial |  |
| `bluez-hid2hci` | oficial |  |
| `bluez-libs` | oficial |  |
| `bluez-obex` | oficial |  |
| `bluez-utils` | oficial |  |
| `curl` | oficial |  |
| `dnsmasq` | oficial |  |
| `ethtool` | oficial |  |
| `inetutils` | oficial |  |
| `iwd` | oficial |  |
| `modemmanager` | oficial |  |
| `netctl` | oficial |  |
| `networkmanager` | oficial |  |
| `networkmanager-openvpn` | oficial |  |
| `nss-mdns` | oficial |  |
| `openssh` | oficial |  |
| `ufw` | oficial |  |
| `ufw-extras` | oficial |  |
| `usb_modeswitch` | oficial |  |
| `wget` | oficial |  |
| `wpa_supplicant` | oficial |  |
| `xl2tpd` | oficial |  |

## Aplicaciones

Navegador, gestor de contraseñas, mensajería, música, editor, escritorio remoto y firma electrónica.

| Paquete | Origen | Nota |
|---|---|---|
| `autofirma-bin` | AUR | necesita jre17-openjdk; [guía](../guias/autofirma-nss-firefox-zen.md) |
| `bitwarden` | oficial |  |
| `parsec-bin` | CachyOS (en Arch: AUR) | [guía](../guias/parsec.md) |
| `spicetify-cli` | AUR |  |
| `spicetify-marketplace-bin` | AUR |  |
| `spotify` | AUR | spicetify con ACL mínima: [guía](../guias/spotify-hyprland.md) |
| `telegram-desktop` | oficial |  |
| `visual-studio-code-bin` | AUR |  |
| `zen-browser-bin` | CachyOS (en Arch: AUR) |  |

## Terminal y desarrollo

fish, Neovim, git y herramientas de terminal y de compilación.

| Paquete | Origen | Nota |
|---|---|---|
| `bash-completion` | oficial |  |
| `bat` | oficial |  |
| `btop` | oficial |  |
| `cli11` | oficial |  |
| `cmake` | oficial |  |
| `direnv` | oficial |  |
| `duf` | oficial |  |
| `extra-cmake-modules` | oficial |  |
| `eza` | oficial |  |
| `fastfetch` | oficial |  |
| `fish` | oficial |  |
| `git` | oficial |  |
| `github-cli` | oficial |  |
| `glances` | oficial |  |
| `inotify-tools` | oficial |  |
| `jq` | oficial |  |
| `lazygit` | oficial |  |
| `less` | oficial |  |
| `man-db` | oficial |  |
| `man-pages` | oficial |  |
| `mise` | oficial |  |
| `nano` | oficial |  |
| `nano-syntax-highlighting` | oficial |  |
| `neovim` | oficial |  |
| `ninja` | oficial |  |
| `nodejs` | oficial |  |
| `perl` | oficial |  |
| `pkgfile` | oficial |  |
| `plocate` | oficial |  |
| `pnpm` | oficial |  |
| `pv` | oficial |  |
| `python` | oficial |  |
| `python-defusedxml` | oficial |  |
| `python-gobject` | oficial |  |
| `python-packaging` | oficial |  |
| `ripgrep` | oficial |  |
| `starship` | oficial |  |
| `texinfo` | oficial |  |
| `trash-cli` | oficial |  |
| `uv` | oficial |  |
| `which` | oficial |  |
| `zoxide` | oficial |  |
| `zsh` | oficial |  |

## Paquetes y sistema

Ayudante de AUR, downgrade, utilidades de pacman y del sistema.

| Paquete | Origen | Nota |
|---|---|---|
| `diffutils` | oficial |  |
| `dmidecode` | oficial |  |
| `downgrade` | CachyOS (en Arch: AUR) |  |
| `logrotate` | oficial |  |
| `lsb-release` | oficial |  |
| `pacman-contrib` | oficial |  |
| `paru` | CachyOS (en Arch: AUR) |  |
| `rebuild-detector` | oficial |  |
| `reflector` | oficial |  |
| `s-nail` | oficial |  |
| `sudo` | oficial |  |
| `sysfsutils` | oficial |  |
| `unrar` | oficial |  |
| `unzip` | oficial |  |
| `usbutils` | oficial |  |

## Instalación

```bash
# Repositorios (pacman pide confirmación: respóndala usted):
sudo pacman -S --needed $(grep -v '^#' paquetes/paquetes-por-funcion.txt)
# En Arch (sin repositorios de CachyOS), quite antes el bloque «Solo CachyOS»:
sudo pacman -S --needed $(sed '/^# == Solo CachyOS/,/^# == Fin de solo CachyOS/d' paquetes/paquetes-por-funcion.txt | grep -v '^#')
# AUR (revise cada PKGBUILD):
paru -S --needed autofirma-bin caelestia-cli darkly-bin papirus-folders qtengine quickshell-git spicetify-cli spicetify-marketplace-bin spotify visual-studio-code-bin
# Local: en el directorio caelestia/ (PKGBUILD.example):
makepkg -si
```

Total en las tablas: 223 paquetes.
