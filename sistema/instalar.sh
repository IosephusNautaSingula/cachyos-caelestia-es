#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# instalar.sh — instala los componentes de Estación (scripts, unidades de systemd, reglas y ajustes del sistema).
#
# Uso: instalar.sh [--prueba] [--usuario] [--solo comp1,comp2] [--conf FICHERO]
#   (sin --usuario)  parte de sistema: /usr/local/bin, /etc/systemd/system, /etc/udev… Exige root (salvo --prueba).
#   --usuario        parte de usuario: ~/.local/bin, ~/.config/systemd/user… Nunca como root.
#   --prueba         NO toca nada (ni directorios, ni systemctl, ni temporales): imprime cada acción que haría.
#                    Funciona sin root; si no hay /etc/estacion/estacion.conf, usa estacion.conf.example.
#   --solo           solo esos componentes: copia, touchpad, bluetooth, red, endurecimiento, energia, avisos, escritorio
#   --conf FICHERO   configuración a usar (en la parte de sistema se instala como /etc/estacion/estacion.conf)
#
# Antes de sobrescribir un fichero existente se copia a <fichero>.bak.AAAA-MM-DD-estacion. Antes de aplicar se
# muestra el plan completo y se pide confirmación. Lo instalado se anota en una lista (/var/lib/estacion/instalado.lista
# o ~/.local/state/estacion/instalado.lista) que usa desinstalar.sh. Este instalador NUNCA crea secretos.
set -euo pipefail
DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/comun.sh
source "$DIR/lib/comun.sh"

PRUEBA=0; USUARIO=0; SOLO=; CONF_OPCION=
while (( $# )); do
  case $1 in
    --prueba)  PRUEBA=1 ;;
    --usuario) USUARIO=1 ;;
    --solo)    SOLO=${2:?--solo necesita una lista}; shift ;;
    --solo=*)  SOLO=${1#*=} ;;
    --conf)    CONF_OPCION=${2:?--conf necesita un fichero}; shift ;;
    --conf=*)  CONF_OPCION=${1#*=} ;;
    -h|--help|--ayuda) sed -n '3,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) error "opción desconocida: $1"; exit 2 ;;
  esac
  shift
done
seleccionar "$SOLO" || exit 2

if (( USUARIO )); then
  [[ $EUID -ne 0 ]] || { error "la parte de usuario (--usuario) no se instala como root: ejecútelo con su usuario"; exit 1; }
else
  (( PRUEBA )) || [[ $EUID -eq 0 ]] || { error "la parte de sistema exige root (sudo bash $0 …) o --prueba"; exit 1; }
fi

# --- Configuración ----------------------------------------------------------------------------------------------
CONF_USADA=
if [[ -n $CONF_OPCION ]]; then
  [[ -r $CONF_OPCION ]] || { error "no se puede leer $CONF_OPCION"; exit 1; }
  CONF_USADA=$CONF_OPCION
elif (( USUARIO )) && [[ -r $CONFIG_U/estacion.conf ]]; then
  CONF_USADA=$CONFIG_U/estacion.conf
elif [[ -r $CONF_SISTEMA ]]; then
  CONF_USADA=$CONF_SISTEMA
else
  CONF_USADA=$DIR/estacion.conf.example
fi
if [[ -n $CONF_OPCION || $CONF_USADA == "$DIR/estacion.conf.example" ]]; then leer_conf "$CONF_USADA" confiar
else leer_conf "$CONF_USADA" || exit 1; fi
(( USUARIO )) && [[ $CONF_USADA != "$CONF_SISTEMA" ]] && { leer_conf "$CONF_SISTEMA" || true; }
leer_conf "$DIR/estacion.conf.example" confiar   # valores por defecto de lo que no esté definido
EJEMPLO=0; [[ $CONF_USADA == "$DIR/estacion.conf.example" ]] && EJEMPLO=1

if (( USUARIO )); then LISTA=$LISTA_USUARIO; AMBITO=usuario; else LISTA=$LISTA_SISTEMA; AMBITO=sistema; fi

# --- Acciones -------------------------------------------------------------------------------------------------------
UNIDADES_A_HABILITAR=()
CAMBIO_INITRAMFS=0; CAMBIO_UDEV=0; CAMBIO_SYSCTL=0; CAMBIO_RESOLVED=0; CAMBIO_NM=0; CAMBIO_UNIDADES=0

registrar() {   # registrar tipo componente valor → línea en la lista de lo instalado
  [[ $MODO == aplicar ]] || return 0
  local linea="$1|$2|$3"
  install -d -m 0755 "$(dirname "$LISTA")"
  grep -qxF "$linea" "$LISTA" 2>/dev/null || echo "$linea" >> "$LISTA"
}

# Instala un fichero del catálogo; devuelve 0 si cambia algo y 1 si ya estaba igual
instalar_fichero() {
  local comp=$1 modo=$2 origen=$3 destino=$4
  if [[ $modo == enlace ]]; then
    if [[ -L $destino && $(readlink "$destino") == "$origen" ]]; then
      info "sin cambios: $destino → $origen"; registrar fichero "$comp" "$destino"; return 1
    fi
    if [[ -e $destino || -L $destino ]] && [[ ! -e $destino$SUFIJO_BAK ]]; then
      ejecutar "cp -a $destino $destino$SUFIJO_BAK" cp -a "$destino" "$destino$SUFIJO_BAK"
    fi
    ejecutar "ln -sfn $origen → $destino" ln -sfn "$origen" "$destino"
    registrar fichero "$comp" "$destino"; return 0
  fi
  local src=$DIR/$origen
  [[ -r $src ]] || { error "falta $src en el paquete"; return 1; }
  if [[ -f $destino && ! -L $destino ]] && cmp -s "$src" "$destino" && [[ $(stat -c %a "$destino") == "$modo" ]]; then
    info "sin cambios: $destino"; registrar fichero "$comp" "$destino"; return 1
  fi
  if [[ -e $destino || -L $destino ]] && [[ ! -e $destino$SUFIJO_BAK ]]; then
    ejecutar "cp -a $destino $destino$SUFIJO_BAK   (copia de lo que había)" cp -a "$destino" "$destino$SUFIJO_BAK"
  fi
  ejecutar "install -D -m $modo $origen → $destino" install -D -m "$modo" "$src" "$destino"
  registrar fichero "$comp" "$destino"
  return 0
}

# Instala los ficheros del catálogo de un componente en el ámbito actual
instalar_componente() {
  local comp=$1 c amb cond modo origen destino
  while IFS='|' read -r c amb cond modo origen destino; do
    [[ $c == "$comp" && $amb == "$AMBITO" ]] || continue
    if ! condicion_cumplida "$cond"; then info "omitido: $destino ($(motivo_condicion "$cond"))"; continue; fi
    if instalar_fichero "$comp" "$modo" "$origen" "$destino"; then
      case $destino in
        */systemd/system/*|*/systemd/user/*) CAMBIO_UNIDADES=1 ;;
        /etc/udev/rules.d/*) CAMBIO_UDEV=1 ;;
        /etc/sysctl.d/*) CAMBIO_SYSCTL=1 ;;
        /etc/systemd/resolved.conf.d/*) CAMBIO_RESOLVED=1 ;;
        /etc/NetworkManager/conf.d/*) CAMBIO_NM=1 ;;
        /etc/mkinitcpio.conf.d/*) CAMBIO_INITRAMFS=1 ;;
      esac
    fi
  done < <(catalogo)
  local u ya
  while IFS='|' read -r c amb cond u ya; do
    [[ $c == "$comp" && $amb == "$AMBITO" ]] || continue
    condicion_cumplida "$cond" || continue
    UNIDADES_A_HABILITAR+=("$comp|$u|$ya")
  done < <(unidades)
}

# --- Componentes: parte de sistema ------------------------------------------------------------------------------
sistema_copia() {
  local falta=() secretos_ok=1 f
  command -v restic >/dev/null || falta+=(restic)
  [[ $COPIA_MODO == smb ]] && ! command -v mount.cifs >/dev/null && falta+=(cifs-utils)
  if (( ${#falta[@]} )); then
    aviso "faltan paquetes: ${falta[*]}. Instálelos (sudo pacman -S ${falta[*]}) y repita; no se instala la copia."
    return 0
  fi
  command -v snapper >/dev/null || info "snapper no está instalado: /home se copiará en vivo (sin instantánea)"
  local secretos=("$COPIA_CLAVE_RESTIC"); [[ $COPIA_MODO == smb ]] && secretos+=("$COPIA_CREDENCIALES")
  for f in "${secretos[@]}"; do
    if [[ ! -s $f ]]; then secretos_ok=0; aviso "falta el secreto $f"
    elif [[ $(stat -c '%u %a' "$f") != "0 600" ]]; then secretos_ok=0; aviso "$f debe ser de root con permisos 0600 (sudo chown root:root $f && sudo chmod 0600 $f)"
    fi
  done
  if (( ! secretos_ok )); then
    info "Este instalador NUNCA crea secretos. Créelos usted (cada orden lee de la terminal; termine con Intro y Ctrl+D):"
    info "  sudo install -d -m 0755 /etc/estacion"
    info "  sudo sh -c 'umask 077; cat > $COPIA_CLAVE_RESTIC'        # contraseña del repositorio restic"
    [[ $COPIA_MODO == smb ]] && info "  sudo sh -c 'umask 077; cat > $COPIA_CREDENCIALES'   # dos líneas: username=… y password=…"
    info "  Guarde también la contraseña del repositorio en su gestor de contraseñas: sin ella la copia no se puede leer."
    info "  Si el repositorio aún no existe, después de instalar: sudo estacion-copia restic init"
    if [[ $MODO == aplicar ]]; then aviso "no se instala la copia hasta que existan los secretos."; return 0; fi
    info "(en la prueba se muestra igualmente lo que se instalaría una vez creados)"
  fi
  instalar_componente copia
  if [[ -e $COPIA_EXCLUIR ]]; then info "sin cambios: $COPIA_EXCLUIR (ya existe; no se toca)"
  else ejecutar "install -D -m 644 excluir.txt.example → $COPIA_EXCLUIR" install -D -m 644 "$DIR/excluir.txt.example" "$COPIA_EXCLUIR"; fi
  if [[ ! -e /var/lib/estacion-copia/instalado ]]; then
    ejecutar "install -d -m 755 /var/lib/estacion-copia && date +%s > /var/lib/estacion-copia/instalado" \
      bash -c 'install -d -m 0755 /var/lib/estacion-copia && date +%s > /var/lib/estacion-copia/instalado && chmod 0644 /var/lib/estacion-copia/instalado'
  fi
}

sistema_touchpad() {
  if hay_touchpad; then info "detectado: touchpad ACPI ${TOUCHPAD_HID}"
  else info "no se detecta el touchpad ${TOUCHPAD_HID:-(TOUCHPAD_HID vacío)}: este componente no se instala"; return 0; fi
  if es_tigerlake; then info "detectado: controlador de pines pinctrl_tigerlake (se añaden los módulos al initramfs)"
  else aviso "el controlador de pines no es pinctrl_tigerlake: NO se aplica 20-estacion-touchpad.conf (vea el README para adaptarlo)"; fi
  instalar_componente touchpad
}

sistema_bluetooth() {
  instalar_componente bluetooth
  if [[ -r /etc/bluetooth/main.conf ]] && ! grep -qE '^[[:space:]]*AutoEnable[[:space:]]*=[[:space:]]*false' /etc/bluetooth/main.conf; then
    info "Recomendado (no lo cambia este instalador): en /etc/bluetooth/main.conf, sección [Policy], AutoEnable=false"
    info "para que el estado lo decida estacion-bluetooth-recordar y no se encienda solo al arrancar."
  fi
}

sistema_red() {
  instalar_componente red
  condicion_cumplida ufw || aviso "sin ufw no se instala el cortafuegos de casa (sudo pacman -S ufw)"
  if [[ $CASA_CONEXION_UUID == 11111111-2222-3333-4444-555555555555 || $CASA_ROUTER_MAC == 00:00:5e:00:53:* ]]; then
    aviso "CASA_CONEXION_UUID / CASA_ROUTER_MAC tienen los valores de ejemplo: el cortafuegos de casa no se activará hasta que ponga los suyos."
  fi
}

sistema_energia() {
  instalar_componente energia
  if getent group energia >/dev/null; then info "sin cambios: el grupo energia ya existe"
  else ejecutar "groupadd --system energia" groupadd --system energia; registrar grupo energia energia; fi
  if [[ -n $ESTACION_USUARIO ]] && id "$ESTACION_USUARIO" >/dev/null 2>&1; then
    if id -nG "$ESTACION_USUARIO" 2>/dev/null | grep -qw energia; then info "sin cambios: $ESTACION_USUARIO ya está en el grupo energia"
    else ejecutar "gpasswd -a $ESTACION_USUARIO energia   (vale tras volver a iniciar sesión)" gpasswd -a "$ESTACION_USUARIO" energia
         registrar miembro energia "$ESTACION_USUARIO"; fi
  else
    aviso "ESTACION_USUARIO («$ESTACION_USUARIO») no existe en este equipo: añada usted su usuario al grupo energia"
  fi
}

sistema_avisos() {
  instalar_componente avisos
  [[ -z $CAELESTIA_PKG_DIR ]] && info "CAELESTIA_PKG_DIR vacío: qt6-rebuild-aviso no podrá dar la orden exacta del paquete local"
  return 0
}

instalar_sistema() {
  local comp
  if [[ $CONF_USADA != "$CONF_SISTEMA" ]] && (( ! EJEMPLO || ! PRUEBA )); then
    titulo "configuración"
    if [[ -e $CONF_SISTEMA ]] && cmp -s "$CONF_USADA" "$CONF_SISTEMA"; then info "sin cambios: $CONF_SISTEMA"
    else
      [[ -e $CONF_SISTEMA && ! -e $CONF_SISTEMA$SUFIJO_BAK ]] && ejecutar "cp -a $CONF_SISTEMA $CONF_SISTEMA$SUFIJO_BAK" cp -a "$CONF_SISTEMA" "$CONF_SISTEMA$SUFIJO_BAK"
      ejecutar "install -D -m 644 ${CONF_USADA#"$DIR"/} → $CONF_SISTEMA" install -D -m 644 "$CONF_USADA" "$CONF_SISTEMA"
      (( EJEMPLO )) && aviso "se instala la configuración de EJEMPLO: revise $CONF_SISTEMA y ponga sus valores"
    fi
  elif (( EJEMPLO )); then
    titulo "configuración"
    info "no existe $CONF_SISTEMA: en la prueba se usa estacion.conf.example (al aplicar se instalaría como $CONF_SISTEMA)"
  fi
  for comp in "${SELECCION[@]}"; do
    titulo "componente $comp (sistema)"
    case $comp in
      copia) sistema_copia ;;
      touchpad) sistema_touchpad ;;
      bluetooth) sistema_bluetooth ;;
      red) sistema_red ;;
      endurecimiento) instalar_componente endurecimiento ;;
      energia) sistema_energia ;;
      avisos) sistema_avisos ;;
      escritorio) info "sin parte de sistema (instálelo con --usuario)" ;;
    esac
  done
  titulo "activación (sistema)"
  local hecho=0
  (( CAMBIO_UNIDADES )) && { ejecutar "systemctl daemon-reload" systemctl daemon-reload; hecho=1; }
  if (( CAMBIO_UDEV )); then
    ejecutar "udevadm control --reload" udevadm control --reload
    seleccionado energia && ejecutar "udevadm trigger --subsystem-match=powercap --action=change" udevadm trigger --subsystem-match=powercap --action=change
    hecho=1
  fi
  (( CAMBIO_SYSCTL )) && { ejecutar "sysctl --load=/etc/sysctl.d/90-estacion.conf" sysctl -q --load=/etc/sysctl.d/90-estacion.conf; hecho=1; }
  (( CAMBIO_RESOLVED )) && { ejecutar "systemctl try-reload-or-restart systemd-resolved" systemctl try-reload-or-restart systemd-resolved; hecho=1; }
  (( CAMBIO_NM )) && { ejecutar "nmcli general reload conf" nmcli general reload conf; hecho=1; }
  local e comp_u u ya
  for e in "${UNIDADES_A_HABILITAR[@]}"; do
    IFS='|' read -r comp_u u ya <<<"$e"
    if [[ $ya == 1 ]]; then ejecutar "systemctl enable --now $u" systemctl enable --now "$u"
    else ejecutar "systemctl enable $u" systemctl enable "$u"; fi
    registrar unidad "$comp_u" "$u"; hecho=1
  done
  (( CAMBIO_INITRAMFS )) && { regenerar_initramfs; hecho=1; }
  (( hecho )) || info "nada que activar"
}

# --- Parte de usuario -----------------------------------------------------------------------------------------------
instalar_usuario() {
  local comp
  for comp in "${SELECCION[@]}"; do
    titulo "componente $comp (usuario)"
    case $comp in
      touchpad|red|endurecimiento|energia) info "sin parte de usuario (instálelo sin --usuario, como root)" ;;
      *) instalar_componente "$comp" ;;
    esac
  done
  titulo "activación (usuario)"
  local hecho=0 e comp_u u ya
  (( CAMBIO_UNIDADES )) && { ejecutar "systemctl --user daemon-reload" systemctl --user daemon-reload; hecho=1; }
  for e in "${UNIDADES_A_HABILITAR[@]}"; do
    IFS='|' read -r comp_u u ya <<<"$e"
    if [[ $ya == 1 ]]; then ejecutar "systemctl --user enable --now $u" systemctl --user enable --now "$u"
    else ejecutar "systemctl --user enable $u" systemctl --user enable "$u"; fi
    registrar unidad "$comp_u" "$u"; hecho=1
  done
  (( hecho )) || info "nada que activar"
  case ":$PATH:" in *":$BIN_U:"*) ;; *) aviso "$BIN_U no está en el PATH: añádalo para usar las órdenes estacion-*" ;; esac
  if seleccionado escritorio && condicion_cumplida autofirma; then
    local p1 p2
    p1=$(tr ':' '\n' <<<"$PATH" | grep -nxF "$BIN_U" | head -1 | cut -d: -f1)
    p2=$(tr ':' '\n' <<<"$PATH" | grep -nxF /usr/bin | head -1 | cut -d: -f1)
    [[ -n $p1 && -n $p2 ]] && (( p1 > p2 )) && aviso "$BIN_U va detrás de /usr/bin en el PATH: la envoltura de AutoFirma no se usará"
    info "AutoFirma: tras abrirlo una vez, ejecute estacion-autofirma-nss con el navegador cerrado."
  fi
  return 0
}

ejecutar_todo() { if (( USUARIO )); then instalar_usuario; else instalar_sistema; fi; }

# --- Programa principal ---------------------------------------------------------------------------------------------
echo "Estación · instalación de la parte de $AMBITO · componentes: ${SELECCION[*]}"
echo "Configuración: $CONF_USADA$( (( EJEMPLO )) && echo ' (ejemplo)')"
if (( PRUEBA )); then
  MODO=prueba
  echo "MODO PRUEBA: no se cambia nada; se muestra cada acción."
  ejecutar_todo
  echo; echo "Fin de la prueba: no se ha cambiado nada."
  exit 0
fi

MODO=plan
echo "Plan (todavía no se ha cambiado nada):"
ejecutar_todo
echo
if ! preguntar "¿Aplicar este plan?"; then echo "Cancelado: no se ha cambiado nada."; exit 0; fi
MODO=aplicar
UNIDADES_A_HABILITAR=(); CAMBIO_INITRAMFS=0; CAMBIO_UDEV=0; CAMBIO_SYSCTL=0; CAMBIO_RESOLVED=0; CAMBIO_NM=0; CAMBIO_UNIDADES=0
ejecutar_todo
echo; echo "${c_v}Hecho.${c_n} Lo instalado consta en $LISTA (lo usa desinstalar.sh)."
