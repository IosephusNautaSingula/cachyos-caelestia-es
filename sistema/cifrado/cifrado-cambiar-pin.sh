#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# cifrado-cambiar-pin.sh — CAMBIAR EL PIN DEL TPM2 de la raíz. En el sistema cifrado, con root.
#  · Pide la frase (para autorizar) y el PIN nuevo dos veces; nada se ve ni va al registro; solo en RAM (/run).
#  · PIN: PIN_MIN caracteres o más; letras SIN tilde ni ñ (mayúsculas o minúsculas) y números. Esas teclas están en
#    el mismo sitio en el teclado español y en el inglés: en la pantalla de arranque se teclea igual.
#  · Deja un único hueco TPM2 (PCR de TPM_PCRS): systemd-cryptenroll inscribe el nuevo y borra el anterior en la misma
#    orden. No toca la frase ni la clave de recuperación. Ctrl+C no corta el cambio.
#  · Al final muestra los huecos de la raíz y actualiza la referencia del PCR (DIR_TPM_REFERENCIA).
set -uo pipefail
# shellcheck source=cifrado-comun.sh
source "$(cd "$(dirname "$0")" && pwd)/cifrado-comun.sh"

ayuda() {
  cat <<EOF
cifrado-cambiar-pin.sh — cambia el PIN del TPM2 de la raíz cifrada (sustituye el hueco TPM2 de LUKS).

  sudo bash $0 --ejecutar --acepto-perdida-de-datos

Pide la frase y el PIN nuevo (dos veces). No toca la frase ni la clave de recuperación.
Sin argumentos: muestra esta ayuda y sale.
EOF
}
leer_opciones "$@"
(( ${#OTRAS[@]} == 0 )) || { echo "Opción desconocida: ${OTRAS[*]}" >&2; ayuda; exit 2; }
if [[ -n $AYUDA || ( -z $EJECUTAR && -z $ACEPTO ) ]]; then ayuda; exit 0; fi
exigir_banderas
exigir_root
exec </dev/null
cargar_conf
confirmar_riesgo "${DISCO##*/}" "sustituir el hueco TPM2 + PIN de la raíz cifrada de $DISCO"
iniciar_log "cifrado-cambiar-pin"
ESTADO="sin cambios (el PIN anterior sigue valiendo)"
huecos() {
  local h tok q
  for h in $(meta "$RAIZ_DEV" | jq -r '.keyslots | keys[]'); do
    tok=$(meta "$RAIZ_DEV" | jq -r --arg h "$h" '[.tokens[] | select(.keyslots | index($h)) | .type] | join(",")')
    case $tok in
      *systemd-tpm2*) q="TPM2 + PIN";;
      *systemd-recovery*) q="clave de recuperación";;
      *) if [[ -s $FRASE ]] && CS open --test-passphrase --key-slot "$h" --key-file "$FRASE" "$RAIZ_DEV" >/dev/null 2>&1; then q="frase"; else q="${R}DESCONOCIDO${N}"; fi;;
    esac
    echo "     hueco $h: $q"
  done
}
final() {
  echo; echo "${A}======== ESTADO AL SALIR [$(date +%T)] ========${N}"
  echo "  PIN: $ESTADO"; echo "  Huecos de la raíz ($RAIZ_DEV):"; huecos
  borrar_secretos
  echo "  Registro: $LOG"
}
trap final EXIT

paso "Comprobaciones"
[[ $(findmnt -n -o SOURCE /) == "/dev/mapper/$RAIZ_MAP"* ]] && ok "sistema cifrado" || para "no es el sistema cifrado"
command -v jq >/dev/null || para "falta jq"
tpm_disponible && ok "TPM2 disponible" || para "no se encuentra un TPM2 utilizable (/dev/tpmrm0)"

paso "1. Frase (para autorizar el cambio)"
pedir_frase_sistema "$RAIZ_DEV"

paso "2. PIN nuevo"
pedir_pin "$S/pin" || para "no se fijó el PIN (el anterior sigue valiendo)"

paso "3. Reinscribir el TPM2 con el PIN nuevo (PCR $TPM_PCRS)"
trap '' INT TERM QUIT TSTP          # Ctrl+C no corta el cambio
n_antes=$(meta "$RAIZ_DEV" | jq '[.tokens[] | select(.type == "systemd-tpm2")] | length')
NEWPIN=$(cat "$S/pin") systemd-cryptenroll --wipe-slot=tpm2 --tpm2-device=auto --tpm2-pcrs="$TPM_PCRS" --tpm2-with-pin=yes \
  --unlock-key-file="$FRASE" "$RAIZ_DEV" </dev/null >/dev/null 2>&1; rc=$?
shred -u "$S/pin" 2>/dev/null
n_despues=$(meta "$RAIZ_DEV" | jq '[.tokens[] | select(.type == "systemd-tpm2")] | length')
trap - INT TERM QUIT TSTP
if [[ $rc -eq 0 && $n_despues -eq 1 ]]; then
  ESTADO="CAMBIADO: un único hueco TPM2 con el PIN nuevo (antes había $n_antes)"; ok "TPM2 reinscrito con el PIN nuevo; un único hueco TPM2"
  guardar_referencia_tpm; ok "referencia del PCR actualizada"
elif [[ $rc -eq 0 ]]; then ESTADO="$n_despues huecos TPM2 (se esperaba 1): revise"; para "quedaron $n_despues huecos TPM2"
else ESTADO="sin cambios: systemd-cryptenroll falló (código $rc); el PIN anterior sigue valiendo"; para "falló la inscripción (código $rc)"; fi

echo
echo "${V}#### HECHO.${N}"
echo "  1. Actualice ya el PIN en su gestor de contraseñas."
echo "  2. Reinicie para probarlo: en la pantalla del disco teclee el PIN nuevo."
echo "  3. Ya dentro:  sudo bash $BASE/cifrado-primer-arranque.sh --comprobar"
