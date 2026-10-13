#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# cifrado-rescate.sh — RESCATE desde el live si, ya cifrado, el sistema NO arranca.
# Abre las dos particiones (con la frase o con la clave de recuperación), y ofrece:
#   1. Rehacer la configuración de arranque (crypttab, crypttab.initramfs, sd-encrypt, rd.luks.name, Limine) y comprobarla.
#   2. Solo abrir y montar el sistema para mirarlo (queda abierto; al terminar, vuelva a ejecutar y elija 3).
#   3. Desmontar y cerrar todo.
# Si alguna partición está a medio cifrar, no es para este script: use cifrado-reanudar.sh.
set -uo pipefail
# shellcheck source=cifrado-comun.sh
source "$(cd "$(dirname "$0")" && pwd)/cifrado-comun.sh"

ayuda() {
  cat <<AYUDA
cifrado-rescate.sh — rescate desde el entorno live cuando el sistema ya cifrado no arranca.

  sudo bash $0 --ejecutar --acepto-perdida-de-datos

Abre la raíz y /home con la frase o la clave de recuperación y ofrece: 1) rehacer la configuración de arranque,
2) montar el sistema en $MNT para mirarlo, 3) desmontar y cerrar todo.
Sin argumentos: muestra esta ayuda y sale.
AYUDA
}
leer_opciones "$@"
(( ${#OTRAS[@]} == 0 )) || { echo "Opción desconocida: ${OTRAS[*]}" >&2; ayuda; exit 2; }
if [[ -n $AYUDA || ( -z $EJECUTAR && -z $ACEPTO ) ]]; then ayuda; exit 0; fi
exigir_banderas
exigir_root
exec </dev/null
cargar_conf
confirmar_riesgo "${DISCO##*/}" "abrir las particiones cifradas de $DISCO y, si lo elige, rehacer la configuración de arranque"
iniciar_log "cifrado-rescate"
DEJAR_ABIERTO=
trap '[[ -z $DEJAR_ABIERTO ]] && cerrar_todo; borrar_frase' EXIT

comprobar_entorno; problemas=$?
# Aquí se tolera que esté montado lo nuestro (de una ejecución anterior con la opción 2): se desmonta primero
if [[ $problemas -gt 0 ]]; then
  desmontar_sistema; FALLOS=0; comprobar_entorno; problemas=$?
  [[ $problemas -eq 0 ]] || falla "las comprobaciones encontraron $problemas problema(s)" "Lea las líneas «MAL»." "Si no arranca"
fi
for p in RAIZ HOME; do
  dv=${p}_DEV bt=${p}_BTRFS lu=${p}_LUKS
  e=$(estado_de "${!dv}" "${!bt}" "${!lu}")
  [[ $e == cifrada ]] || falla "$p está «$e», no cifrada por completo" "Use  sudo bash $BASE/cifrado-reanudar.sh --ejecutar --acepto-perdida-de-datos" "Si se corta a mitad del cifrado"
done
ok "las dos particiones están cifradas por completo"

pedir_frase "$RAIZ_DEV" libre
for p in RAIZ HOME; do
  dv=${p}_DEV mp=${p}_MAP
  [[ -e /dev/mapper/${!mp} ]] || CS open --key-file "$FRASE" "${!dv}" "${!mp}" || falla "no se pudo abrir $p" "Pruebe con la otra (frase o clave de recuperación)." "Si no arranca"
  ok "$p abierta como /dev/mapper/${!mp}"
done

echo
echo "  1  Rehacer la configuración de arranque y comprobarla (lo normal si no arranca)"
echo "  2  Solo montar el sistema en $MNT para mirarlo (queda abierto)"
echo "  3  Desmontar, cerrar y salir"
read -r -p "  Elija 1, 2 o 3 y pulse Intro: " op </dev/tty; echo "  (opción: $op)"
case $op in
  1) configurar_arranque; cerrar_todo
     echo "${V}  Hecho. Apague (sudo poweroff), quite el USB y encienda (guía, «Primer arranque cifrado»).${N}";;
  2) montar_sistema; DEJAR_ABIERTO=1
     echo "  Montado en $MNT (con $ESP_MONTAJE). Para entrar como en el sistema: sudo arch-chroot $MNT"
     echo "  Al terminar: sudo bash $BASE/cifrado-rescate.sh --ejecutar --acepto-perdida-de-datos  y elija 3.";;
  3) cerrar_todo; echo "  Cerrado.";;
  *) echo "  Opción no válida; se cierra todo."; cerrar_todo;;
esac
