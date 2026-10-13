# SPDX-License-Identifier: GPL-3.0-or-later
# Funciones y catálogo comunes de instalar.sh y desinstalar.sh (se carga con «source»; no se ejecuta solo).

COMPONENTES=(copia touchpad bluetooth red endurecimiento energia avisos escritorio)
CONF_SISTEMA=/etc/estacion/estacion.conf
LISTA_SISTEMA=/var/lib/estacion/instalado.lista
SUFIJO_BAK=".bak.$(date +%F)-estacion"

# Modo de trabajo: prueba (solo imprime, --prueba), plan (solo imprime, antes de confirmar) o aplicar.
MODO=${MODO:-prueba}

# --- Mensajes -------------------------------------------------------------------------------------------------------
if [[ -t 1 ]]; then c_t=$'\e[1m'; c_a=$'\e[1;33m'; c_r=$'\e[1;31m'; c_v=$'\e[1;32m'; c_n=$'\e[0m'
else c_t=; c_a=; c_r=; c_v=; c_n=; fi
titulo() { echo; echo "${c_t}== $* ==${c_n}"; }
info()   { echo "   $*"; }
aviso()  { echo "   ${c_a}AVISO:${c_n} $*"; }
error()  { echo "${c_r}ERROR:${c_n} $*" >&2; }
preguntar() { local r; read -r -p "$1 [s/N] " r; [[ $r =~ ^[sS]$ ]]; }

# Imprime la orden (en prueba y plan) o la ejecuta (en aplicar). Uso: ejecutar "texto legible" orden args...
ejecutar() {
  local texto=$1; shift
  case $MODO in
    prueba) echo "   [prueba] $texto" ;;
    plan)   echo "   [plan]   $texto" ;;
    aplicar) echo "   → $texto"; "$@" ;;
  esac
}

# --- Configuración --------------------------------------------------------------------------------------------------
# Lee VAR=valor de un fichero sin ejecutarlo; no pisa variables ya definidas (manda el entorno). Solo acepta ficheros
# de root o del propio usuario que no puedan escribir otros, salvo con un segundo argumento «confiar» (el ejemplo que
# acompaña a este instalador o el fichero que usted pasa con --conf).
leer_conf() {
  local f=$1 confiar=${2:-} linea k v
  [[ -r $f ]] || return 0
  read -r k v < <(stat -c '%u %a' "$f")
  if [[ $confiar != confiar ]] && { [[ $k != 0 && $k != "$EUID" ]] || (( 8#$v & 8#022 )); }; then
    error "$f no es de root ni suyo, o lo pueden escribir otros: no se usa"; return 1
  fi
  while IFS= read -r linea || [[ -n $linea ]]; do
    [[ $linea =~ ^[[:space:]]*([A-Z][A-Z0-9_]*)=(.*)$ ]] || continue
    k=${BASH_REMATCH[1]}; v=${BASH_REMATCH[2]}
    case $v in
      \"*) v=${v#\"}; v=${v%%\"*} ;;
      \'*) v=${v#\'}; v=${v%%\'*} ;;
      *)   v=${v%%[[:space:]#]*} ;;
    esac
    [[ -v $k ]] || printf -v "$k" '%s' "$v"
  done < "$f"
}

# --- Opciones comunes -----------------------------------------------------------------------------------------------
# Comprueba la lista de --solo y la deja en SELECCION (array)
seleccionar() {
  local lista=$1 c ok
  SELECCION=()
  if [[ -z $lista ]]; then SELECCION=("${COMPONENTES[@]}"); return 0; fi
  IFS=, read -r -a pedidos <<<"$lista"
  for c in "${pedidos[@]}"; do
    ok=
    for k in "${COMPONENTES[@]}"; do [[ $c == "$k" ]] && ok=1; done
    [[ -n $ok ]] || { error "componente desconocido: «$c». Válidos: ${COMPONENTES[*]}"; return 1; }
    SELECCION+=("$c")
  done
}
seleccionado() { local c; for c in "${SELECCION[@]}"; do [[ $c == "$1" ]] && return 0; done; return 1; }

# --- Rutas de usuario -----------------------------------------------------------------------------------------------
BIN_U="$HOME/.local/bin"
UNI_U="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
DATA_U="${XDG_DATA_HOME:-$HOME/.local/share}"
ESTADO_U="${XDG_STATE_HOME:-$HOME/.local/state}/estacion"
CONFIG_U="${XDG_CONFIG_HOME:-$HOME/.config}/estacion"
LISTA_USUARIO="$ESTADO_U/instalado.lista"

# --- Catálogo -------------------------------------------------------------------------------------------------------
# Ficheros: «componente|ámbito|condición|modo|origen (relativo a sistema/)|destino». modo «enlace»: origen = destino
# del enlace simbólico. condición vacía = siempre; si no, la evalúa condicion_cumplida.
catalogo() {
  local S=/etc/systemd/system B=/usr/local/bin
  cat <<EOF
copia|sistema||755|bin/estacion-copia|$B/estacion-copia
copia|sistema||755|bin/estacion-copia-aviso|$B/estacion-copia-aviso
copia|sistema||644|systemd/system/estacion-copia.service|$S/estacion-copia.service
copia|sistema||644|systemd/system/estacion-copia.timer|$S/estacion-copia.timer
copia|sistema||644|systemd/system/estacion-copia-mantener.service|$S/estacion-copia-mantener.service
copia|sistema||644|systemd/system/estacion-copia-mantener.timer|$S/estacion-copia-mantener.timer
copia|sistema||644|systemd/system/estacion-copia-cargador.service|$S/estacion-copia-cargador.service
copia|sistema||644|systemd/system/estacion-copia-aviso@.service|$S/estacion-copia-aviso@.service
copia|sistema||644|udev/90-estacion-copia-cargador.rules|/etc/udev/rules.d/90-estacion-copia-cargador.rules
touchpad|sistema|touchpad|755|bin/estacion-touchpad|$B/estacion-touchpad
touchpad|sistema|touchpad|644|systemd/system/estacion-touchpad.service|$S/estacion-touchpad.service
touchpad|sistema|touchpad|755|sleep/estacion-touchpad|/usr/lib/systemd/system-sleep/estacion-touchpad
touchpad|sistema|tigerlake|644|mkinitcpio/20-estacion-touchpad.conf|/etc/mkinitcpio.conf.d/20-estacion-touchpad.conf
bluetooth|sistema||755|bin/estacion-bluetooth-recordar|$B/estacion-bluetooth-recordar
bluetooth|sistema||644|systemd/system/estacion-bluetooth-recordar.service|$S/estacion-bluetooth-recordar.service
red|sistema|ufw|755|networkmanager/90-estacion-cortafuegos-casa|/etc/NetworkManager/dispatcher.d/90-estacion-cortafuegos-casa
red|sistema||644|networkmanager/90-estacion-mac.conf|/etc/NetworkManager/conf.d/90-estacion-mac.conf
red|sistema||644|resolved/91-estacion-dot.conf|/etc/systemd/resolved.conf.d/91-estacion-dot.conf
endurecimiento|sistema||644|sysctl/90-estacion.conf|/etc/sysctl.d/90-estacion.conf
endurecimiento|sistema||644|resolved/90-estacion.conf|/etc/systemd/resolved.conf.d/90-estacion.conf
energia|sistema||644|udev/90-estacion-powercap.rules|/etc/udev/rules.d/90-estacion-powercap.rules
avisos|sistema||755|bin/qt6-rebuild-aviso|$B/qt6-rebuild-aviso
avisos|sistema||644|pacman-hooks/qt6-rebuild-aviso.hook|/etc/pacman.d/hooks/qt6-rebuild-aviso.hook
avisos|sistema|spotify|755|bin/spotify-spicetify-acl|$B/spotify-spicetify-acl
avisos|sistema|spotify|644|pacman-hooks/spotify-spicetify.hook|/etc/pacman.d/hooks/spotify-spicetify.hook
copia|usuario||755|bin/estacion-copia-vigilar|$BIN_U/estacion-copia-vigilar
copia|usuario||644|systemd/user/estacion-copia-vigilar.service|$UNI_U/estacion-copia-vigilar.service
copia|usuario||644|systemd/user/estacion-copia-vigilar.timer|$UNI_U/estacion-copia-vigilar.timer
bluetooth|usuario||755|bin/estacion-bluetooth-reconectar|$BIN_U/estacion-bluetooth-reconectar
bluetooth|usuario||644|systemd/user/estacion-bluetooth-reconectar.service|$UNI_U/estacion-bluetooth-reconectar.service
avisos|usuario||755|bin/estacion-actualizar|$BIN_U/estacion-actualizar
avisos|usuario||644|systemd/user/estacion-aviso-actualizar.service|$UNI_U/estacion-aviso-actualizar.service
avisos|usuario||644|systemd/user/estacion-aviso-actualizar.timer|$UNI_U/estacion-aviso-actualizar.timer
escritorio|usuario||755|bin/estacion-ajuste|$BIN_U/estacion-ajuste
escritorio|usuario||enlace|estacion-ajuste|$BIN_U/estacion-volumen
escritorio|usuario||755|bin/estacion-cerrar-sesion|$BIN_U/estacion-cerrar-sesion
escritorio|usuario||644|share/fundido-salida/shell.qml|$DATA_U/estacion/fundido-salida/shell.qml
escritorio|usuario|zen|755|bin/estacion-zen-tema|$BIN_U/estacion-zen-tema
escritorio|usuario|zen|644|systemd/user/estacion-zen-tema.path|$UNI_U/estacion-zen-tema.path
escritorio|usuario|zen|644|systemd/user/estacion-zen-tema.service|$UNI_U/estacion-zen-tema.service
escritorio|usuario|autofirma|755|bin/estacion-autofirma-nss|$BIN_U/estacion-autofirma-nss
escritorio|usuario|autofirma|755|bin/autofirma|$BIN_U/autofirma
escritorio|usuario|autofirma|644|systemd/user/estacion-autofirma-nss.path|$UNI_U/estacion-autofirma-nss.path
escritorio|usuario|autofirma|644|systemd/user/estacion-autofirma-nss.service|$UNI_U/estacion-autofirma-nss.service
escritorio|usuario||755|bin/estacion-comprobar-caelestia|$BIN_U/estacion-comprobar-caelestia
escritorio|usuario||644|systemd/user/estacion-comprobar-caelestia.service|$UNI_U/estacion-comprobar-caelestia.service
escritorio|usuario||644|systemd/user/estacion-comprobar-caelestia.timer|$UNI_U/estacion-comprobar-caelestia.timer
escritorio|usuario||644|systemd/user/autostart-recarga.path|$UNI_U/autostart-recarga.path
escritorio|usuario||644|systemd/user/autostart-recarga.service|$UNI_U/autostart-recarga.service
EOF
}

# Unidades que se habilitan: «componente|ámbito|condición|unidad|arrancar ya (1/0)»
unidades() {
  cat <<'EOF'
copia|sistema||estacion-copia.timer|1
copia|sistema||estacion-copia-mantener.timer|1
touchpad|sistema|touchpad|estacion-touchpad.service|0
bluetooth|sistema||estacion-bluetooth-recordar.service|0
copia|usuario||estacion-copia-vigilar.timer|1
bluetooth|usuario||estacion-bluetooth-reconectar.service|0
avisos|usuario||estacion-aviso-actualizar.timer|1
escritorio|usuario|zen|estacion-zen-tema.path|1
escritorio|usuario|autofirma|estacion-autofirma-nss.path|1
escritorio|usuario||estacion-comprobar-caelestia.timer|1
escritorio|usuario||autostart-recarga.path|1
EOF
}

# --- Detección ------------------------------------------------------------------------------------------------------
hay_touchpad() { [[ -n ${TOUCHPAD_HID:-} ]] && compgen -G "/sys/bus/acpi/devices/${TOUCHPAD_HID}:*" >/dev/null; }
# Controlador de pines Intel Tiger Lake: módulo cargado (lsmod) o dispositivo con su modalias ACPI (INT34C5/INT34C6)
es_tigerlake() {
  lsmod 2>/dev/null | grep -q '^pinctrl_tigerlake ' && return 0
  [[ -d /sys/module/pinctrl_tigerlake ]] && return 0
  grep -qsE 'acpi:INT34C[56]:' /sys/bus/platform/devices/*/modalias
}
condicion_cumplida() {
  case $1 in
    '') return 0 ;;
    touchpad)  hay_touchpad ;;
    tigerlake) hay_touchpad && es_tigerlake ;;
    spotify)   pacman -Qq spotify >/dev/null 2>&1 || [[ -d ${SPOTIFY_DIR:-/opt/spotify} ]] ;;
    ufw)       command -v ufw >/dev/null ;;
    zen)       [[ -r ${ZEN_DIR:-$HOME/.config/zen}/profiles.ini ]] ;;
    autofirma) [[ -x /usr/bin/autofirma ]] ;;
    *) return 1 ;;
  esac
}
motivo_condicion() {
  case $1 in
    touchpad)  echo "no hay dispositivo ACPI ${TOUCHPAD_HID:-(TOUCHPAD_HID vacío)}:* en /sys/bus/acpi/devices" ;;
    tigerlake) if hay_touchpad; then echo "el controlador de pines no es pinctrl_tigerlake: los módulos del initramfs no se aplican"
               else echo "no hay touchpad ${TOUCHPAD_HID:-} que necesite los módulos"; fi ;;
    spotify)   echo "spotify no está instalado" ;;
    ufw)       echo "ufw no está instalado (el cortafuegos de casa lo necesita)" ;;
    zen)       echo "no hay perfil de Zen (${ZEN_DIR:-$HOME/.config/zen}/profiles.ini)" ;;
    autofirma) echo "AutoFirma no está instalado (/usr/bin/autofirma)" ;;
  esac
}

# Orden para regenerar el initramfs: limine-mkinitcpio si existe (Limine con CachyOS), si no mkinitcpio -P
orden_initramfs() { if command -v limine-mkinitcpio >/dev/null; then echo limine-mkinitcpio; else echo "mkinitcpio -P"; fi; }
regenerar_initramfs() {
  local orden; orden=$(orden_initramfs)
  if [[ $MODO != aplicar ]]; then ejecutar "$orden   (pediría confirmación antes)" true; return 0; fi
  if preguntar "   Hay que regenerar el initramfs con «$orden». ¿Hacerlo ahora?"; then
    # shellcheck disable=SC2086
    ejecutar "$orden" $orden || aviso "«$orden» ha fallado: revíselo antes de reiniciar"
  else
    aviso "No se ha regenerado: hágalo usted antes de reiniciar con: sudo $orden"
  fi
}
