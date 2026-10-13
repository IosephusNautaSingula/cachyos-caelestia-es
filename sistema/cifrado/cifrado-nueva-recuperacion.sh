#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# cifrado-nueva-recuperacion.sh — SUSTITUIR la clave de recuperación (p. ej. si la anterior quedó expuesta). En el
# sistema cifrado, con root.
#  1. Quita la clave de recuperación de la raíz (y en /home cualquier hueco que no sea la frase ni el fichero de clave).
#  2. Genera una NUEVA (systemd-cryptenroll), la muestra solo en pantalla y pide teclearla ENTERA para confirmar.
#     Ctrl+C no corta la confirmación; y pase lo que pase, al salir se dice el estado de cada partición.
#     Confirmada: se añade la misma a /home y se prueba en las dos. Sin confirmar: se quita de la raíz.
#  3. Cabeceras: borra (shred) las copias locales (DIR_CABECERAS) y las del destino en red, y hace copias nuevas.
#     Si hay COPIA_RESTIC, busca instantáneas que incluyan las cabeceras viejas y OFRECE reescribirlas sin ellas
#     (rewrite --dry-run → confirmar → rewrite → prune --max-unused 0 → check), con el cerrojo COPIA_CERROJO.
#  4. Muestra los huecos: raíz = frase, recuperación, TPM2+PIN; /home = frase, fichero de clave, recuperación.
# REGLA DE LAS CABECERAS: una copia de cabecera LUKS sigue aceptando las claves que tenía cuando se hizo. Si cambia la
# frase o la clave de recuperación (el PIN del TPM no: solo vale con este TPM), hay que sustituir también las copias
# viejas de las cabeceras, también las que estén dentro de la copia de seguridad.
# Nada secreto va al registro: la clave solo a la pantalla (/dev/tty).
set -uo pipefail
# shellcheck source=cifrado-comun.sh
source "$(cd "$(dirname "$0")" && pwd)/cifrado-comun.sh"

ayuda() {
  cat <<EOF
cifrado-nueva-recuperacion.sh — sustituye la clave de recuperación de la raíz y /home y rehace las copias de las
cabeceras LUKS (borra las viejas, que seguirían abriendo con la clave anterior).

  sudo bash $0 --ejecutar --acepto-perdida-de-datos

Pide la frase y, al final, que teclee la clave nueva leyéndola de su gestor de contraseñas.
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
confirmar_riesgo "${DISCO##*/}" "quitar y regenerar la clave de recuperación en los huecos LUKS de $DISCO"
iniciar_log "cifrado-nueva-recuperacion"
n_huecos() { meta "$1" | jq '.keyslots | length'; }
tokens() { meta "$1" | jq -r '[.tokens[] | .type + "→" + (.keyslots | join(","))] | join(" ")'; }
abre_hueco() { CS open --test-passphrase --key-slot "$2" --key-file "$3" "$1" >/dev/null 2>&1; }   # disp hueco fichero

# Estado al salir, pase lo que pase (también tras un error). Nunca muestra secretos.
ESTADO_REC="sin empezar"
estado_final() {
  local d
  echo; echo "${A}======== ESTADO AL SALIR [$(date +%T)] ========${N}"
  echo "  Clave de recuperación: $ESTADO_REC"
  for d in "$RAIZ_DEV" "$HOME_DEV"; do echo "  $d: $(n_huecos "$d") huecos · tokens: $(tokens "$d")"; done
  borrar_secretos; desmontar_red
  echo "  Registro: $LOG"
}
trap estado_final EXIT

paso "Comprobaciones"
es_sistema_cifrado && ok "sistema cifrado: / y /home salen de LUKS" || para "no es el sistema cifrado"
command -v jq >/dev/null || para "falta jq"
[[ -r $CLAVE_HOME ]] && ok "fichero de clave de /home presente" || para "falta el fichero de clave de /home"

paso "1. Frase (para autorizar los cambios)"
pedir_frase_sistema "$RAIZ_DEV" "$HOME_DEV"

paso "2. Quitar la clave de recuperación anterior"
if systemd-cryptenroll "$RAIZ_DEV" </dev/null 2>/dev/null | grep -qw recovery; then
  systemd-cryptenroll --wipe-slot=recovery --unlock-key-file="$FRASE" "$RAIZ_DEV" </dev/null >/dev/null 2>&1
  systemd-cryptenroll "$RAIZ_DEV" </dev/null 2>/dev/null | grep -qw recovery && para "no se pudo quitar la recuperación de la raíz" || ok "raíz: clave de recuperación anterior QUITADA"
else ok "raíz: no tenía clave de recuperación"; fi
# /home: solo deben quedar la frase y el fichero de clave; cualquier otro hueco (p. ej. una recuperación vieja) se quita
for h in $(meta "$HOME_DEV" | jq -r '.keyslots | keys[]'); do
  if abre_hueco "$HOME_DEV" "$h" "$FRASE"; then echo "  /home hueco $h: frase"
  elif abre_hueco "$HOME_DEV" "$h" "$CLAVE_HOME"; then echo "  /home hueco $h: fichero de clave"
  else CS luksKillSlot --key-file "$CLAVE_HOME" "$HOME_DEV" "$h" >/dev/null 2>&1 && ok "/home hueco $h (ni frase ni fichero de clave): QUITADO" || mal "no se pudo quitar el hueco $h de /home"; fi
done
ESTADO_REC="ninguna (la anterior ya no abre nada)"

paso "3. Clave de recuperación NUEVA (la misma para la raíz y /home)"
salida=$(systemd-cryptenroll --recovery-key --unlock-key-file="$FRASE" "$RAIZ_DEV" </dev/null 2>&1); rc=$?
clave=$(grep -oE '[cbdefghijklnrtuv]{8}(-[cbdefghijklnrtuv]{8}){7}' <<<"$salida" | head -1); salida=
if [[ $rc -ne 0 || -z $clave ]]; then
  systemd-cryptenroll --wipe-slot=recovery --unlock-key-file="$FRASE" "$RAIZ_DEV" </dev/null >/dev/null 2>&1
  para "no se pudo leer la clave nueva (código $rc); se ha quitado de la raíz. Vuelva a ejecutar el script"
fi
guardar_secreto "$S/rec" "$clave"
ESTADO_REC="NUEVA en la raíz, SIN CONFIRMAR (si sale así, vuelva a ejecutar el script: la quitará y hará otra)"
trap '' INT TERM QUIT TSTP          # Ctrl+C, Ctrl+\ y Ctrl+Z no cortan la confirmación
{ echo; echo "  ┌──────────── CLAVE DE RECUPERACIÓN NUEVA (solo en pantalla; NO queda en el registro) ────────────┐"
  echo "  │  $clave  │"
  echo "  └──────────────────────────────────────────────────────────────────────────────────────────────────┘"
  echo "  1. Cópiela en su gestor de contraseñas (sustituya la anterior), con los guiones."
  echo "  2. Después, teclee aquí la clave ENTERA leyéndola de su gestor (no de esta pantalla), con los guiones."
  echo "     (Ctrl+C no corta este paso. Para abandonar, escriba: abandonar)"; } >/dev/tty
confirmada=
for i in 1 2 3 4 5; do
  read -r -p "  Clave (desde su gestor de contraseñas): " t </dev/tty
  [[ $t == abandonar ]] && break
  if [[ $t == "$clave" ]]; then confirmada=1; break; fi
  echo "  ${R}No coincide (intento $i de 5). Compare grupo a grupo con la pantalla y corrija su gestor si hace falta.${N}" >/dev/tty
done
t=
if [[ -z $confirmada ]]; then
  systemd-cryptenroll --wipe-slot=recovery --unlock-key-file="$FRASE" "$RAIZ_DEV" </dev/null >/dev/null 2>&1
  clave=; ESTADO_REC="ninguna (no se confirmó; la nueva se ha QUITADO de la raíz). Vuelva a ejecutar el script"
  trap - INT TERM QUIT TSTP; para "no se confirmó la clave nueva; se ha quitado de la raíz"
fi
clear >/dev/tty 2>&1; clave=; ok "clave nueva confirmada (tecleada entera desde su gestor de contraseñas)"
ESTADO_REC="NUEVA en la raíz y confirmada; falta /home"
CS luksAddKey --key-file "$CLAVE_HOME" "$HOME_DEV" "$S/rec" >/dev/null 2>&1 && ok "la misma clave añadida a /home" || mal "no se pudo añadir a /home"
for d in "$RAIZ_DEV" "$HOME_DEV"; do CS open --test-passphrase --key-file "$S/rec" "$d" >/dev/null 2>&1 && ok "la clave nueva abre $d" || mal "la clave nueva NO abre $d"; done
[[ $FALLOS -eq 0 ]] && ESTADO_REC="NUEVA, confirmada, en la raíz y en /home (probada en las dos)"
trap - INT TERM QUIT TSTP

paso "4. Cabeceras: borrar las viejas (abren con la clave anterior) y hacer nuevas"
C=$DIR_CABECERAS; hoy=$(date +%F); install -d -m 700 "$C"
for f in "$C"/*-cabecera-*.img "$C"/SHA256SUMS-*; do [[ -e $f ]] && { shred -u "$f"; echo "  borrada (shred): ${f##*/}"; }; done
for p in raiz:"$RAIZ_DEV" home:"$HOME_DEV"; do
  f="$C/${p%%:*}-cabecera-$hoy.img"
  CS luksHeaderBackup "${p#*:}" --header-backup-file "$f" >/dev/null 2>&1 && chmod 600 "$f" && ok "cabecera nueva de ${p%%:*}" || mal "no se pudo copiar la cabecera de ${p%%:*}"
done
(cd "$C" && sha256sum ./*-"$hoy".img > "SHA256SUMS-$hoy" && chmod 600 "SHA256SUMS-$hoy")
if [[ -z $COPIA_RECURSO ]]; then aviso "sin destino en red: las cabeceras nuevas quedan solo en $C"
elif montar_red; then
  NC="$MNT_RED/$COPIA_SUBDIR/cabeceras"; install -d -m 700 "$NC"
  for f in "$NC"/*; do [[ -f $f ]] && { shred -u "$f" 2>/dev/null || rm -f "$f"; echo "  red: borrada ${f##*/}"; }; done
  cp "$C"/*-"$hoy".img "$C/SHA256SUMS-$hoy" "$NC/" && (cd "$NC" && sha256sum --quiet -c "SHA256SUMS-$hoy") && ok "cabeceras nuevas en la red" || mal "cabeceras de la red"
  desmontar_red
else mal "no se pudo montar el destino en red (las cabeceras nuevas quedan solo en $C)"; fi

paso "5. ¿Alguna copia de seguridad incluye las cabeceras viejas?"
if (( ${#COPIA_RESTIC[@]} == 0 )); then
  aviso "COPIA_RESTIC vacío: compruebe usted si su copia de seguridad guarda $C y quite de ella las cabeceras viejas"
else
  exec 9>"$COPIA_CERROJO"; flock -n 9 || para "hay una copia en marcha; repita al terminar"
  con=()
  for id in $("${COPIA_RESTIC[@]}" snapshots --json 2>/dev/null | jq -r '.[].short_id'); do
    n=$("${COPIA_RESTIC[@]}" ls "$id" "$C" 2>/dev/null | grep -c -- "-cabecera-" || true)
    (( n > 0 )) && { con+=("$id"); echo "  $id: $n ficheros de cabecera"; }
  done
  if (( ${#con[@]} == 0 )); then ok "ninguna instantánea incluye cabeceras: no hay que reescribir nada"
  else
    "${COPIA_RESTIC[@]}" rewrite --dry-run --exclude "$C" "${con[@]}"
    read -r -p "  Se quitarán las cabeceras de ${#con[@]} instantánea(s). Escriba «si» para seguir: " r </dev/tty
    if [[ $r == si ]]; then
      "${COPIA_RESTIC[@]}" rewrite --forget --exclude "$C" "${con[@]}" && "${COPIA_RESTIC[@]}" prune --max-unused 0 && "${COPIA_RESTIC[@]}" check \
        && ok "instantáneas reescritas sin cabeceras, prune y check" || mal "rewrite/prune/check"
    else mal "no se reescribieron las instantáneas (siguen con las cabeceras viejas)"; fi
  fi
  flock -u 9
fi

paso "6. Huecos de cada partición"
for p in raiz:"$RAIZ_DEV" home:"$HOME_DEV"; do
  d=${p#*:}; echo "  ${p%%:*} ($d):"
  for h in $(meta "$d" | jq -r '.keyslots | keys[]'); do
    tok=$(meta "$d" | jq -r --arg h "$h" '[.tokens[] | select(.keyslots | index($h)) | .type] | join(",")')
    if   [[ $tok == *systemd-tpm2* ]]; then q="TPM2 + PIN"
    elif abre_hueco "$d" "$h" "$FRASE"; then q="frase"
    elif abre_hueco "$d" "$h" "$S/rec"; then q="clave de recuperación"
    elif [[ ${p%%:*} == home ]] && abre_hueco "$d" "$h" "$CLAVE_HOME"; then q="fichero de clave"
    else q="${R}DESCONOCIDO${N}"; FALLOS=$((FALLOS + 1)); fi
    echo "     hueco $h: $q${tok:+ (token $tok)}"
  done
done
echo; [[ $FALLOS -eq 0 ]] && echo "${V}#### HECHO: clave de recuperación sustituida; cabeceras nuevas.${N}" || echo "${R}#### $FALLOS problema(s): revise las líneas MAL.${N}"
echo "  ${A}Recuerde la regla de las cabeceras:${N} una copia vieja de cabecera sigue abriendo con la clave que tenía."
echo "  Si en el paso 5 respondió «no» (o no hay COPIA_RESTIC), quite usted las cabeceras viejas de su copia de seguridad."
