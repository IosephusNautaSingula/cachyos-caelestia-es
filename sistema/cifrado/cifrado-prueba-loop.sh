#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# cifrado-prueba-loop.sh — PRUEBA EN SECO del cifrado en el sitio con un fichero de imagen y un dispositivo loop.
# Solo toca su propio fichero (en /var/tmp) y su loop: NUNCA el disco real. NO LEE DEL TECLADO durante la prueba:
# stdin es /dev/null, todas las órdenes de cryptsetup llevan --batch-mode y la clave por --key-file, y cada paso tiene
# un tiempo máximo.
#  A. btrfs con subvolúmenes, instantánea y datos con sumas → reducir → reencrypt --encrypt (LUKS2, datashift con
#     --reduce-device-size 32M, --uuid fijado) → abrir con discards persistentes → crecer → sumas, check, scrub. Velocidad.
#  B. Fichero de clave (como el de /home), clave de recuperación, copia de la cabecera.
#  C. CORTES: kill -9 al cryptsetup en 13 puntos (0,2 a 8 s —inicialización, escritura de la cabecera y primer tramo— y
#     al 25 / 50 / 90 %). Antes de recuperar, «apagón»: se pierde la cabecera temporal (estaría en RAM) y se quitan
#     bloqueos sin dueño. Después: si ya es LUKS → repair + reencrypt --resume-only HASTA TERMINAR; si no → btrfs en
#     claro intacto y se repite. En los dos casos: cifrado completo (sin requisito online-reencrypt) y sumas correctas.
#  D. Marcha atrás: descifrado en el sitio (reencrypt --decrypt con la cabecera exportada) y sumas.
#  E. Estimación de tiempos para las particiones reales (si hay cifrado.conf).
# El trap limpia SIEMPRE (y, si algo quedara, cifrado-limpiar-prueba.sh).
set -uo pipefail
# shellcheck source=cifrado-comun.sh
source "$(cd "$(dirname "$0")" && pwd)/cifrado-comun.sh"

W=/var/tmp/estacion-cifrado-prueba; IMG="$W/disco.img"; PMNT="$W/mnt"; K="$W/frase.key"
NOMBRE=cifradoprueba; TAM_MIB=8192

ayuda() {
  cat <<EOF
cifrado-prueba-loop.sh — prueba en seco del cifrado en el sitio sobre una imagen de $((TAM_MIB / 1024)) GiB en $W.
No toca el disco real: crea un fichero, lo cifra, lo corta 13 veces con kill -9, lo recupera, lo descifra y lo borra.
Necesita unos $((TAM_MIB / 1024 + 1)) GiB libres en /var/tmp y tarda de 10 a 30 minutos.

  sudo bash $0 --ejecutar --acepto-perdida-de-datos

Escribe y borra su propio fichero de imagen; mata solo los cryptsetup que trabajan sobre él. Si se interrumpe y queda
algo, use cifrado-limpiar-prueba.sh. Sin argumentos: muestra esta ayuda y sale.
EOF
}
leer_opciones "$@"
(( ${#OTRAS[@]} == 0 )) || { echo "Opción desconocida: ${OTRAS[*]}" >&2; ayuda; exit 2; }
if [[ -n $AYUDA || ( -z $EJECUTAR && -z $ACEPTO ) ]]; then ayuda; exit 0; fi
exigir_banderas
exigir_root
exec </dev/null
CON_CONF=; [[ -r $CONF ]] && { cargar_conf; CON_CONF=1; }
LOGDIR=${LOGDIR:-$BASE/registros}
[[ -e $W ]] && { echo "${R}ERROR:${N} ya existe $W (restos de otra prueba). Ejecute antes cifrado-limpiar-prueba.sh." >&2; exit 1; }
libre=$(df --output=avail -B1M /var/tmp | tail -1)
(( libre > TAM_MIB + 1024 )) || { echo "${R}ERROR:${N} hacen falta $((TAM_MIB + 1024)) MiB libres en /var/tmp (hay $libre)." >&2; exit 1; }
confirmar_riesgo "prueba" "crear, cifrar y borrar una imagen de prueba de $((TAM_MIB / 1024)) GiB en $W (el disco real no se toca)"
iniciar_log "cifrado-prueba-loop"
UUID_PRUEBA=$(cat /proc/sys/kernel/random/uuid)
LOOP=; FALLOS=0; T0=$(date +%s)
t()   { echo; echo "======== $* [$(date +%T), $(( $(date +%s) - T0 )) s desde el inicio] ========"; }
CSP() { cryptsetup --batch-mode "$@"; }   # nunca pregunta (stdin ya es /dev/null)

limpiar() {
  local c
  for c in $(pgrep -x cryptsetup); do grep -qa -- "$W" "/proc/$c/cmdline" 2>/dev/null && kill -9 "$c"; done
  mountpoint -q "$PMNT" 2>/dev/null && umount "$PMNT"
  [[ -e /dev/mapper/$NOMBRE ]] && cryptsetup close "$NOMBRE"
  [[ -n $LOOP ]] && losetup -d "$LOOP" 2>/dev/null
  [[ -f $K ]] && shred -u "$K"
  cd / && rm -rf --one-file-system "${W:?}"
  echo "#### Limpieza hecha: $(losetup -j "$IMG" 2>/dev/null | wc -l) loop(s) del fichero, $([[ -e $W ]] && echo 'QUEDA' || echo 'sin') directorio"
}
trap limpiar EXIT
trap 'echo "## Interrumpido"; exit 130' INT TERM

guardia() { [[ -n $LOOP && $LOOP == /dev/loop* && $(losetup -n -O BACK-FILE "$LOOP") == "$IMG" ]] || { echo "ERROR: el loop no es el de la prueba" >&2; exit 1; }; }
temporal() { local f; f=$(ls -1 "$W"/LUKS2-temp-*.new 2>/dev/null | head -1); [[ -n $f ]] && echo "${f##*/} ($(stat -c %s "$f") bytes)" || echo "ninguna"; }
# Lo que pasaría tras un apagón: no queda ningún cryptsetup, ni mapeo, ni bloqueo sin dueño, ni cabecera temporal
apagon() {
  local c f
  for c in $(pgrep -x cryptsetup); do grep -qa -- "$W" "/proc/$c/cmdline" 2>/dev/null && { echo "     apagón: mata cryptsetup $c"; kill -9 "$c"; }; done
  mountpoint -q "$PMNT" && umount "$PMNT"; [[ -e /dev/mapper/$NOMBRE ]] && cryptsetup close "$NOMBRE"
  f="/run/cryptsetup/L_$(lsblk -dno MAJ:MIN "$LOOP" | tr -d ' ')"
  if [[ -e $f ]]; then   # solo el bloqueo de NUESTRO loop
    if flock -n "$f" true; then rm -f "$f"; echo "     apagón: bloqueo sin dueño ${f##*/} quitado"; else echo "     !! bloqueo ${f##*/} en uso"; fi
  fi
  for f in "$W"/LUKS2-temp-*.new; do [[ -e $f ]] && { echo "     apagón: se pierde la cabecera temporal ${f##*/} ($(stat -c %s "$f") bytes)"; rm -f "$f"; }; done
  return 0
}
preparar() {   # btrfs nuevo con datos y sumas, reducido 256 MiB y desmontado
  guardia; apagon >/dev/null
  wipefs -qa "$LOOP"; mkfs.btrfs -q -f -L prueba "$LOOP" || return 1
  mount -o compress=zstd:1 "$LOOP" "$PMNT" || return 1
  btrfs subvolume create "$PMNT/@" >/dev/null; btrfs subvolume create "$PMNT/@home" >/dev/null
  head -c "${1:-1024}M" /dev/urandom > "$PMNT/@/aleatorio.bin"; cp -r /usr/share/doc "$PMNT/@home/doc" 2>/dev/null
  btrfs subvolume snapshot -r "$PMNT/@" "$PMNT/@-instantanea" >/dev/null
  (cd "$PMNT" && find . -type f -print0 | sort -z | xargs -0 sha256sum) > "$W/sumas.antes"
  btrfs filesystem resize -256M "$PMNT" >/dev/null; sync; umount "$PMNT"
}
verificar() {  # sumas, btrfs check e instantánea en $1
  timeout 300 btrfs check --readonly "$1" >/dev/null 2>&1 || { echo "     btrfs check con errores"; return 1; }
  mount -o ro "$1" "$PMNT" || { echo "     no monta"; return 1; }
  (cd "$PMNT" && find . -type f -print0 | sort -z | xargs -0 sha256sum) > "$W/sumas.ahora"; umount "$PMNT"
  cmp -s "$W/sumas.antes" "$W/sumas.ahora" || { echo "     sumas distintas"; return 1; }
}
dump() { CSP luksDump "$LOOP" 2>/dev/null; }   # a variable antes de buscar: «| grep -q» con pipefail puede mentir
completo() { local d; CSP isLuks "$LOOP" || return 1; d=$(dump); [[ $d != *online-reencrypt* ]]; }
pct() { grep -o '"device_bytes":"[0-9]*","device_size":"[0-9]*"' "$1" | tail -1 | tr -dc '0-9,' | awk -F, '$2>0{printf "%d", $1*100/$2}'; }
ARGS_CIFRAR=(reencrypt --encrypt --type luks2 --cipher aes-xts-plain64 --key-size 512 --hash sha256 --pbkdf argon2id
             --reduce-device-size 32M --uuid "$UUID_PRUEBA" --key-file "$K")

echo "#### cryptsetup $(cryptsetup --version | awk '{print $2}') · btrfs-progs $(btrfs --version | awk '{print $2}') · $(uname -r)"
install -d -m 700 "$W" "$PMNT"; cd "$W" || exit 1     # cryptsetup deja aquí su cabecera temporal
printf '%s' "clave desechable solo para esta imagen de prueba" > "$K"; chmod 400 "$K"
truncate -s 0 "$IMG"; chattr +C "$IMG" 2>/dev/null; fallocate -l "${TAM_MIB}M" "$IMG"
LOOP=$(losetup --find --show --direct-io=on "$IMG"); guardia
ok "imagen de $((TAM_MIB / 1024)) GiB en $LOOP ($IMG)"

t "A. Cifrado completo"
preparar 1500 && ok "btrfs con $(wc -l < "$W/sumas.antes") ficheros, subvolúmenes e instantánea; reducido 256 MiB"
UUID_BTRFS=$(blkid -s UUID -o value "$LOOP")
ini=$(date +%s%N)
con_tiempo 600 "reencrypt --encrypt" cryptsetup --batch-mode "${ARGS_CIFRAR[@]}" --progress-frequency 3 "$LOOP" \
  || { mal "el cifrado de A falló: PRUEBA INVÁLIDA, se para aquí"; exit 1; }
seg=$(( ($(date +%s%N) - ini) / 1000000 )); VEL=$(( TAM_MIB * 1000 / (seg > 0 ? seg : 1) ))
ok "${TAM_MIB} MiB en $((seg / 1000)),$(( (seg % 1000) / 100 )) s → ${VEL} MiB/s; cabecera temporal al terminar: $(temporal)"
completo && ok "LUKS2 completo (sin reencriptado pendiente)" || mal "queda reencriptado pendiente"
[[ $(CSP luksUUID "$LOOP") == "$UUID_PRUEBA" ]] && ok "UUID de LUKS fijado" || mal "UUID de LUKS distinto"
CSP luksDump "$LOOP" | grep -E "^Version|cipher:|sector:|offset:|PBKDF:" | sort -u | sed 's/^/  /'
CSP open --allow-discards --persistent --key-file "$K" "$LOOP" "$NOMBRE"
[[ $(dump) == *allow-discards* ]] && ok "allow-discards guardado en la cabecera" || mal "allow-discards no persistente"
[[ $(blkid -s UUID -o value /dev/mapper/$NOMBRE) == "$UUID_BTRFS" ]] && ok "el btrfs conserva su UUID dentro de LUKS (fstab no cambia)" || mal "UUID del btrfs distinto"
verificar /dev/mapper/$NOMBRE && ok "sumas, btrfs check e instantánea correctos tras cifrar" || mal "datos dañados tras cifrar"
mount /dev/mapper/$NOMBRE "$PMNT"; a=$(btrfs filesystem show --raw "$PMNT" | awk '/devid/{print $4}')
btrfs filesystem resize max "$PMNT" >/dev/null; b=$(btrfs filesystem show --raw "$PMNT" | awk '/devid/{print $4}')
ok "btrfs crecido: $a → $b bytes (LUKS: $(blockdev --getsize64 /dev/mapper/$NOMBRE))"
timeout 600 btrfs scrub start -B "$PMNT" 2>&1 | grep -E "Error summary" | sed 's/^/  /'

t "B. Huecos y cabecera"
head -c 64 /dev/urandom > "$W/clave.home"; chmod 400 "$W/clave.home"
CSP luksAddKey --key-file "$K" "$LOOP" "$W/clave.home" && CSP open --test-passphrase --key-file "$W/clave.home" "$LOOP" \
  && ok "fichero de clave añadido y abre" || mal "fichero de clave"
# Clave de recuperación de prueba con el mismo formato que las de systemd-cryptenroll, generada al azar
tr -dc 'cbdefghijklnrtuv' </dev/urandom | head -c 64 | sed -E 's/(.{8})/\1-/g; s/-$//' | tr -d '\n' > "$W/rec.key"; chmod 400 "$W/rec.key"
CSP luksAddKey --key-file "$W/clave.home" "$LOOP" "$W/rec.key" && CSP open --test-passphrase --key-file "$W/rec.key" "$LOOP" \
  && ok "clave de recuperación añadida y abre" || mal "clave de recuperación"
CSP open --test-passphrase --key-file "$K" "$LOOP" && ok "la frase sigue abriendo" || mal "la frase ya no abre"
echo "  huecos ocupados: $(CSP luksDump "$LOOP" | grep -cE '^\s+[0-9]+: luks2')"
CSP luksHeaderBackup "$LOOP" --header-backup-file "$W/cabecera.img" && ok "cabecera exportada: $(stat -c %s "$W/cabecera.img") bytes"
umount "$PMNT"; CSP close "$NOMBRE"

PUNTOS=(0.2s 0.6s 1.2s 2.5s 3s 3.5s 4s 5s 6s 8s 25% 50% 90%)
t "C. Cortes con kill -9 en ${#PUNTOS[@]} puntos"
declare -A RES; n=0
for punto in "${PUNTOS[@]}"; do
  n=$((n + 1)); ic=$(date +%s)
  echo; echo "  ==== CORTE $n/${#PUNTOS[@]} en $punto — empieza $(date +%T) ===="
  preparar 1024 || { mal "no se pudo preparar el btrfs"; RES[$punto]="FALLO (preparar)"; continue; }
  echo "     btrfs preparado en $(( $(date +%s) - ic )) s"
  P="$W/progreso.json"; : > "$P"; guardia
  timeout -k 5 300 cryptsetup --batch-mode "${ARGS_CIFRAR[@]}" --progress-json --progress-frequency 1 "$LOOP" > "$P" 2>&1 &
  cpid=$!
  if [[ $punto == *s ]]; then sleep "${punto%s}"
  else
    obj=${punto%\%}
    while kill -0 "$cpid" 2>/dev/null; do
      pc=$(pct "$P"); [[ -n $pc && $pc -ge $obj ]] && break; sleep 0.2
    done
  fi
  # cpid es el timeout; el cryptsetup es su hijo
  csp=$(pgrep -P "$cpid" -x cryptsetup || true)
  if [[ -n $csp ]] && kill -0 "$csp" 2>/dev/null; then
    kill -9 "$csp"; wait "$cpid" 2>/dev/null
    pc=$(pct "$P")
    echo "     CORTADO a los $(( $(date +%s) - ic )) s del inicio del corte; progreso: ${pc:-sin informe aún} %; cabecera temporal: $(temporal)"
  else
    wait "$cpid"; rc=$?
    if [[ $rc -ne 0 ]]; then mal "corte $punto: cryptsetup acabó con error $rc antes del corte: $(grep -v device_bytes "$P" | tail -2 | paste -sd' ')"; RES[$punto]="FALLO (error $rc)"
    else echo "     terminó antes del corte (no cuenta)"; RES[$punto]="no cortado"; fi
    continue
  fi
  apagon
  if CSP isLuks "$LOOP" 2>/dev/null; then
    echo "     estado: LUKS2 $([[ $(dump) == *online-reencrypt* ]] && echo 'con reencriptado a medias' || echo 'completo')"
    con_tiempo 120 "repair" cryptsetup --batch-mode repair --key-file "$K" "$LOOP"
    con_tiempo 300 "reencrypt --resume-only" cryptsetup --batch-mode reencrypt --resume-only --key-file "$K" "$LOOP"
    camino="LUKS reanudado"
  else
    echo "     estado: aún NO es LUKS (blkid: $(blkid -p -s TYPE -o value "$LOOP" 2>/dev/null || echo nada))"
    if verificar "$LOOP"; then
      echo "     btrfs en claro intacto → se repite el cifrado"
      con_tiempo 300 "reencrypt --encrypt (repetido)" cryptsetup --batch-mode "${ARGS_CIFRAR[@]}" "$LOOP"
      camino="sin cabecera aún; repetido"
    else camino="IRRECUPERABLE"; fi
  fi
  if [[ $camino != IRRECUPERABLE ]] && completo && CSP open --key-file "$K" "$LOOP" "$NOMBRE" && verificar /dev/mapper/$NOMBRE; then
    ok "corte $punto: RECUPERADO Y TERMINADO ($camino; cifrado completo; sumas correctas) en $(( $(date +%s) - ic )) s"; RES[$punto]="$camino → OK"
  else
    mal "corte $punto: NO recuperado ($camino)"; RES[$punto]="FALLO ($camino)"
    CSP luksDump "$LOOP" 2>/dev/null | grep -iE "Requirements|reencrypt" | head -3 | sed 's/^/       /'
  fi
  [[ -e /dev/mapper/$NOMBRE ]] && CSP close "$NOMBRE"
done

t "D. Marcha atrás: descifrar en el sitio"
if preparar 1024 && con_tiempo 300 "cifrar para descifrar" cryptsetup --batch-mode "${ARGS_CIFRAR[@]}" "$LOOP" && completo; then
  # --header debe ser un fichero que NO exista: cryptsetup exporta ahí la cabecera original
  con_tiempo 600 "reencrypt --decrypt" cryptsetup --batch-mode reencrypt --decrypt --header "$W/descifrar.img" --key-file "$K" "$LOOP"
  ! CSP isLuks "$LOOP" 2>/dev/null && verificar "$LOOP" && ok "descifrado: ya no es LUKS; btrfs en claro con sumas correctas" || mal "tras descifrar, datos dañados o sigue siendo LUKS"
else mal "D: no se pudo cifrar el btrfs de partida"; fi

t "E. Tiempos estimados (a ${VEL} MiB/s, toda la partición, también el espacio libre)"
if [[ -n $CON_CONF ]]; then
  for p in RAIZ HOME; do
    by=${p}_BYTES; m=$(( ${!by} / 1048576 ))
    echo "  $p: $((m / 1024)) GiB → unos $(( m / VEL / 60 + 1 )) min (ponga en MAX_$p al menos $(( (m / VEL + 60) * 3 )) s)"
  done
else echo "  (sin cifrado.conf: no se estiman las particiones reales)"; fi

t "Resumen de los cortes"
for punto in "${PUNTOS[@]}"; do printf '  %-5s %s\n' "$punto" "${RES[$punto]:-?}"; done
echo; [[ $FALLOS -eq 0 ]] && echo "#### PRUEBA: TODO CORRECTO" || echo "#### PRUEBA: $FALLOS FALLO(S)"
