#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# cifrado-live.sh — CIFRADO EN EL SITIO de la raíz y /home (btrfs → LUKS2) desde el entorno live de CachyOS/Arch.
# Se ejecuta desde el USB (o desde la copia de la ESP, plan B), nunca desde el sistema instalado.
#
# Cada partición, según su estado: en claro → btrfs check, reducir, cifrar (cryptsetup reencrypt --encrypt);
# a medio cifrar → repair y reanudar; cifrada → nada. Después: abrir (TRIM guardado en la cabecera), crecer el btrfs y
# scrub. Al final, en chroot: fichero de clave de /home, crypttab, crypttab.initramfs, sd-encrypt, rd.luks.name y
# entradas de Limine.
# ORDEN: primero la raíz (más pequeña y reconstruible desde la copia: el procedimiento se estrena con lo menos valioso;
# además guarda el fichero de clave de /home y hace falta abierta para el chroot), después /home.
# Sin -e a propósito: cada paso comprueba su código y se para con instrucciones.
set -uo pipefail
# shellcheck source=cifrado-comun.sh
source "$(cd "$(dirname "$0")" && pwd)/cifrado-comun.sh"

ayuda() {
  cat <<EOF
cifrado-live.sh — cifra EN EL SITIO la raíz y /home (LUKS2) desde el entorno live. Lea README.md y la guía
$GUIA antes de usarlo.

  sudo bash $0 --prueba
      Lo comprueba todo (entorno live, cargador, disco, serie, PARTUUID, tamaños, que nada esté montado, estado de
      cada partición) y NO escribe nada en el disco (solo su registro). HÁGALO PRIMERO.

  sudo bash $0 --ejecutar --acepto-perdida-de-datos
      CIFRA: raíz → /home → arranque, con pausas. Pide confirmación tecleada (el nombre del disco) y la frase.

  sudo bash $0 --reanudar --ejecutar --acepto-perdida-de-datos
      Lo mismo tras un corte o un error (es lo que hace cifrado-reanudar.sh).

Sin argumentos: muestra esta ayuda y sale.
EOF
}

leer_opciones "$@"
MODO=
for a in "${OTRAS[@]}"; do
  case $a in
    --prueba) MODO=prueba;;
    --reanudar) MODO=reanudar;;
    *) echo "Opción desconocida: $a" >&2; ayuda; exit 2;;
  esac
done
if [[ -n $AYUDA || ( -z $MODO && -z $EJECUTAR && -z $ACEPTO ) ]]; then ayuda; exit 0; fi
if [[ $MODO == prueba ]]; then
  [[ -z $EJECUTAR && -z $ACEPTO ]] || { echo "--prueba no se combina con --ejecutar ni --acepto-perdida-de-datos." >&2; exit 2; }
else
  exigir_banderas
  MODO=${MODO:-cifrar}
fi
exigir_root
exec </dev/null

# Que nada suspenda, apague ni duerma el equipo mientras trabaja (tapa, inactividad, botón)
if [[ $MODO != prueba && -z ${ESTACION_CIFRADO_INHIBIDO:-} ]] && command -v systemd-inhibit >/dev/null; then
  exec env ESTACION_CIFRADO_INHIBIDO=1 systemd-inhibit --what=idle:sleep:shutdown:handle-lid-switch:handle-power-key:handle-suspend-key \
    --who="cifrado-live" --why="Cifrando el disco: no apague" bash "$0" "$@"
fi

cargar_conf
if [[ $MODO != prueba ]]; then
  confirmar_riesgo "${DISCO##*/}" "cifrar en el sitio la raíz y /home de $DISCO"
fi
iniciar_log "cifrado-live-$MODO"
if [[ $MODO == prueba ]]; then trap 'borrar_frase' EXIT; else trap 'cerrar_todo; borrar_frase' EXIT; fi

comprobar_entorno; problemas=$?

if [[ $MODO == prueba ]]; then
  echo
  if [[ $problemas -eq 0 ]]; then
    echo "${V}#### PRUEBA: TODO CORRECTO. Puede cifrar:  sudo bash $BASE/cifrado-live.sh --ejecutar --acepto-perdida-de-datos${N}"
  else
    echo "${R}#### PRUEBA: $problemas PROBLEMA(S). NO CIFRE. Lea las líneas «MAL» de arriba (guía: «Si algo falla antes de cifrar»).${N}"
  fi
  exit $(( problemas > 0 ))
fi
[[ $problemas -eq 0 ]] || falla "las comprobaciones encontraron $problemas problema(s) (líneas «MAL» de arriba)" "Corrija lo que digan y vuelva a ejecutar el mismo script. No se ha cambiado nada." "Si algo falla antes de cifrar"
install -d "$TRABAJO" || falla "no puedo crear $TRABAJO" "Compruebe que el USB está montado con escritura." "Si algo falla antes de cifrar"

gib() { echo $(( $1 / 1073741824 )); }
echo
echo "  Va a hacer, por este orden:"
echo "   1. Raíz ($RAIZ_DEV, $(gib "$RAIZ_BYTES") GiB): comprobar, reducir, CIFRAR, abrir y verificar."
echo "   2. /home ($HOME_DEV, $(gib "$HOME_BYTES") GiB): lo mismo."
echo "   3. Configurar el arranque para pedir la frase (y, más adelante, el PIN del TPM)."
echo "  El cifrado recorre TODA la partición (también el espacio libre). El tiempo exacto lo estimó cifrado-prueba-loop.sh."
echo "  El equipo no se suspenderá aunque cierre la tapa, pero NO la cierre."
if [[ $MODO == reanudar ]]; then pausa "Se REANUDA donde se quedó. Primero pedirá la frase." "seguir"
else pausa "Se va a CIFRAR el disco. Primero pedirá la frase dos veces." "cifrar"; fi

# Frase: si alguna partición ya es LUKS, se comprueba contra ella
comprobar_con=""
for d in "$RAIZ_DEV" "$HOME_DEV"; do CS isLuks "$d" && { comprobar_con=$d; break; }; done
pedir_frase "$comprobar_con"

procesar RAIZ
CS open --test-passphrase --key-file "$FRASE" "$RAIZ_DEV" || falla "la frase no abre la raíz recién cifrada" "Ejecute cifrado-reanudar.sh." "Si se corta a mitad del cifrado"
estado_home=$(estado_de "$HOME_DEV" "$HOME_BTRFS" "$HOME_LUKS")
[[ $estado_home == cifrada ]] || pausa "Raíz TERMINADA. Ahora /home: cifrado más la comprobación." "seguir"
procesar HOME
configurar_arranque
cerrar_todo

echo
echo "${V}╔══════════════════════════════════════════════════════════════════════╗"
echo "║  TERMINADO: raíz y /home cifradas, arranque configurado.             ║"
echo "╚══════════════════════════════════════════════════════════════════════╝${N}"
echo "  Siguiente (guía, «Primer arranque cifrado»):"
echo "   1. Teclee:  sudo poweroff     y espere a que se apague del todo."
echo "   2. QUITE EL USB."
echo "   3. Encienda. En Limine elija la entrada normal. Le pedirá la FRASE (la de su gestor de contraseñas)."
echo "  Registro de esta ejecución: $LOG"
sync
