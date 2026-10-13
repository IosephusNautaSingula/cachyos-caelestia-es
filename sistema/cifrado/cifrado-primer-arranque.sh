#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# cifrado-primer-arranque.sh — PRIMER ARRANQUE ya cifrado (en el sistema, con root). Después de entrar con la FRASE:
#  1. Comprueba que / y /home salen de LUKS, con TRIM, y que el arranque está bien configurado.
#  2. TPM2 + PIN en la raíz (PCR de TPM_PCRS, por defecto 7). /home se abre sola con su fichero de clave.
#  3. Clave de recuperación (la genera systemd-cryptenroll) en la raíz y la MISMA en /home. Solo se muestra en
#     pantalla (/dev/tty, fuera del registro) y hay que teclearla entera para confirmar que se ha guardado.
#  4. Copia de las cabeceras LUKS (luksHeaderBackup) en DIR_CABECERAS y, si lo hay, en el destino en red.
#  5. Entradas de Limine (instantáneas), referencia del TPM e instantáneas «Fin del cifrado (LUKS)».
# Con --comprobar (tras reiniciar con el PIN) solo comprueba; no cambia nada.
set -uo pipefail
# shellcheck source=cifrado-comun.sh
source "$(cd "$(dirname "$0")" && pwd)/cifrado-comun.sh"

ayuda() {
  cat <<EOF
cifrado-primer-arranque.sh — en el sistema ya cifrado, tras entrar con la frase: TPM2 + PIN, clave de recuperación y
copia de las cabeceras.

  sudo bash $0 --comprobar
      Solo comprueba (solo lectura): sistema cifrado, TRIM, crypttab, Limine y si la raíz se abrió con el TPM2 + PIN.

  sudo bash $0 --ejecutar --acepto-perdida-de-datos
      Inscribe el TPM2 + PIN y la clave de recuperación (cambia los huecos de LUKS) y copia las cabeceras.
      Pregunta: la frase, el PIN (dos veces) y la clave de recuperación (para confirmar que la guardó).

Sin argumentos: muestra esta ayuda y sale.
EOF
}
leer_opciones "$@"
COMPROBAR=
for a in "${OTRAS[@]}"; do case $a in --comprobar) COMPROBAR=1;; *) echo "Opción desconocida: $a" >&2; ayuda; exit 2;; esac; done
if [[ -n $AYUDA || ( -z $COMPROBAR && -z $EJECUTAR && -z $ACEPTO ) ]]; then ayuda; exit 0; fi
[[ -n $COMPROBAR ]] || exigir_banderas
exigir_root
exec </dev/null
cargar_conf
[[ -n $COMPROBAR ]] || confirmar_riesgo "${DISCO##*/}" "inscribir TPM2 + PIN y clave de recuperación en los huecos LUKS de $DISCO"
iniciar_log "cifrado-primer-arranque${COMPROBAR:+-comprobar}"
trap borrar_secretos EXIT

comprobar_sistema() {
  local m t n f
  paso "Comprobación del sistema cifrado"
  [[ $(findmnt -n -o SOURCE /) == "/dev/mapper/$RAIZ_MAP"* ]] && ok "/ sale de /dev/mapper/$RAIZ_MAP" || mal "/ no sale de $RAIZ_MAP ($(findmnt -n -o SOURCE /))"
  [[ $(findmnt -n -o SOURCE /home) == "/dev/mapper/$HOME_MAP"* ]] && ok "/home sale de /dev/mapper/$HOME_MAP" || mal "/home no sale de $HOME_MAP"
  for m in "$RAIZ_MAP" "$HOME_MAP"; do
    t=$(dmsetup table "$m" 2>/dev/null)
    [[ $t == *aes-xts-plain64* ]] && ok "$m: aes-xts-plain64" || mal "$m: cifrado inesperado"
    [[ $t == *allow_discards* ]] && ok "$m: TRIM activo" || mal "$m: sin TRIM"
  done
  [[ $(CS luksUUID "$RAIZ_DEV") == "$RAIZ_LUKS" && $(CS luksUUID "$HOME_DEV") == "$HOME_LUKS" ]] && ok "UUID de LUKS los de cifrado.conf" || mal "UUID de LUKS distintos de cifrado.conf"
  grep -q "^$RAIZ_MAP UUID=$RAIZ_LUKS none luks" /etc/crypttab.initramfs && ! grep -q nofail /etc/crypttab.initramfs \
    && ok "crypttab.initramfs definitivo (sin nofail)" || mal "crypttab.initramfs no es el definitivo"
  grep -q "^$HOME_MAP UUID=$HOME_LUKS $CLAVE_HOME" /etc/crypttab && ok "crypttab: $HOME_MAP con fichero de clave" || mal "crypttab sin $HOME_MAP"
  [[ $(stat -c %a "$CLAVE_HOME" 2>/dev/null) == 400 ]] && ok "fichero de clave 0400" || mal "fichero de clave ausente o con permisos abiertos"
  n=$(sed '/\/\/Snapshots/q' "$LIMINE_CONF" | grep -c "cmdline:.*rd.luks.name=$RAIZ_LUKS")
  (( n >= 1 )) && ok "Limine: $n entradas principales con rd.luks.name" || mal "Limine: ninguna entrada principal con rd.luks.name"
  f=$(systemctl --failed --no-legend --plain | wc -l); (( f == 0 )) && ok "sin servicios fallidos" || mal "$f servicio(s) fallido(s): $(systemctl --failed --no-legend --plain | awk '{print $1}' | paste -sd' ')"
}

# Cómo se abrió la raíz en el arranque $1 (0 = este). Solo lee el journal. Heurística: algunas versiones de systemd
# no registran qué hueco se usó. Dos huellas del initrd:
#  · «Set cipher … <UUID de LUKS>» solo aparece al abrir con frase o clave de recuperación (no con el token TPM2);
#  · la memoria máxima de systemd-cryptsetup@<mapeo>: con TPM2+PIN suele ser mayor (argon2id del PIN) que con la frase.
como_se_abrio() {
  local j sc mem mib
  j=$(journalctl -b "$1" --no-pager 2>/dev/null)
  [[ $j == *"Finished Cryptography Setup for $RAIZ_MAP"* || $j == *"systemd-cryptsetup@$RAIZ_MAP.service: Consumed"* ]] || { echo "desconocido (no consta la apertura de $RAIZ_MAP)"; return; }
  sc=$(grep -c "Set cipher.*$RAIZ_LUKS" <<<"$j")
  mem=$(grep -oE "systemd-cryptsetup@$RAIZ_MAP.service: Consumed .*, ([0-9.]+[KMG]) memory peak" <<<"$j" | grep -oE '[0-9.]+[KMG] memory' | head -1 | cut -d' ' -f1)
  case $mem in *G) mib=$(awk -v v="${mem%G}" 'BEGIN{printf "%d", v*1024}');; *M) mib=${mem%M}; mib=${mib%.*};; *) mib=0;; esac
  if (( sc == 0 && mib >= 1536 )); then echo "TPM2 + PIN (sin «Set cipher»; memoria ${mem})"
  elif (( sc > 0 )); then echo "frase o clave de recuperación («Set cipher» ×$sc; memoria ${mem:-?})"
  else echo "dudoso (sin «Set cipher» pero memoria ${mem:-?})"; fi
}

if [[ -n $COMPROBAR ]]; then
  comprobar_sistema
  paso "¿Se abrió con el TPM?"
  metodo=$(como_se_abrio 0); echo "  $metodo"
  [[ $metodo == TPM2* ]] && ok "la raíz se abrió con el TPM2 + PIN" || mal "no consta que la raíz se abriera con el TPM2 + PIN en este arranque"
  if [[ -r $DIR_TPM_REFERENCIA/pcr ]]; then
    [[ $(systemd-analyze pcrs "${TPM_PCRS%%[+,]*}" 2>/dev/null | awk 'NR==2{print $3}') == "$(cat "$DIR_TPM_REFERENCIA/pcr")" ]] \
      && ok "PCR ${TPM_PCRS%%[+,]*} igual que al inscribir" || mal "PCR ${TPM_PCRS%%[+,]*} distinto del de la inscripción"
  fi
  echo; [[ $FALLOS -eq 0 ]] && echo "${V}#### COMPROBADO: arranque cifrado correcto.${N}" || echo "${R}#### $FALLOS problema(s).${N}"
  exit $(( FALLOS > 0 ))
fi

comprobar_sistema
[[ $FALLOS -eq 0 ]] || para "$FALLOS problema(s) en el sistema cifrado; no se inscribe el TPM"
command -v jq >/dev/null || para "falta jq"

paso "1. Frase (para autorizar los cambios en LUKS)"
pedir_frase_sistema "$RAIZ_DEV" "$HOME_DEV"
CS open --test-passphrase --key-file "$CLAVE_HOME" "$HOME_DEV" && ok "/home abre también con su fichero de clave" || mal "/home no abre con el fichero de clave"

paso "2. TPM2 + PIN (PCR $TPM_PCRS)"
systemd-cryptenroll --tpm2-device=list </dev/null | sed 's/^/  /'
tpm_disponible || para "no se encuentra un TPM2 utilizable (/dev/tpmrm0)"
echo "  ${A}Guarde primero el PIN nuevo en su gestor de contraseñas.${N}"
pedir_pin "$S/pin" || para "no se pudo fijar el PIN"
borrar=(); systemd-cryptenroll "$RAIZ_DEV" </dev/null | grep -qw tpm2 && borrar=(--wipe-slot=tpm2) && echo "  (ya había un TPM2: se sustituye)"
NEWPIN=$(cat "$S/pin") systemd-cryptenroll "${borrar[@]}" --tpm2-device=auto --tpm2-pcrs="$TPM_PCRS" --tpm2-with-pin=yes \
  --unlock-key-file="$FRASE" "$RAIZ_DEV" </dev/null >/dev/null 2>&1; rc=$?
shred -u "$S/pin" 2>/dev/null
[[ $rc -eq 0 ]] && systemd-cryptenroll "$RAIZ_DEV" </dev/null | grep -qw tpm2 && ok "TPM2 + PIN inscritos en la raíz (PCR $TPM_PCRS)" || para "falló la inscripción del TPM2 (código $rc)"
guardar_referencia_tpm; ok "referencia guardada en $DIR_TPM_REFERENCIA (PCR y versión de la BIOS; sin secretos)"

paso "3. Clave de recuperación (la misma para la raíz y /home)"
# Solo se conserva una recuperación si está completa: en la raíz (token) y en /home (3 huecos: frase, fichero, recuperación)
if systemd-cryptenroll "$RAIZ_DEV" </dev/null 2>/dev/null | grep -qw recovery && (( $(meta "$HOME_DEV" | jq '.keyslots | length') >= 3 )); then
  echo "  Ya hay clave de recuperación en la raíz y en /home: se conserva (la de su gestor de contraseñas sigue valiendo)."
else
  if systemd-cryptenroll "$RAIZ_DEV" </dev/null 2>/dev/null | grep -qw recovery; then
    systemd-cryptenroll --wipe-slot=recovery --unlock-key-file="$FRASE" "$RAIZ_DEV" </dev/null >/dev/null 2>&1
    echo "  Había una clave de recuperación a medias (sin /home): se QUITA y se genera otra."
  fi
  salida=$(systemd-cryptenroll --recovery-key --unlock-key-file="$FRASE" "$RAIZ_DEV" </dev/null 2>&1); rc=$?
  clave=$(grep -oE '[cbdefghijklnrtuv]{8}(-[cbdefghijklnrtuv]{8}){7}' <<<"$salida" | head -1); salida=
  if [[ $rc -ne 0 || -z $clave ]]; then
    systemd-cryptenroll --wipe-slot=recovery --unlock-key-file="$FRASE" "$RAIZ_DEV" </dev/null >/dev/null 2>&1
    para "no se pudo leer la clave de recuperación (código $rc); el hueco se ha quitado. Vuelva a ejecutar el script"
  fi
  guardar_secreto "$S/rec" "$clave"
  trap '' INT TERM QUIT TSTP          # Ctrl+C no corta la confirmación
  { echo; echo "  ┌──────────────── CLAVE DE RECUPERACIÓN (solo en pantalla; NO queda en el registro) ────────────────┐"
    echo "  │  $clave  │"
    echo "  └────────────────────────────────────────────────────────────────────────────────────────────────────┘"
    echo "  1. Cópiela en su gestor de contraseñas, con los guiones."
    echo "  2. Teclee aquí la clave ENTERA leyéndola de su gestor (no de esta pantalla). Para abandonar: abandonar"; } >/dev/tty
  confirmada=
  for i in 1 2 3 4 5; do
    read -r -p "  Clave (desde su gestor de contraseñas): " t </dev/tty
    [[ $t == abandonar ]] && break
    [[ $t == "$clave" ]] && { confirmada=1; break; }
    echo "  ${R}No coincide (intento $i de 5).${N}" >/dev/tty
  done; t=
  if [[ -z $confirmada ]]; then
    systemd-cryptenroll --wipe-slot=recovery --unlock-key-file="$FRASE" "$RAIZ_DEV" </dev/null >/dev/null 2>&1; clave=
    trap - INT TERM QUIT TSTP; para "no se confirmó la clave de recuperación: se ha QUITADO de la raíz. Vuelva a ejecutar el script"
  fi
  trap - INT TERM QUIT TSTP
  clear >/dev/tty 2>&1; clave=; ok "clave de recuperación confirmada (tecleada entera)"
  CS luksAddKey --key-file "$CLAVE_HOME" "$HOME_DEV" "$S/rec" >/dev/null 2>&1 && ok "la misma clave añadida a /home" || mal "no se pudo añadir a /home"
  for d in "$RAIZ_DEV" "$HOME_DEV"; do CS open --test-passphrase --key-file "$S/rec" "$d" >/dev/null 2>&1 && ok "la clave de recuperación abre $d" || mal "la clave de recuperación NO abre $d"; done
fi
for d in "$RAIZ_DEV" "$HOME_DEV"; do
  echo "  $d: $(meta "$d" | jq '.keyslots | length') huecos · tokens: $(meta "$d" | jq -r '[.tokens[].type] | join(" ")')"
done

paso "4. Copia de las cabeceras LUKS"
# Una copia de cabecera sigue aceptando las claves que tenía al hacerse: guárdela como un secreto (0600, fuera de
# cualquier sitio público). Si cambia la frase o la recuperación, use cifrado-nueva-recuperacion.sh.
C=$DIR_CABECERAS; install -d -m 700 "$C"; hoy=$(date +%F)
for p in raiz:"$RAIZ_DEV" home:"$HOME_DEV"; do
  f="$C/${p%%:*}-cabecera-$hoy.img"; rm -f "$f"
  CS luksHeaderBackup "${p#*:}" --header-backup-file "$f" >/dev/null 2>&1 && chmod 600 "$f" && ok "cabecera de ${p%%:*}: $f" || mal "no se pudo copiar la cabecera de ${p%%:*}"
done
(cd "$C" && sha256sum ./*-"$hoy".img > "SHA256SUMS-$hoy" && chmod 600 "SHA256SUMS-$hoy")
if [[ -z $COPIA_RECURSO ]]; then aviso "sin destino en red: las cabeceras quedan solo en $C (llévelas a su copia de seguridad)"
elif montar_red; then
  NC="$MNT_RED/$COPIA_SUBDIR/cabeceras"; install -d -m 700 "$NC"; cp "$C"/*-"$hoy".img "$C/SHA256SUMS-$hoy" "$NC/"
  (cd "$NC" && sha256sum --quiet -c "SHA256SUMS-$hoy") && ok "cabeceras en la red ($COPIA_SUBDIR/cabeceras)" || mal "las cabeceras de la red no coinciden"
  desmontar_red
else mal "no se pudo montar el destino en red: las cabeceras quedan solo en $C"; fi

paso "5. Limine e instantáneas"
if command -v limine-snapper-sync >/dev/null; then timeout 600 limine-snapper-sync >/dev/null 2>&1 && ok "entradas de instantáneas regeneradas" || mal "limine-snapper-sync falló"; fi
echo "  entradas con rd.luks.name: $(grep -c 'cmdline:.*rd.luks.name' "$LIMINE_CONF") de $(grep -c 'cmdline:' "$LIMINE_CONF")"
for c in $SNAPPER_CONFIGS; do
  n=$(snapper -c "$c" create --description "Fin del cifrado (LUKS)" --userdata important=yes --print-number) && ok "snapper $c #$n «Fin del cifrado (LUKS)»" || mal "snapper $c"
done
if command -v limine-snapper-sync >/dev/null; then timeout 600 limine-snapper-sync >/dev/null 2>&1; fi

echo
if [[ $FALLOS -eq 0 ]]; then
  echo "${V}#### HECHO. Ahora REINICIE para probar el PIN:${N}"
  echo "  reboot → Limine → entrada normal → pedirá el PIN. Ya dentro:"
  echo "  sudo bash $BASE/cifrado-primer-arranque.sh --comprobar"
else echo "${R}#### $FALLOS problema(s): revise las líneas MAL (registro: $LOG).${N}"; fi
