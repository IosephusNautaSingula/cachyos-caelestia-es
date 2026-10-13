#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# cifrado-limpiar-prueba.sh — limpia los restos de cifrado-prueba-loop.sh (si se interrumpió) y comprueba, en solo
# lectura, que el disco real NO se tocó.
# Solo actúa sobre lo de la prueba: procesos cryptsetup que trabajan en /var/tmp/estacion-cifrado-prueba, sobre el
# mapeo «cifradoprueba» o sobre un loop de su imagen; ese mapeo; los loops de esa imagen; los bloqueos sin dueño de
# cryptsetup de esos loops; el directorio de la prueba y sus cabeceras temporales LUKS2-temp-*.new.
set -uo pipefail
# shellcheck source=cifrado-comun.sh
source "$(cd "$(dirname "$0")" && pwd)/cifrado-comun.sh"
W=/var/tmp/estacion-cifrado-prueba; IMG="$W/disco.img"; NOMBRE=cifradoprueba

ayuda() {
  cat <<AYUDA
cifrado-limpiar-prueba.sh — limpia los restos de una prueba en seco interrumpida ($W).

  sudo bash $0 --ejecutar --acepto-perdida-de-datos

Solo toca lo de la prueba (su directorio, su imagen, sus loops, el mapeo «$NOMBRE» y los cryptsetup que trabajan
sobre ellos). Después comprueba en solo lectura que la raíz y /home de cifrado.conf siguen en claro.
Sin argumentos: muestra esta ayuda y sale.
AYUDA
}
leer_opciones "$@"
(( ${#OTRAS[@]} == 0 )) || { echo "Opción desconocida: ${OTRAS[*]}" >&2; ayuda; exit 2; }
if [[ -n $AYUDA || ( -z $EJECUTAR && -z $ACEPTO ) ]]; then ayuda; exit 0; fi
exigir_banderas
exigir_root
exec </dev/null
CON_CONF=; [[ -r $CONF ]] && { cargar_conf; CON_CONF=1; }
LOGDIR=${LOGDIR:-$BASE/registros}
confirmar_riesgo "prueba" "borrar los restos de la prueba en seco de $W (el disco real no se toca)"
iniciar_log "cifrado-limpiar-prueba"

mapfile -t LOOPS < <(losetup -j "$IMG" 2>/dev/null | cut -d: -f1)
echo "== Procesos"
for c in $(pgrep -x cryptsetup); do
  cmd=$(tr '\0' ' ' < "/proc/$c/cmdline" 2>/dev/null); nuestro=
  [[ $cmd == *"$W"* || $cmd == *" $NOMBRE"* ]] && nuestro=1
  for l in "${LOOPS[@]}"; do [[ $cmd == *"$l"* ]] && nuestro=1; done
  if [[ -n $nuestro ]]; then echo "  mata $c: $cmd"; kill -9 "$c"; else echo "  NO se toca $c: $cmd"; fi
done
pgrep -af "cifrado-prueba-loop" | grep -v pgrep | sed 's/^/  script de prueba en marcha: /'

echo "== Montajes, mapeo y loops de la prueba"
findmnt -rn -o TARGET | grep "^$W" | while read -r m; do umount "$m" && echo "  desmontado $m"; done
[[ -e /dev/mapper/$NOMBRE ]] && cryptsetup close "$NOMBRE" && echo "  cerrado $NOMBRE"
for l in "${LOOPS[@]}"; do
  f="/run/cryptsetup/L_$(lsblk -dno MAJ:MIN "$l" 2>/dev/null | tr -d ' ')"
  losetup -d "$l" && echo "  soltado $l"
  if [[ -e $f ]]; then
    if flock -n "$f" true; then rm -f "$f" && echo "  quitado bloqueo sin dueño ${f##*/}"; else echo "  !! ${f##*/} sigue en uso"; fi
  fi
done
echo "  loops que quedan de la imagen: $(losetup -j "$IMG" 2>/dev/null | wc -l)"

echo "== Directorio de la prueba y cabeceras temporales"
[[ -d $W ]] && rm -rf --one-file-system "${W:?}" && echo "  borrado $W"
echo "  quedan LUKS2-temp en /var/tmp: $(find /var/tmp -xdev -name 'LUKS2-temp-*.new' 2>/dev/null | wc -l)"

echo "== Disco real (solo lectura)"
if [[ -n $CON_CONF ]]; then
  for p in RAIZ HOME; do
    dv=${p}_DEV bt=${p}_BTRFS
    e=$(estado_de "${!dv}" "${!bt}" "${p}-sin-luks")
    [[ $e == claro ]] && ok "$p (${!dv}): btrfs en claro con el UUID de cifrado.conf; sin LUKS" || mal "$p (${!dv}): estado «$e» (se esperaba en claro)"
  done
else echo "  (sin cifrado.conf: no se comprueba el disco real)"; fi
echo "#### Fin $(date +%T)"
