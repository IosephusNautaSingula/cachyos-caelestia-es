#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# cifrado-copiar.sh — rehace SHA256SUMS de los scripts y los copia, verificados, a:
#   · el USB del entorno live (por su etiqueta y número de serie), carpeta DIR_EN_USB;
#   · la ESP (plan B, por si en el live no se puede montar el USB), carpeta <ESP>/DIR_EN_USB;
#   · el destino en red (si COPIA_RECURSO está configurado), carpeta COPIA_SUBDIR.
# No cambia nada más. Los ficheros copiados: cifrado-*.sh, cifrado.conf y README.md (nunca claves ni registros).
set -uo pipefail
# shellcheck source=cifrado-comun.sh
source "$(cd "$(dirname "$0")" && pwd)/cifrado-comun.sh"

ayuda() {
  cat <<AYUDA
cifrado-copiar.sh — copia y verifica los scripts en el USB, la ESP (plan B) y, si lo hay, el destino en red.

  sudo bash $0 --ejecutar --acepto-perdida-de-datos

Escribe en el USB, en la ESP y en la red (no en las particiones que se cifran). Sin argumentos: muestra esta ayuda.
AYUDA
}
leer_opciones "$@"
(( ${#OTRAS[@]} == 0 )) || { echo "Opción desconocida: ${OTRAS[*]}" >&2; ayuda; exit 2; }
if [[ -n $AYUDA || ( -z $EJECUTAR && -z $ACEPTO ) ]]; then ayuda; exit 0; fi
exigir_banderas
exigir_root
exec </dev/null
cargar_conf
confirmar_riesgo "copiar" "copiar los scripts al USB, a la ESP ($ESP_MONTAJE/$DIR_EN_USB) y al destino en red"
iniciar_log "cifrado-copiar"
DESMONTAR_USB=
trap '[[ -n $DESMONTAR_USB ]] && umount "$USB"; desmontar_red' EXIT

paso "Sumas"
(cd "$BASE" && sha256sum $(ficheros_publicables) > SHA256SUMS.nuevo && mv SHA256SUMS.nuevo SHA256SUMS) || para "no se pudo crear SHA256SUMS"
chmod 644 "$BASE/SHA256SUMS"; sed 's/^/  /' "$BASE/SHA256SUMS"

paso "USB"
USBDEV=$(readlink -f "/dev/disk/by-label/$USB_ETIQUETA" 2>/dev/null); USBDISCO=$(disco_de "$USBDEV")
if [[ -z $USB_ETIQUETA || ! -b $USBDEV || $USBDISCO == "$DISCO" ]]; then mal "no encuentro el USB (etiqueta de cifrado.conf)"
elif [[ $(udevadm info -q property -n "$USBDISCO" | sed -n 's/^ID_SERIAL=//p') != "${USB_SERIE%-0:0}" && \
        $(udevadm info -q property -n "$USBDISCO" | sed -n 's/^ID_SERIAL=//p') != "$USB_SERIE" ]]; then mal "el USB $USBDISCO no tiene la serie de cifrado.conf"
else
  USB=$(findmnt -rn -S "$USBDEV" -o TARGET | head -1)
  if [[ -z $USB ]]; then USB=/mnt/estacion-cifrado-usb; install -d "$USB"; mount "$USBDEV" "$USB" && DESMONTAR_USB=1 || mal "no se pudo montar el USB"; fi
  [[ -n $USB ]] && mountpoint -q "$USB" && { copiar_a "$USB/$DIR_EN_USB" && ok "USB: $USB/$DIR_EN_USB verificado" || mal "USB: la copia no coincide"; }
fi

paso "ESP (plan B)"
copiar_a "$ESP_MONTAJE/$DIR_EN_USB" && ok "ESP: $ESP_MONTAJE/$DIR_EN_USB verificado ($(du -sh "$ESP_MONTAJE/$DIR_EN_USB" | cut -f1))" || mal "ESP: la copia no coincide"

paso "Destino en red"
if [[ -z $COPIA_RECURSO ]]; then aviso "sin destino en red configurado (COPIA_RECURSO vacío)"
elif montar_red; then copiar_a "$MNT_RED/$COPIA_SUBDIR" && ok "red: $COPIA_SUBDIR verificado" || mal "red: la copia no coincide"; desmontar_red
else mal "no se pudo montar el destino en red"; fi

echo
echo "  SHA256SUMS = $(sha256sum "$BASE/SHA256SUMS" | cut -c1-64)   (guárdela en su gestor de contraseñas para compararla en el live)"
[[ $FALLOS -eq 0 ]] && echo "${V}#### COPIADO Y VERIFICADO.${N}" || echo "${R}#### $FALLOS problema(s).${N}"
exit $(( FALLOS > 0 ))
