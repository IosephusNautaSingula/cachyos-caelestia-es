#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# desinstalar.sh — quita lo que instaló instalar.sh (y solo eso: lo lee de su lista de instalación).
#
# Uso: desinstalar.sh [--prueba] [--usuario] [--solo comp1,comp2] [--purgar] [--conf FICHERO]
#   (sin --usuario)  parte de sistema (lista /var/lib/estacion/instalado.lista). Exige root (salvo --prueba).
#   --usuario        parte de usuario (lista ~/.local/state/estacion/instalado.lista). Nunca como root.
#   --prueba         NO toca nada: imprime cada acción que haría. Funciona sin root.
#   --solo           solo esos componentes (copia, touchpad, bluetooth, red, endurecimiento, energia, avisos, escritorio)
#   --purgar         además borra el estado y la configuración: /etc/estacion (¡incluidos los secretos que creó
#                    usted!), /var/lib/estacion-*, /var/cache/estacion-copia, el grupo energia; o, con --usuario,
#                    ~/.local/state/estacion y ~/.config/estacion. Pide confirmación aparte.
#   --conf FICHERO   se acepta por simetría con instalar.sh (no hace falta).
# Deshabilita y para las unidades, borra los ficheros instalados y, si al instalar se guardó una copia de un fichero
# previo (<fichero>.bak.AAAA-MM-DD-estacion), le dice cómo restaurarla (no lo hace solo). NUNCA borra el repositorio
# de copias (NAS) ni sus datos.
set -euo pipefail
DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/comun.sh
source "$DIR/lib/comun.sh"

PRUEBA=0; USUARIO=0; SOLO=; PURGAR=0
while (( $# )); do
  case $1 in
    --prueba)  PRUEBA=1 ;;
    --usuario) USUARIO=1 ;;
    --purgar)  PURGAR=1 ;;
    --solo)    SOLO=${2:?--solo necesita una lista}; shift ;;
    --solo=*)  SOLO=${1#*=} ;;
    --conf)    shift ;;
    --conf=*)  ;;
    -h|--help|--ayuda) sed -n '3,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) error "opción desconocida: $1"; exit 2 ;;
  esac
  shift
done
seleccionar "$SOLO" || exit 2
TODOS=0; [[ -z $SOLO ]] && TODOS=1

if (( USUARIO )); then
  [[ $EUID -ne 0 ]] || { error "la parte de usuario (--usuario) no se desinstala como root"; exit 1; }
  LISTA=$LISTA_USUARIO; AMBITO=usuario; SC=(systemctl --user)
else
  (( PRUEBA )) || [[ $EUID -eq 0 ]] || { error "la parte de sistema exige root (sudo bash $0 …) o --prueba"; exit 1; }
  LISTA=$LISTA_SISTEMA; AMBITO=sistema; SC=(systemctl)
fi

# Entradas de la lista (tipo|componente|valor) de los componentes elegidos. Sin lista, en --prueba se simula con el
# catálogo completo (como si todo estuviera instalado) para enseñar lo que se haría.
SIMULADA=0
ENTRADAS=()
if [[ -r $LISTA ]]; then
  while IFS= read -r l; do
    [[ -n $l ]] || continue
    IFS='|' read -r _ comp _ <<<"$l"
    seleccionado "$comp" && ENTRADAS+=("$l")
  done < "$LISTA"
elif (( PRUEBA )); then
  SIMULADA=1
  while IFS='|' read -r comp amb _ _ _ destino; do
    [[ $amb == "$AMBITO" ]] && seleccionado "$comp" && ENTRADAS+=("fichero|$comp|$destino")
  done < <(catalogo)
  while IFS='|' read -r comp amb _ u _; do
    [[ $amb == "$AMBITO" ]] && seleccionado "$comp" && ENTRADAS+=("unidad|$comp|$u")
  done < <(unidades)
  if [[ $AMBITO == sistema ]] && seleccionado energia; then ENTRADAS+=("miembro|energia|usuario" "grupo|energia|energia"); fi
fi

QUITADAS=()
desinstalar() {
  local l tipo comp valor quita_initramfs=0 quita_udev=0 quita_resolved=0 quita_nm=0 quita_sysctl=0 quita_unidad=0 b
  QUITADAS=()
  # 1. Unidades: deshabilitar y parar
  for l in "${ENTRADAS[@]}"; do
    IFS='|' read -r tipo comp valor <<<"$l"
    [[ $tipo == unidad ]] || continue
    ejecutar "${SC[*]} disable --now $valor" "${SC[@]}" disable --now "$valor" || aviso "no se pudo deshabilitar $valor"
    QUITADAS+=("$l")
  done
  # 2. Ficheros
  for l in "${ENTRADAS[@]}"; do
    IFS='|' read -r tipo comp valor <<<"$l"
    [[ $tipo == fichero ]] || continue
    if [[ -e $valor || -L $valor ]]; then
      ejecutar "rm -f $valor$( (( SIMULADA )) && echo '   (simulación: solo si constara en la lista)')" rm -f "$valor"
    else
      info "ya no existe: $valor"
    fi
    case $valor in
      */systemd/system/*|*/systemd/user/*) quita_unidad=1 ;;
      /etc/udev/rules.d/*) quita_udev=1 ;;
      /etc/sysctl.d/*) quita_sysctl=1 ;;
      /etc/systemd/resolved.conf.d/*) quita_resolved=1 ;;
      /etc/NetworkManager/conf.d/*) quita_nm=1 ;;
      /etc/mkinitcpio.conf.d/*) quita_initramfs=1 ;;
    esac
    for b in "$valor".bak.*-estacion; do
      [[ -e $b ]] && info "había un fichero previo; si quiere recuperarlo: mv $b $valor"
    done
    QUITADAS+=("$l")
  done
  # 3. Pertenencia al grupo energia (el grupo solo se borra con --purgar)
  for l in "${ENTRADAS[@]}"; do
    IFS='|' read -r tipo comp valor <<<"$l"
    case $tipo in
      miembro) ejecutar "gpasswd -d $valor energia" gpasswd -d "$valor" energia || aviso "no se pudo quitar $valor del grupo energia"
               QUITADAS+=("$l") ;;
      grupo)   QUITADAS+=("$l") ;;
    esac
  done
  # 4. Recargas
  (( quita_unidad )) && ejecutar "${SC[*]} daemon-reload" "${SC[@]}" daemon-reload
  (( quita_udev )) && ejecutar "udevadm control --reload" udevadm control --reload
  (( quita_resolved )) && ejecutar "systemctl try-reload-or-restart systemd-resolved" systemctl try-reload-or-restart systemd-resolved
  (( quita_nm )) && ejecutar "nmcli general reload conf" nmcli general reload conf
  (( quita_sysctl )) && info "los valores de sysctl siguen activos hasta reiniciar (o fíjelos a mano con sysctl -w)"
  (( quita_initramfs )) && regenerar_initramfs
  # 5. Lista de instalación: se quitan las entradas tratadas
  if [[ $MODO == aplicar && -e $LISTA ]]; then
    local resto
    resto=$(grep -vxF -f <(printf '%s\n' "${QUITADAS[@]}") "$LISTA" || true)
    if [[ -n $resto ]]; then printf '%s\n' "$resto" > "$LISTA"; else rm -f "$LISTA"; fi
  fi
  return 0
}

purgar() {
  local d
  titulo "purgar (estado y configuración)"
  if [[ $AMBITO == sistema ]]; then
    if seleccionado copia; then
      for d in /var/lib/estacion-copia /var/cache/estacion-copia; do
        [[ -e $d ]] && ejecutar "rm -rf $d" rm -rf "$d"
      done
    fi
    if seleccionado bluetooth && [[ -e /var/lib/estacion-bluetooth ]]; then ejecutar "rm -rf /var/lib/estacion-bluetooth" rm -rf /var/lib/estacion-bluetooth; fi
    # El grupo solo se borra si lo creó instalar.sh (entrada «grupo» en la lista)
    if seleccionado energia && printf '%s\n' "${ENTRADAS[@]}" | grep -qx 'grupo|energia|energia' && getent group energia >/dev/null; then
      ejecutar "groupdel energia" groupdel energia
    fi
    if (( TODOS )); then
      [[ -e /var/lib/estacion ]] && ejecutar "rm -rf /var/lib/estacion" rm -rf /var/lib/estacion
      if [[ -e /etc/estacion ]]; then
        if [[ $MODO == aplicar ]] && ! preguntar "   ¿Borrar también /etc/estacion, CON los secretos que creó usted (clave de restic, credenciales)?"; then
          info "se conserva /etc/estacion"
        else
          ejecutar "rm -rf /etc/estacion   (pide confirmación aparte)" rm -rf /etc/estacion
        fi
      fi
    else
      info "con --solo no se borra /etc/estacion (es común a todos los componentes)"
    fi
  else
    if (( TODOS )); then
      for d in "$ESTADO_U" "$CONFIG_U"; do [[ -e $d ]] && ejecutar "rm -rf $d" rm -rf "$d"; done
    else
      info "con --solo no se borran $ESTADO_U ni $CONFIG_U"
    fi
  fi
  info "El repositorio de copias (NAS) no se toca nunca."
  return 0
}

ejecutar_todo() {
  titulo "desinstalar (parte de $AMBITO): ${SELECCION[*]}"
  if (( ${#ENTRADAS[@]} == 0 )); then
    info "No hay nada instalado por instalar.sh para estos componentes ($LISTA)."
  else
    desinstalar
  fi
  (( PURGAR )) && purgar
  return 0
}

echo "Estación · desinstalación de la parte de $AMBITO"
if (( PRUEBA )); then
  MODO=prueba
  echo "MODO PRUEBA: no se cambia nada; se muestra cada acción."
  if (( SIMULADA )); then
    echo "No existe $LISTA: instalar.sh no ha instalado nada aquí."
    echo "Para enseñar el procedimiento se simula como si estuviera instalado todo el catálogo:"
  fi
  ejecutar_todo
  echo; echo "Fin de la prueba: no se ha cambiado nada."
  exit 0
fi
if (( ${#ENTRADAS[@]} == 0 && ! PURGAR )); then
  echo "No hay nada instalado por instalar.sh para estos componentes ($LISTA). Nada que hacer."; exit 0
fi
MODO=plan
echo "Plan (todavía no se ha cambiado nada):"
ejecutar_todo
echo
if ! preguntar "¿Aplicar este plan?"; then echo "Cancelado: no se ha cambiado nada."; exit 0; fi
MODO=aplicar
ejecutar_todo
echo; echo "${c_v}Hecho.${c_n}"
