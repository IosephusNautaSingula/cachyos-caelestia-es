<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# Estación · sistema

Scripts, unidades de systemd, reglas y ajustes del sistema de Estación para un escritorio CachyOS (o Arch) con
Hyprland, Caelestia Shell, UWSM, Limine y snapper. Todo lo que depende del equipo se lee de
`/etc/estacion/estacion.conf` (o de variables de entorno); no hay nada fijo de un equipo concreto.

## Contenido

| Directorio / fichero | Qué es |
|---|---|
| `bin/` | órdenes `estacion-*`, `qt6-rebuild-aviso`, `spotify-spicetify-acl` y la envoltura `autofirma` |
| `systemd/system/`, `systemd/user/` | unidades de sistema y de usuario |
| `udev/` | reglas `90-estacion-*.rules` |
| `sleep/` | gancho de suspensión `estacion-touchpad` (`/usr/lib/systemd/system-sleep/`) |
| `mkinitcpio/` | `20-estacion-touchpad.conf` (módulos del touchpad en el initramfs) |
| `pacman-hooks/` | `qt6-rebuild-aviso.hook`, `spotify-spicetify.hook` |
| `networkmanager/` | dispatcher `90-estacion-cortafuegos-casa` y `90-estacion-mac.conf` |
| `sysctl/`, `resolved/` | endurecimiento y DNS |
| `sudoers/` | ejemplo comentado (no se instala) |
| `share/fundido-salida/shell.qml` | fundido a negro al cerrar sesión (Quickshell) |
| `herramientas/` | utilidades de prueba y medición (no se instalan) |
| `lib/comun.sh` | catálogo y funciones comunes del instalador y el desinstalador |
| `estacion.conf.example`, `excluir.txt.example` | ejemplos de configuración |
| `instalar.sh`, `desinstalar.sh` | instalador y desinstalador |

## Requisitos

- Arch Linux o CachyOS con systemd, `bash`, `pacman`. Para cada componente, además:
  - **copia**: `restic`; en modo SMB, `cifs-utils`; opcional `snapper` y `/` y `/home` en btrfs (instantáneas
    consistentes).
  - **red**: NetworkManager; `ufw` para el cortafuegos de casa; systemd-resolved para el DNS.
  - **bluetooth**: BlueZ (`bluetoothctl`, `busctl`, `gdbus`).
  - **avisos**: `paru`, `pacman-contrib` (`checkupdates`, `pacdiff`), `rebuild-detector` (`checkrebuild`), `curl`,
    `python3`, `libnotify`.
  - **escritorio**: Hyprland, Caelestia Shell (`qs`), `wireplumber` (`wpctl`), `jq`, `brightnessctl`; Zen para el
    tema; AutoFirma, `nss` (`certutil`) y `openssl` para la integración de AutoFirma; `gh` o `curl`, `bsdtar`,
    `patch`, `gettext`, `perl` para el comprobador de Caelestia.

## Configuración

1. Copie el ejemplo y póngale sus valores (el instalador lo hace por usted si no existe):

   ```bash
   sudo install -D -m 0644 estacion.conf.example /etc/estacion/estacion.conf
   sudoedit /etc/estacion/estacion.conf
   ```

2. El fichero se lee como texto (no se ejecuta) y debe ser de root y no escribible por otros. Las variables de
   entorno tienen prioridad. Los scripts de usuario leen antes `~/.config/estacion/estacion.conf`, si existe.
3. **No guarde secretos ahí.** Los secretos de la copia van en ficheros aparte, 0600 y de root, que crea usted
   (ver «copia»). El instalador nunca los crea.

## Instalación

```bash
bash sistema/instalar.sh --prueba                 # ver qué haría la parte de sistema (sin root, no cambia nada)
bash sistema/instalar.sh --prueba --usuario       # ídem para la parte de usuario
sudo bash sistema/instalar.sh                     # parte de sistema (muestra el plan y pide confirmación)
bash sistema/instalar.sh --usuario                # parte de usuario, con su usuario (nunca como root)
sudo bash sistema/instalar.sh --solo copia,red    # solo algunos componentes
sudo bash sistema/instalar.sh --conf mi.conf      # usar (e instalar como /etc/estacion/estacion.conf) otro fichero
```

- `--prueba` no crea directorios, ni ficheros temporales, ni llama a `systemctl`: solo imprime cada acción
  (`[prueba] install -D -m 755 … → …`). Si no hay `/etc/estacion/estacion.conf`, usa `estacion.conf.example`.
- Antes de sobrescribir un fichero existente se guarda una copia `<fichero>.bak.AAAA-MM-DD-estacion`.
- Lo instalado se anota en `/var/lib/estacion/instalado.lista` (sistema) o
  `~/.local/state/estacion/instalado.lista` (usuario).

## Desinstalación

```bash
bash sistema/desinstalar.sh --prueba              # qué haría (sin lista, lo simula con el catálogo completo)
sudo bash sistema/desinstalar.sh                  # parte de sistema
bash sistema/desinstalar.sh --usuario             # parte de usuario
sudo bash sistema/desinstalar.sh --purgar         # además, estado y /etc/estacion (pide confirmación aparte)
```

Deshabilita y para las unidades y quita **solo** lo que consta en la lista de instalación. Si al instalar se guardó
una copia `.bak…-estacion` de un fichero previo, le indica cómo restaurarla. No borra nunca el repositorio de copias
ni sus datos; `/etc/estacion` y el estado local solo con `--purgar`.

## Componentes

### copia

Copia diaria con restic a un NAS (SMB 3.1.1 cifrado) o a cualquier repositorio restic (`COPIA_MODO=directo`).

- `estacion-copia` (root): `/home` desde una instantánea de snapper recién creada (configuración
  `COPIA_SNAPPER_HOME`, por defecto `home`) y `/etc` desde una instantánea btrfs de solo lectura de `/` (no de
  snapper, para no llenar el menú de Limine); ambas se montan en un espacio de montaje privado y se borran al
  terminar. Sin snapper o sin btrfs se copia en vivo. Guarda además listas de paquetes y la configuración del
  arranque (`/var/lib/estacion-copia/sistema`). Retención: `COPIA_RETENCION`.
- `estacion-copia.timer` (20:30, con cargador), `estacion-copia-mantener.timer` (miércoles: `forget --prune` y
  `check`; la primera semana del mes también comprueba el 10 % de los datos), `estacion-copia-cargador.service` (al
  enchufar el cargador, si hoy aún no hay copia; lo lanza la regla de udev) y `estacion-copia-aviso@.service`
  (notificación en la sesión de `ESTACION_USUARIO` si una unidad falla, con el hint `x-caelestia-log` =
  `journal:<unidad>` para abrir el registro al pulsarla).
- Usuario: `estacion-copia-vigilar.timer` avisa si la última copia correcta tiene más de `COPIA_AVISO_DIAS` días.
- Exclusiones: `/etc/estacion/excluir.txt` (se instala desde `excluir.txt.example` si no existe).
- Secretos (los crea usted, 0600, de root; si faltan, el instalador explica cómo y **no** instala la copia):

  ```bash
  sudo install -d -m 0755 /etc/estacion
  sudo sh -c 'umask 077; cat > /etc/estacion/restic-clave'        # contraseña del repositorio; Intro y Ctrl+D
  sudo sh -c 'umask 077; cat > /etc/estacion/smb-credenciales'    # username=… y password=… (formato de mount.cifs)
  sudo estacion-copia restic init                                 # solo si el repositorio aún no existe
  ```

  Guarde la contraseña del repositorio también en su gestor de contraseñas: sin ella la copia no se puede leer.
- Uso manual: `sudo estacion-copia --ahora` (con cargador), `sudo estacion-copia restic snapshots`,
  registro con `journalctl -u estacion-copia`.

### touchpad (solo si se detecta el hardware)

Para algunos portátiles Lenovo con touchpad I2C-HID (p. ej. HID ACPI `ELAN06FA`) cuya primera lectura falla al
arrancar o al volver de suspensión («controller timed out», -110, a veces precedido de «irq N: nobody cared»).

- `estacion-touchpad` + `estacion-touchpad.service` + gancho de suspensión: si falta el touchpad, reinicia su
  controlador I2C. **La dirección PCI del controlador no es fija**: se calcula en cada ejecución siguiendo sysfs desde
  `/sys/bus/i2c/devices/i2c-${TOUCHPAD_HID}:00` hasta su primer antecesor PCI (o, si ese dispositivo no existe, desde
  el nodo ACPI del touchpad hasta el `physical_node` de su controlador). El driver PCI (normalmente `intel-lpss`)
  también se lee de sysfs.
- `20-estacion-touchpad.conf`: añade `pinctrl_tigerlake intel_lpss_pci i2c_hid_acpi hid_multitouch` al initramfs
  para que el touchpad se inicialice antes de pedir la frase del disco cifrado.
- Detección en el instalador:
  - todo el componente solo se instala si existe `/sys/bus/acpi/devices/${TOUCHPAD_HID}:*`;
  - el `.conf` del initramfs solo si, además, el controlador de pines es Tiger Lake (`pinctrl_tigerlake` en `lsmod`
    o un dispositivo con modalias `acpi:INT34C5:`/`acpi:INT34C6:`). Si no, avisa y no lo aplica: en otras
    plataformas el módulo es otro (p. ej. `pinctrl_alderlake`) y debe adaptarlo usted;
  - tras instalar el `.conf` hay que regenerar el initramfs: el instalador usa `limine-mkinitcpio` si existe o
    `mkinitcpio -P`, y le pide confirmación.
- Comprobación a mano:

  ```bash
  ls /sys/bus/acpi/devices/ | grep -iE 'elan|syna|alps'     # ¿qué HID tiene su touchpad?
  readlink -f /sys/bus/i2c/devices/i2c-ELAN06FA:00           # camino sysfs: el componente 0000:xx:yy.z es el PCI
  lsmod | grep pinctrl_                                      # ¿qué controlador de pines usa?
  grep -h . /sys/bus/platform/devices/*/modalias | grep -i INT34C
  estacion-touchpad --diagnostico                            # lo que detecta el script (no cambia nada)
  journalctl -t estacion-touchpad -b                         # qué hizo en este arranque
  lsinitcpio /boot/initramfs-linux-cachyos.img | grep -E 'i2c-hid|pinctrl'   # ¿están los módulos en el initramfs?
  ```

### bluetooth

- `estacion-bluetooth-recordar.service` (sistema): guarda al apagar si el Bluetooth estaba encendido y lo restaura al
  arrancar (BlueZ no lo recuerda). Estado en `/var/lib/estacion-bluetooth/estado`.
- `estacion-bluetooth-reconectar.service` (usuario): al encenderse el adaptador conecta una vez los dispositivos
  emparejados y de confianza (`BT_ADAPTADOR`, `BT_INTENTOS`, `BT_ESPERA`). No escribe direcciones en el registro.
- Recomendado (el instalador no toca este fichero, solo lo sugiere): en `/etc/bluetooth/main.conf`, sección
  `[Policy]`, `AutoEnable=false`, para que el encendido lo decida `estacion-bluetooth-recordar` y no BlueZ.

### red

- `90-estacion-cortafuegos-casa` (dispatcher de NetworkManager): con `ufw`, abre `CASA_PUERTOS` (por defecto Spotify
  Connect, 57621 tcp/udp) desde `CASA_RED` **solo** si está activa la conexión `CASA_CONEXION_UUID` y la puerta de
  enlace tiene la MAC `CASA_ROUTER_MAC`; fuera de casa retira las reglas. Valores:

  ```bash
  nmcli -g UUID,NAME connection show                              # CASA_CONEXION_UUID
  ip neigh show "$(ip -4 route show default | awk '{print $3; exit}')"   # CASA_ROUTER_MAC
  sudo ufw status | grep estacion-casa                            # ¿reglas puestas?
  ```

- `90-estacion-mac.conf`: MAC Wi-Fi «estable» (distinta en cada red, fija dentro de cada una).
- `91-estacion-dot.conf`: DNS sobre TLS oportunista (Cloudflare, respaldo Quad9). Compruébelo con `resolvectl status`.

### endurecimiento

- `90-estacion.conf` (sysctl): `fs.protected_fifos=2`, `fs.protected_regular=2`, `dev.tty.ldisc_autoload=0`, sin
  redirecciones ICMP, `kernel.kexec_load_disabled=1`. No toca los espacios de nombres de usuario ni ptrace.
  Compruébelo con `sysctl fs.protected_regular kernel.kexec_load_disabled`.
- `90-estacion.conf` (resolved): `LLMNR=no`.

### energia

- `90-estacion-powercap.rules`: los contadores RAPL (`energy_uj`) solo los leen root y el grupo `energia`
  (CVE-2020-8694). El instalador crea el grupo si no existe y añade `ESTACION_USUARIO` (vale tras volver a iniciar
  sesión). Si un programa (p. ej. Mission Center) instala su propia regla que los deja legibles por todos, el
  comprobador semanal lo avisa. Compruébelo con `ls -l /sys/class/powercap/intel-rapl*/energy_uj`.
- `power-profiles-daemon.service` (si está instalado): se habilita para que el perfil elegido en Caelestia
  (Rendimiento / Equilibrado / Ahorro) se aplique desde el arranque. El paquete lo deja sin habilitar: solo lo arranca
  D-Bus al iniciar sesión y, hasta entonces (pantalla del PIN, gestor de inicio de sesión), rige el perfil por
  defecto del firmware. Si ya estaba habilitado, no se toca ni se deshabilita al desinstalar. Compruébelo con
  `systemctl is-enabled power-profiles-daemon` y `powerprofilesctl`. Más en `guias/perfiles-energia.md`.

### avisos

- `qt6-rebuild-aviso` + hook de pacman: tras actualizar Qt6, imprime qué recompilar y en qué orden (quickshell-git,
  qt6-m3shapes-git, el paquete local `CAELESTIA_PKG` en `CAELESTIA_PKG_DIR` o caelestia-shell de AUR, qtengine).
- `spotify-spicetify-acl` + hook (solo si spotify está instalado): ACL de escritura en `/opt/spotify` solo para
  `ESTACION_USUARIO`, sin abrir permisos a nadie más.
- `estacion-actualizar` (usuario): actualización semanal guiada (noticias de Arch y CachyOS, `.pacnew`, `paru -Syu`
  sin confirmación automática, servicios fallidos, si hay que reiniciar y `checkrebuild` con la orden exacta). Los paquetes
  locales se buscan en `PKG_LOCALES_DIR`. `estacion-aviso-actualizar.timer` solo notifica el viernes.

### escritorio (usuario)

- `estacion-ajuste` (+ enlace `estacion-volumen`): volumen, micrófono y brillo con aceleración al mantener la tecla.
  Ejemplo de atajos de Hyprland: `estacion-ajuste volumen subir`, `estacion-ajuste brillo bajar`.
- `estacion-cerrar-sesion`: fundido a negro (`~/.local/share/estacion/fundido-salida/shell.qml`) y cierre de sesión
  que devuelve siempre a SDDM (con o sin UWSM).
- `estacion-zen-tema` + `.path` (solo si hay perfil de Zen): `userChrome.css` de Zen con los colores del esquema de
  Caelestia, regenerado al cambiar el esquema.
- `estacion-autofirma-nss` + `.path` + envoltura `~/.local/bin/autofirma` (solo si AutoFirma está instalado): hace
  que AutoFirma use el almacén de certificados de Zen o Firefox (`NAVEGADOR=zen|firefox`; por defecto el que tenga
  perfil) mediante `~/.config/estacion/afirma-profiles.ini`, y añade la autoridad local de AutoFirma como de confianza
  en ese almacén (con el navegador cerrado). `~/.local/bin` debe ir antes que `/usr/bin` en el `PATH`.
  Compruébelo con `estacion-autofirma-nss --comprobar`.
- `estacion-comprobar-caelestia` + timer semanal: si hay versión nueva de caelestia-shell, prueba los parches del
  paquete local (`CAELESTIA_PKG_DIR`) y cuenta las cadenas por traducir, sin tocar nada instalado. Comprobaciones
  opcionales y genéricas (`auto | 1 | 0`): reglas de udev ajenas (`COMPROBAR_UDEV`, `UDEV_PERMITIDAS`), foco de
  Hyprland (`COMPROBAR_FOCO`, `FOCO_ESPERADO`), TPM (`COMPROBAR_TPM`: compara el PCR 7 y la versión de la BIOS con
  los guardados en `TPM_ESTADO_DIR` al inscribir), Parsec (`COMPROBAR_PARSEC`) y AutoFirma con caducidad de
  certificados (`COMPROBAR_AUTOFIRMA`). Informe en `~/.local/state/estacion/`.
- `autostart-recarga.path`: recarga el gestor de usuario cuando cambia `~/.config/autostart` (el generador de
  autoarranque XDG crea las unidades al momento).

## sudoers (ejemplo)

`sudoers/estacion-papirus-folders.example` muestra una regla mínima para `papirus-folders`. No se instala: créela
siempre con `sudo visudo -f /etc/sudoers.d/estacion-papirus-folders` y conceda solo esa orden.

## Herramientas (no se instalan)

| Fichero | Uso |
|---|---|
| `puntero.c` | mueve el cursor y hace clic como un ratón real (protocolo wlr-virtual-pointer), sin abrir ventanas. Tamaño de pantalla en `PUNTERO_ANCHO`/`PUNTERO_ALTO` |
| `xdano.c` | cuenta el daño (redibujado) de una ventana XWayland durante N segundos |
| `activacion-x11.py` | ventana X11 que pide su propia activación (para probar `misc:focus_on_activate`) |
| `huerfanos-snapper.sh` | función `huerfanos_snapper CONFIG DIR`: instantáneas huérfanas (distingue el directorio vacío que conserva snapper por `UNIQUE_NUMBERS`) |
| `simular-ajuste.sh` | simula pulsaciones mantenidas para medir `estacion-ajuste` (restaura los valores al terminar) |
| `verificar-arranque.sh` | comprobación de solo lectura tras arrancar desde una instantánea o con el kernel LTS |
| `gpu-por-proceso.sh` | uso de GPU por proceso y motor (i915/xe) sin root |

Compilación de las herramientas en C:

```bash
cd sistema/herramientas
mkdir -p protocolo
# El XML del protocolo no se incluye (tiene otra licencia): descárguelo del proyecto wlr-protocols
#   https://gitlab.freedesktop.org/wlroots/wlr-protocols → unstable/wlr-virtual-pointer-unstable-v1.xml
cp /ruta/a/wlr-virtual-pointer-unstable-v1.xml protocolo/
make            # genera protocolo/vp.h y protocolo/vp.c con wayland-scanner y compila puntero y xdano
```

`make` ejecuta `wayland-scanner client-header` y `wayland-scanner private-code` sobre el XML; los ficheros generados
heredan la licencia del protocolo y no forman parte de este proyecto.

## Licencia

GPL-3.0-or-later (fichero `LICENSE` en la raíz del proyecto).
