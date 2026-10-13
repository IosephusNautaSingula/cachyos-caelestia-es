#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# cifrado-comun.sh — funciones comunes de los scripts de «cifrado en el sitio» (LUKS2 + TPM2 + PIN, btrfs, Limine).
# Se carga con «source» desde los demás scripts; no hace nada por sí solo. Al cargarlo NO se lee cifrado.conf ni se
# toca nada: eso lo hace cada script con «cargar_conf» después de comprobar sus argumentos.
#
# Reglas (aprendidas en pruebas con imágenes y cortes de luz simulados):
#  · cryptsetup SIEMPRE con --batch-mode y la clave por --key-file; stdin desde /dev/null en todo. Las únicas lecturas
#    del teclado son las confirmaciones, las pausas y la frase, siempre desde /dev/tty.
#  · Cada paso largo tiene un tiempo máximo (nunca se queda esperando sin decirlo).
#  · El directorio de trabajo (donde cryptsetup deja LUKS2-temp-<UUID>.new) está en el USB o la ESP, nunca en lo que
#    se cifra, y sobrevive a un corte.
#  · Frases, PIN y claves de recuperación: solo en RAM (/run), nunca en pantalla salvo la clave de recuperación recién
#    generada (y entonces solo a /dev/tty, fuera del registro), y se borran al salir.

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  echo "cifrado-comun.sh: funciones comunes; no se ejecuta, lo cargan los demás scripts cifrado-*.sh."
  echo "Vea README.md para el orden de uso."
  exit 0
fi

BASE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CONF=${CIFRADO_CONF:-$BASE/cifrado.conf}
GUIA="guias/cifrado-luks2-tpm2-limine.md"
S=/run/estacion-cifrado                     # RAM: se borra al salir y se pierde con un corte (se vuelve a pedir)
FRASE=$S/frase
MNT=/mnt/estacion-cifrado; MNT_BRUTO=/mnt/estacion-cifrado-btrfs; MNT_RED=/mnt/estacion-cifrado-red
FALLOS=0; LOG=/dev/null
EJECUTAR=; ACEPTO=; AYUDA=; OTRAS=()
R=$'\e[1;31m'; A=$'\e[1;33m'; V=$'\e[1;32m'; N=$'\e[0m'

# ---------- argumentos y salvaguardas ----------
# leer_opciones "$@": reconoce --ejecutar, --acepto-perdida-de-datos y -h/--ayuda; el resto queda en OTRAS.
leer_opciones() {
  local a
  for a in "$@"; do
    case $a in
      --ejecutar) EJECUTAR=1;;
      --acepto-perdida-de-datos) ACEPTO=1;;
      -h|--help|--ayuda) AYUDA=1;;
      *) OTRAS+=("$a");;
    esac
  done
}
# exigir_banderas: el modo real necesita LAS DOS banderas. No pregunta nada; sale si faltan.
exigir_banderas() {
  if [[ -z $EJECUTAR || -z $ACEPTO ]]; then
    echo "${R}No se ha hecho nada.${N} Para el modo real hacen falta, a la vez, --ejecutar y --acepto-perdida-de-datos." >&2
    echo "Lea antes la ayuda (sin argumentos) y la guía $GUIA." >&2
    exit 2
  fi
}
exigir_root() { [[ $EUID -eq 0 ]] || { echo "${R}ERROR:${N} hay que ejecutarlo como root:  sudo bash $0 $*" >&2; exit 1; }; }
hay_terminal() { ( : </dev/tty ) 2>/dev/null; }
# corriente_ok: verdadero si no hay batería o si hay un cargador conectado
corriente_ok() {
  local p t bat=0 ac=0
  for p in /sys/class/power_supply/*; do
    [[ -e $p/type ]] || continue
    t=$(cat "$p/type" 2>/dev/null)
    [[ $t == Battery ]] && bat=1
    [[ ($t == Mains || $t == USB) && $(cat "$p/online" 2>/dev/null) == 1 ]] && ac=1
  done
  (( bat == 0 || ac == 1 ))
}
# confirmar_riesgo PALABRA "qué se va a hacer": aviso en mayúsculas y confirmación tecleada desde /dev/tty.
confirmar_riesgo() {
  local palabra=$1 que=$2 r
  hay_terminal || { echo "${R}ERROR:${N} hace falta un terminal para confirmar. No se ha hecho nada." >&2; exit 1; }
  corriente_ok || { echo "${R}ERROR:${N} el equipo funciona con batería. Conecte el cargador y repita. No se ha hecho nada." >&2; exit 1; }
  {
    echo
    echo "${R}╔════════════════════════════════════════════════════════════════════════════╗"
    echo "║  ATENCIÓN: RIESGO DE PÉRDIDA TOTAL DE DATOS                                ║"
    echo "╚════════════════════════════════════════════════════════════════════════════╝${N}"
    echo "${R}  ESTE SCRIPT VA A ESCRIBIR EN EL DISCO: ${que^^}.${N}"
    echo "${R}  UN ERROR, UN FALLO DE HARDWARE O UN CORTE MAL RECUPERADO PUEDEN DEJAR TODOS LOS DATOS ILEGIBLES.${N}"
    echo "${A}  · ES IMPRESCINDIBLE TENER UNA COPIA DE SEGURIDAD COMPLETA Y COMPROBADA (RESTAURADA DE PRUEBA) FUERA DE ESTE DISCO.${N}"
    echo "${A}  · DEBE HABER PASADO ANTES EL MODO DE PRUEBA (--prueba) SIN NINGUNA LÍNEA «MAL».${N}"
    echo "${A}  · EL CARGADOR DEBE ESTAR CONECTADO TODO EL TIEMPO. NO CIERRE LA TAPA NI APAGUE.${N}"
    echo "${A}  · TENGA A MANO LA FRASE EN SU GESTOR DE CONTRASEÑAS (EN OTRO DISPOSITIVO).${N}"
    echo "  Guía: $GUIA"
    echo
  } >/dev/tty
  read -r -p "  Para confirmar, escriba exactamente «$palabra» y pulse Intro (cualquier otra cosa cancela): " r </dev/tty
  [[ $r == "$palabra" ]] || { echo "  Cancelado. No se ha hecho nada." >/dev/tty; exit 1; }
  echo "  (confirmado: $palabra)"
}

# ---------- configuración ----------
dev_de() { readlink -f "/dev/disk/by-partuuid/$1" 2>/dev/null; }
disco_de() { local p; p=$(lsblk -dno PKNAME "$1" 2>/dev/null | head -1); [[ -n $p ]] && echo "/dev/$p"; }
cargar_conf() {
  local v falta=()
  [[ -r $CONF ]] || { echo "${R}ERROR:${N} falta $CONF. Copie cifrado.conf.example como cifrado.conf y rellénelo (cifrado-inventario.sh --conf le propone los valores)." >&2; exit 1; }
  # cifrado.conf se carga con «source» (lleva listas): antes se comprueba que nadie más haya podido cambiarlo.
  # En un sistema de ficheros con permisos: de root (o suyo) y sin escritura para otros. En exFAT/vfat (USB, ESP),
  # que no guardan permisos: tiene que coincidir con SHA256SUMS (que cifrado-copiar.sh genera y usted compara con la
  # suma que guardó). Si no, no se carga.
  local fs dueno modo
  fs=$(stat -f -c %T "$CONF" 2>/dev/null)
  case $fs in
    msdos|vfat|exfat|fuseblk)
      ( cd "$(dirname "$CONF")" && grep -E "[[:space:]](\./)?$(basename "$CONF")\$" SHA256SUMS 2>/dev/null | sha256sum --quiet -c - ) >/dev/null 2>&1 \
        || { echo "${R}ERROR:${N} $CONF está en $fs (sin permisos) y no coincide con SHA256SUMS: no se carga." >&2; exit 1; } ;;
    *)
      read -r dueno modo < <(stat -c '%u %a' "$CONF")
      if [[ $dueno != 0 && $dueno != "$EUID" ]] || (( 8#$modo & 8#022 )); then
        echo "${R}ERROR:${N} $CONF no es de root ni suyo, o lo pueden escribir otros: no se carga." >&2; exit 1
      fi ;;
  esac
  # shellcheck source=cifrado.conf.example
  source "$CONF"
  for v in DISCO DISCO_SERIE ESP_PARTUUID ESP_UUID RAIZ_PARTUUID RAIZ_BYTES RAIZ_BTRFS RAIZ_LUKS RAIZ_MAP \
           HOME_PARTUUID HOME_BYTES HOME_BTRFS HOME_LUKS HOME_MAP CLAVE_HOME REDUCIR_BTRFS MAX_RAIZ MAX_HOME; do
    [[ -n ${!v:-} ]] || falta+=("$v")
  done
  [[ $(declare -p CIFRADO 2>/dev/null) == "declare -a"* ]] || falta+=(CIFRADO)
  (( ${#falta[@]} == 0 )) || { echo "${R}ERROR:${N} en $CONF faltan: ${falta[*]}" >&2; exit 1; }
  for v in ESP_PARTUUID RAIZ_PARTUUID RAIZ_BTRFS RAIZ_LUKS HOME_PARTUUID HOME_BTRFS HOME_LUKS; do
    [[ ${!v} == 11111111-2222-3333-4444-* ]] && { echo "${R}ERROR:${N} $CONF aún tiene valores de EJEMPLO ($v). Rellénelo con los de su equipo." >&2; exit 1; }
  done
  [[ $RAIZ_LUKS != "$HOME_LUKS" ]] || { echo "${R}ERROR:${N} RAIZ_LUKS y HOME_LUKS deben ser distintos." >&2; exit 1; }
  : "${EQUIPO:=}" "${USUARIO:=}" "${DISCO_MODELO:=}" "${ESP_MONTAJE:=/boot}" "${LIMINE_CONF:=/boot/limine.conf}"
  : "${KERNELS:=linux-cachyos linux-cachyos-lts}" "${RAIZ_SUBVOL:=@}" "${OPCIONES_BTRFS:=compress=zstd:1}"
  : "${SUBVOLUMENES_RAIZ:=}" "${FRASE_PALABRAS:=6}" "${PIN_MIN:=6}" "${TPM_PCRS:=7}" "${DIR_TPM_REFERENCIA:=/var/lib/estacion-tpm}"
  : "${USB_ETIQUETA:=}" "${USB_SERIE:=}" "${DIR_EN_USB:=estacion-cifrado}" "${VENTOY_JSON:=}"
  : "${DIR_REGISTROS:=}" "${DIR_TRABAJO:=}" "${COPIA_CERROJO:=/run/estacion-copia.lock}"
  : "${DIR_CABECERAS:=/var/lib/estacion-copia/sistema/luks}" "${COPIA_NAS:=}" "${COPIA_PUERTO:=445}" "${COPIA_RECURSO:=}"
  : "${COPIA_CREDENCIALES:=}" "${COPIA_OPCIONES_CIFS:=vers=3.1.1,seal,uid=0,gid=0,file_mode=0600,dir_mode=0700,noperm}"
  : "${COPIA_SUBDIR:=reconstruir/cifrado}" "${SNAPPER_CONFIGS:=}"
  [[ $(declare -p COPIA_AHORA 2>/dev/null) == "declare -a"* ]] || COPIA_AHORA=()
  [[ $(declare -p COPIA_COMPROBAR 2>/dev/null) == "declare -a"* ]] || COPIA_COMPROBAR=()
  [[ $(declare -p COPIA_RESTIC 2>/dev/null) == "declare -a"* ]] || COPIA_RESTIC=()
  [[ $(declare -p COPIA_EXCLUIR 2>/dev/null) == "declare -a"* ]] || COPIA_EXCLUIR=()
  LOGDIR=${DIR_REGISTROS:-$BASE/registros}
  TRABAJO=${DIR_TRABAJO:-$BASE/trabajo}
  DISCO=$(readlink -f "$DISCO")
  RAIZ_DEV=$(dev_de "$RAIZ_PARTUUID"); HOME_DEV=$(dev_de "$HOME_PARTUUID"); ESP_DEV=$(dev_de "$ESP_PARTUUID")
}

# ---------- registro y pantalla ----------
iniciar_log() {   # $1 = nombre. Un registro por ejecución (0600). Nunca se escriben en él frases, PIN ni claves.
  local d=${LOGDIR:-$BASE/registros}
  (umask 077; install -d "$d") 2>/dev/null || { echo "${R}ERROR: no puedo escribir en $d${N}" >&2; exit 1; }
  LOG="$d/$1-$(date +%Y%m%d-%H%M%S).log"
  (umask 077; : > "$LOG") || { echo "${R}ERROR: no puedo crear $LOG${N}" >&2; exit 1; }
  [[ -n ${SUDO_USER:-} && $SUDO_USER != root ]] && chown "$SUDO_USER:" "$LOG" 2>/dev/null
  exec > >(trap '' INT TERM QUIT TSTP; exec tee -a "$LOG") 2>&1   # el registro sigue aunque se pulse Ctrl+C
  echo "#### $(date '+%F %T') · $* · $(uname -r) · cryptsetup $(cryptsetup --version 2>/dev/null | awk '{print $2}')"
  echo "#### Registro: $LOG"
}
ok()    { echo "  ${V}OK${N}   $*"; }
aviso() { echo "  ${A}!!${N}   $*"; }
mal()   { echo "  ${R}MAL${N}  $*"; FALLOS=$((FALLOS + 1)); }
paso()  { sync; echo; echo "${A}======== $* [$(date +%T)] ========${N}"; }
# para "motivo": parada simple (scripts del sistema instalado)
para()  { echo; echo "${R}#### PARADO: $*${N}"; echo "  Guía: $GUIA · Registro: $LOG"; exit 1; }
# falla "qué ha pasado" "qué hacer" "apartado de la guía": parada con instrucciones (entorno live)
falla() {
  sync
  echo; echo "${R}╔══════════════════════════════════════════════════════════════════════╗"
  echo "║  PARADO. NO apague el equipo todavía.                                ║"
  echo "╚══════════════════════════════════════════════════════════════════════╝${N}"
  echo "${R}Qué ha pasado:${N} $1"
  echo "${A}Qué hacer:${N}     $2"
  echo "${A}Guía:${N}          $GUIA, apartado «$3»"
  echo "Registro:      $LOG"
  sync; exit 1
}
# con_tiempo SEGUNDOS "descripción" orden…
con_tiempo() {
  local max=$1 desc=$2; shift 2; local ini rc; ini=$(date +%s)
  echo "     → $desc (empieza $(date +%T); máximo $((max / 60)) min)"
  timeout -k 30 "$max" "$@" </dev/null; rc=$?
  [[ $rc -eq 124 || $rc -eq 137 ]] && echo "     ${R}!! TIEMPO MÁXIMO AGOTADO en «$desc»${N}"
  echo "     ← $desc: código $rc, $(( ($(date +%s) - ini) / 60 )) min $(( ($(date +%s) - ini) % 60 )) s"
  sync; return $rc
}
CS() { cryptsetup --batch-mode "$@" </dev/null; }
# Metadatos LUKS en JSON, sin nada por pantalla (luksDump normal muestra datos de los tokens)
meta() { cryptsetup luksDump --dump-json-metadata "$1" </dev/null 2>/dev/null; }
borrar_secretos() { local f; for f in "$S"/*; do [[ -f $f ]] && { shred -u "$f" 2>/dev/null || rm -f "$f"; }; done; return 0; }

# Pausa prevista: solo continúa si se teclea exactamente la palabra; «no» sale sin cambiar nada más.
pausa() {   # $1 = texto, $2 = palabra
  local r
  while :; do
    echo; echo "${A}>>> $1${N}"
    read -r -p "    Escriba «$2» y pulse Intro para seguir (o «no» para salir): " r </dev/tty
    [[ $r == "$2" ]] && { echo "    (respuesta: $2)"; return 0; }
    [[ $r == no ]] && { echo "    Salida a petición del usuario. No se ha cambiado nada más."; exit 0; }
    echo "    No es «$2». Otra vez."
  done
}

# ---------- frase ----------
# guardar_secreto FICHERO VALOR: a RAM, 0400, sin salto de línea
guardar_secreto() { install -d -m 700 "$S"; (umask 077; printf '%s' "$2" > "$1"); chmod 400 "$1"; }
# pedir_frase [dispositivo-LUKS-para-comprobar] [libre]: la teclea dos veces (no se ve), solo a RAM.
# Con «libre» (rescate) acepta también la clave de recuperación: se teclea una vez y se comprueba con el disco.
pedir_frase() {
  local f1 f2 i n=$((FRASE_PALABRAS - 1))
  install -d -m 700 "$S"
  if [[ ${2:-} == libre ]]; then
    for i in 1 2 3; do
      echo; echo "${A}>>> Teclee la FRASE o la CLAVE DE RECUPERACIÓN (la de su gestor de contraseñas, con sus guiones)."
      echo "    No se ve nada al teclear.${N}"
      read -r -s -p "    Frase o clave: " f1 </dev/tty; echo
      guardar_secreto "$FRASE" "$f1"; f1=
      CS open --test-passphrase --key-file "$FRASE" "$1" && { ok "abre $1"; return 0; }
      echo "    ${R}No abre $1. Otra vez.${N}"; rm -f "$FRASE"
    done
    falla "ni la frase ni la clave de recuperación abrieron $1 en 3 intentos" "Compruébelas en su gestor de contraseñas y vuelva a ejecutar." "Si la frase no entra"
  fi
  for i in 1 2 3; do
    echo
    echo "${A}>>> Teclee la FRASE de LUKS (la de su gestor de contraseñas): $FRASE_PALABRAS palabras o más, en minúsculas"
    echo "    (a-z), separadas por un espacio. No se ve nada al teclear; es normal.${N}"
    read -r -s -p "    Frase: " f1 </dev/tty; echo
    read -r -s -p "    Repítala: " f2 </dev/tty; echo
    if [[ $f1 != "$f2" ]]; then echo "    ${R}No coinciden. Otra vez.${N}"; f1=; f2=; continue; fi
    if [[ ! $f1 =~ ^[a-z]+(\ [a-z]+){$n,}$ ]]; then
      echo "    ${R}No son $FRASE_PALABRAS palabras o más en minúsculas (a-z) con un solo espacio entre ellas (sin espacios al principio ni al final). Otra vez.${N}"
      f1=; f2=; continue
    fi
    guardar_secreto "$FRASE" "$f1"; f1=; f2=
    if [[ -n ${1:-} ]] && CS isLuks "$1"; then
      if CS open --test-passphrase --key-file "$FRASE" "$1"; then ok "la frase abre $1"; return 0
      else echo "    ${R}Esa frase NO abre $1. Compruébela en su gestor de contraseñas. Otra vez.${N}"; rm -f "$FRASE"; continue; fi
    fi
    ok "frase tecleada dos veces igual (guardada solo en RAM)"; return 0
  done
  falla "la frase no se pudo confirmar en 3 intentos" "Compruebe la frase y vuelva a ejecutar el mismo script." "Si la frase no entra"
}
borrar_frase() { [[ -f $FRASE ]] && { shred -u "$FRASE" 2>/dev/null || rm -f "$FRASE"; }; return 0; }
# pedir_frase_sistema DEV...: en el sistema instalado, una vez, comprobada contra todos los DEV
pedir_frase_sistema() {
  local i fr d bien
  for i in 1 2 3; do
    read -r -s -p "  Teclee la FRASE de LUKS (no se ve) y pulse Intro: " fr </dev/tty; echo
    guardar_secreto "$FRASE" "$fr"; fr=; bien=1
    for d in "$@"; do CS open --test-passphrase --key-file "$FRASE" "$d" >/dev/null 2>&1 || bien=; done
    [[ -n $bien ]] && { ok "la frase abre: $*"; return 0; }
    echo "  ${R}No abre todo lo necesario. Otra vez.${N}"; shred -u "$FRASE" 2>/dev/null
  done
  para "la frase no se pudo comprobar"
}
# pedir_pin FICHERO: PIN nuevo dos veces; solo a RAM. Letras sin tilde ni ñ y números (mismas teclas en los teclados
# español e inglés: en la pantalla de arranque se teclea igual).
pedir_pin() {
  local p1 p2 d i
  echo "  PIN: $PIN_MIN caracteres o más; solo letras SIN tilde ni ñ (mayúsculas o minúsculas) y números; ni espacios ni símbolos."
  for i in 1 2 3 4 5; do
    read -r -s -p "  PIN nuevo: " p1 </dev/tty; echo
    read -r -s -p "  Repítalo:  " p2 </dev/tty; echo
    if [[ $p1 != "$p2" ]]; then echo "  ${R}No coinciden.${N}"; continue; fi
    if (( ${#p1} < PIN_MIN )); then echo "  ${R}Tiene menos de $PIN_MIN caracteres.${N}"; continue; fi
    if [[ ! $p1 =~ ^[A-Za-z0-9]+$ ]]; then echo "  ${R}Solo letras sin tilde ni ñ y números.${N}"; continue; fi
    d=${p1:0:1}; [[ -z ${p1//"$d"/} ]] && { echo "  ${R}Es el mismo carácter repetido.${N}"; continue; }
    [[ 01234567890 == *"$p1"* || 09876543210 == *"$p1"* ]] && { echo "  ${R}Demasiado fácil (secuencia).${N}"; continue; }
    guardar_secreto "$1" "$p1"; p1=; p2=; ok "PIN tecleado dos veces igual (solo en RAM)"; return 0
  done
  p1=; p2=; return 1
}

# ---------- dispositivos ----------
# estado_de DEV BTRFS_UUID LUKS_UUID → claro | a-medias | cifrada | desconocido
estado_de() {
  local d=$1 b=$2 l=$3 dump
  if CS isLuks "$d" 2>/dev/null; then
    [[ $(CS luksUUID "$d") == "$l" ]] || { echo desconocido; return; }
    dump=$(CS luksDump "$d" 2>/dev/null)
    [[ $dump == *online-reencrypt* ]] && echo a-medias || echo cifrada
  elif [[ $(blkid -p -s TYPE -o value "$d" 2>/dev/null) == btrfs && $(blkid -p -s UUID -o value "$d" 2>/dev/null) == "$b" ]]; then
    echo claro
  else echo desconocido; fi
}
# comprobar_disco: disco, serie y particiones esperadas (solo lectura). Suma a FALLOS.
comprobar_disco() {
  local serie modelo p dv pu by tam
  serie=$(lsblk -dno SERIAL "$DISCO" 2>/dev/null | tr -d ' ')
  [[ -n $serie && $serie == "${DISCO_SERIE// /}" ]] && ok "disco $DISCO con la serie esperada" || mal "el disco $DISCO no tiene la serie de cifrado.conf"
  if [[ -n $DISCO_MODELO ]]; then
    modelo=$(lsblk -dno MODEL "$DISCO" 2>/dev/null | sed 's/ *$//')
    [[ $modelo == "$DISCO_MODELO" ]] && ok "modelo del disco esperado" || mal "el modelo del disco $DISCO no es el de cifrado.conf"
  fi
  for p in RAIZ HOME; do
    dv=${p}_DEV pu=${p}_PARTUUID by=${p}_BYTES
    [[ -b ${!dv} && $(disco_de "${!dv}") == "$DISCO" ]] && ok "$p: ${!dv} (PARTUUID de cifrado.conf, en $DISCO)" || mal "$p: el PARTUUID de cifrado.conf no está en $DISCO (${!dv:-no existe})"
    tam=$(blockdev --getsize64 "${!dv}" 2>/dev/null)
    [[ $tam == "${!by}" ]] && ok "$p: tamaño $tam bytes" || mal "$p: tamaño ${tam:-?} y se esperaba ${!by}"
  done
  [[ -b $ESP_DEV && $(disco_de "$ESP_DEV") == "$DISCO" && $(blkid -p -s UUID -o value "$ESP_DEV" 2>/dev/null) == "$ESP_UUID" ]] \
    && ok "ESP $ESP_DEV" || mal "no encuentro la ESP de cifrado.conf en $DISCO"
  [[ $RAIZ_DEV != "$HOME_DEV" && $RAIZ_DEV != "$ESP_DEV" && $HOME_DEV != "$ESP_DEV" ]] || mal "RAIZ, HOME y ESP deben ser particiones distintas"
}

# Comprobaciones del entorno live antes de tocar nada. Devuelve el número de problemas (0 = se puede seguir).
comprobar_entorno() {
  local p fuente fstipo estado v bat="" dv bt lu
  paso "Comprobaciones (no se escribe nada en el disco)"
  [[ $EUID -eq 0 ]] && ok "ejecutado como root" || mal "hay que ejecutarlo con sudo"
  # 1. Es un entorno live de CachyOS o Arch
  if [[ -d /run/archiso ]] || grep -q archisobasedir /proc/cmdline 2>/dev/null; then
    grep -qiE '^(ID|ID_LIKE)=.*(cachyos|arch)' /etc/os-release && ok "entorno live de CachyOS/Arch" || mal "es un entorno live, pero no de CachyOS ni Arch"
  else mal "NO es el entorno live (esto es el sistema instalado o no se reconoce el live)"; fi
  # 2. Corriente
  corriente_ok && ok "cargador conectado (o equipo sin batería)" || mal "SIN CARGADOR: enchúfelo"
  for p in /sys/class/power_supply/*; do [[ $(cat "$p/type" 2>/dev/null) == Battery ]] && bat=$(cat "$p/capacity" 2>/dev/null); done
  if [[ -n $bat ]]; then (( bat >= 30 )) && ok "batería al ${bat} %" || mal "batería al ${bat} %: espere a que pase del 30 %"; fi
  # 3. Herramientas
  v=$(cryptsetup --version 2>/dev/null | awk '{print $2}')
  [[ -n $v && $(printf '%s\n2.8.0\n' "$v" | sort -V | head -1) == 2.8.0 ]] && ok "cryptsetup $v" || mal "cryptsetup ${v:-ausente} (hace falta 2.8 o posterior)"
  for p in btrfs arch-chroot blkid blockdev timeout systemd-inhibit lsblk findmnt sha256sum; do
    command -v "$p" >/dev/null && ok "$p disponible" || mal "falta $p"
  done
  # 4. Dónde están los scripts y el trabajo: en el USB (o la ESP), nunca en lo que se cifra
  fuente=$(findmnt -n -o SOURCE -T "$BASE"); fstipo=$(findmnt -n -o FSTYPE -T "$BASE")
  if [[ ( -n $RAIZ_DEV && $fuente == "$RAIZ_DEV"* ) || ( -n $HOME_DEV && $fuente == "$HOME_DEV"* ) || $fuente == /dev/mapper/* ]]; then
    mal "los scripts están en una partición que se cifra ($fuente)"
  else
    [[ $fstipo == exfat || $fstipo == vfat ]] && ok "scripts y trabajo en $fuente ($fstipo)" || mal "scripts en $fuente ($fstipo): no es el USB ni la ESP"
  fi
  findmnt -n -o OPTIONS -T "$BASE" | grep -qw rw && ok "$BASE se puede escribir" || mal "$BASE está montado solo lectura"
  # 5. El disco y sus particiones son los esperados
  comprobar_disco
  # 6. Nada montado de lo que se va a cifrar
  for p in "$RAIZ_DEV" "$HOME_DEV" "/dev/mapper/$RAIZ_MAP" "/dev/mapper/$HOME_MAP"; do
    [[ -n $p && -e $p ]] || continue
    if findmnt -rn -S "$p" >/dev/null; then mal "$p está MONTADO en $(findmnt -rn -S "$p" -o TARGET | head -1)"; else ok "$p sin montar"; fi
  done
  # 7. Estado de cada partición
  for p in RAIZ HOME; do
    dv=${p}_DEV bt=${p}_BTRFS lu=${p}_LUKS
    estado=$(estado_de "${!dv}" "${!bt}" "${!lu}")
    case $estado in
      claro)    ok "$p: en claro (btrfs de cifrado.conf), sin cifrar todavía";;
      a-medias) aviso "$p: LUKS A MEDIO CIFRAR (se reanudará)";;
      cifrada)  ok "$p: ya cifrada (LUKS de cifrado.conf)";;
      *)        mal "$p: estado DESCONOCIDO (ni el btrfs ni el LUKS de cifrado.conf)";;
    esac
  done
  return $FALLOS
}

# ---------- una partición: de donde esté hasta cifrada, abierta y crecida ----------
# procesar NOMBRE (RAIZ|HOME)
procesar() {
  local P=$1; local dv=${P}_DEV bt=${P}_BTRFS lu=${P}_LUKS mp=${P}_MAP mx=MAX_${P} by=${P}_BYTES
  local D=${!dv} B=${!bt} L=${!lu} M=${!mp} MAXT=${!mx} OBJ=${!by} estado tam temp
  local REAN="sudo bash $BASE/cifrado-reanudar.sh --ejecutar --acepto-perdida-de-datos"
  paso "$P ($D)"
  estado=$(estado_de "$D" "$B" "$L"); echo "     estado: $estado"
  case $estado in
    claro)
      # Una cabecera temporal de un intento anterior cortado antes de escribir LUKS no sirve: se aparta
      for temp in "$TRABAJO"/LUKS2-temp-"$L".new; do
        [[ -e $temp ]] && { aviso "cabecera temporal de un intento anterior: se aparta (${temp##*/})"; mv "$temp" "$temp.descartada-$(date +%H%M%S)"; }
      done
      con_tiempo 1800 "btrfs check (solo lectura)" btrfs check --readonly "$D" \
        || falla "btrfs check encontró errores en $D (sin cifrar todavía; nada cambiado)" "No siga. Arranque el sistema normal sin cifrar y revise el btrfs." "Si algo falla antes de cifrar"
      ok "btrfs sin errores"
      install -d "$MNT_BRUTO"; mount -t btrfs "$D" "$MNT_BRUTO" || falla "no se pudo montar $D" "Ejecute cifrado-reanudar.sh; si se repite, vea la guía." "Si algo falla antes de cifrar"
      tam=$(btrfs filesystem show --raw "$MNT_BRUTO" | awk '/devid/{print $4}')
      if (( tam > OBJ - 64 * 1048576 )); then
        con_tiempo 600 "reducir el btrfs $REDUCIR_BTRFS" btrfs filesystem resize "-$REDUCIR_BTRFS" "$MNT_BRUTO" \
          || { umount "$MNT_BRUTO"; falla "no se pudo reducir el btrfs de $D" "Nada cifrado aún. Ejecute:  $REAN" "Si algo falla antes de cifrar"; }
        tam=$(btrfs filesystem show --raw "$MNT_BRUTO" | awk '/devid/{print $4}')
      fi
      sync; umount "$MNT_BRUTO" || falla "no se pudo desmontar $MNT_BRUTO" "Ejecute:  $REAN" "Si algo falla antes de cifrar"
      (( tam <= OBJ - 64 * 1048576 )) && ok "btrfs de $((tam / 1048576)) MiB en una partición de $((OBJ / 1048576)) MiB (sitio para LUKS)" \
        || falla "el btrfs no quedó reducido" "Ejecute:  $REAN" "Si algo falla antes de cifrar"
      cd "$TRABAJO" || falla "no puedo entrar en $TRABAJO" "Compruebe el USB." "Si algo falla antes de cifrar"
      echo "     Cifrando: verá líneas de progreso cada 20 s. NO apague, NO cierre la tapa, NO quite el USB."
      con_tiempo "$MAXT" "CIFRAR $P" cryptsetup --batch-mode reencrypt --encrypt "${CIFRADO[@]}" --uuid "$L" \
        --key-file "$FRASE" --progress-frequency 20 "$D" \
        || falla "el cifrado de $P se interrumpió o dio error" "Ejecute:  $REAN  (continúa donde se quedó)." "Si se corta a mitad del cifrado"
      ;;
    a-medias)
      cd "$TRABAJO" || true
      con_tiempo 600 "repair (recuperar tras el corte)" cryptsetup --batch-mode repair --key-file "$FRASE" "$D" \
        || aviso "repair no terminó bien; se intenta reanudar igualmente"
      con_tiempo "$MAXT" "REANUDAR el cifrado de $P" cryptsetup --batch-mode reencrypt --resume-only --key-file "$FRASE" \
        --progress-frequency 20 "$D" \
        || falla "no se pudo reanudar el cifrado de $P" "Ejecute otra vez:  $REAN  Si falla dos veces: último recurso." "Si se corta a mitad del cifrado"
      ;;
    cifrada) ok "ya estaba cifrada";;
    *) falla "$P ($D) no está ni en claro ni cifrada como se esperaba" "No siga. Último recurso: restaurar desde la copia de seguridad." "Último recurso";;
  esac
  [[ $(estado_de "$D" "$B" "$L") == cifrada ]] && ok "$P cifrada por completo (LUKS2)" \
    || falla "$P no quedó cifrada por completo" "Ejecute:  $REAN" "Si se corta a mitad del cifrado"
  # Abrir (TRIM permitido y guardado en la cabecera) y crecer el btrfs
  if [[ ! -e /dev/mapper/$M ]]; then
    CS open --allow-discards --persistent --key-file "$FRASE" "$D" "$M" || falla "no se pudo abrir $P con la frase" "Ejecute:  $REAN  (le pedirá la frase de nuevo)." "Si se corta a mitad del cifrado"
  fi
  [[ $(CS luksDump "$D") == *allow-discards* ]] && ok "TRIM permitido (guardado en la cabecera)" || aviso "TRIM no quedó guardado en la cabecera"
  [[ $(blkid -p -s UUID -o value "/dev/mapper/$M") == "$B" ]] && ok "dentro de LUKS está el btrfs de siempre (mismo UUID)" \
    || falla "dentro de $M no aparece el btrfs esperado" "No siga. Último recurso." "Último recurso"
  install -d "$MNT_BRUTO"; mount -t btrfs "/dev/mapper/$M" "$MNT_BRUTO" || falla "no se pudo montar /dev/mapper/$M" "Ejecute:  $REAN" "Si se corta a mitad del cifrado"
  con_tiempo 600 "crecer el btrfs al tamaño de LUKS" btrfs filesystem resize max "$MNT_BRUTO" >/dev/null || aviso "no se pudo crecer el btrfs (no es grave)"
  echo "     Comprobando todos los datos (scrub); puede tardar unos minutos."
  con_tiempo 3600 "scrub de $P" btrfs scrub start -B "$MNT_BRUTO" | tee "$TRABAJO/scrub-$P.txt"
  grep -q "no errors found" "$TRABAJO/scrub-$P.txt" && ok "scrub sin errores" || aviso "el scrub no dijo «no errors found»: revise $TRABAJO/scrub-$P.txt"
  sync; umount "$MNT_BRUTO"
  ok "$P TERMINADA: cifrada, abierta como /dev/mapper/$M y verificada"
}

# ---------- arranque (en chroot) ----------
montar_sistema() {
  local s
  install -d "$MNT"
  mountpoint -q "$MNT" || mount -o "subvol=$RAIZ_SUBVOL,$OPCIONES_BTRFS" "/dev/mapper/$RAIZ_MAP" "$MNT" \
    || falla "no se pudo montar la raíz ($RAIZ_SUBVOL)" "Ejecute cifrado-rescate.sh." "Si no arranca"
  for s in $SUBVOLUMENES_RAIZ; do
    mountpoint -q "$MNT/${s%%:*}" || mount -o "subvol=${s#*:},$OPCIONES_BTRFS" "/dev/mapper/$RAIZ_MAP" "$MNT/${s%%:*}" || aviso "no se montó ${s#*:}"
  done
  mountpoint -q "$MNT$ESP_MONTAJE" || mount "$ESP_DEV" "$MNT$ESP_MONTAJE" || falla "no se pudo montar la ESP en $MNT$ESP_MONTAJE" "Ejecute cifrado-rescate.sh." "Si no arranca"
  ok "sistema montado en $MNT (con $ESP_MONTAJE)"
}
desmontar_sistema() { sync; umount -R "$MNT" 2>/dev/null; mountpoint -q "$MNT" && aviso "no se pudo desmontar $MNT"; return 0; }
bak_una_vez() { [[ -e $1 && ! -e $1.bak.cifrado ]] && cp -p "$1" "$1.bak.cifrado"; return 0; }

configurar_arranque() {
  local K="$MNT$CLAVE_HOME" mid ent img cont principales lc="$MNT$LIMINE_CONF"
  local RES="Ejecute cifrado-rescate.sh (opción 1)."
  paso "Arranque: clave de /home, crypttab, initramfs y Limine (en chroot)"
  montar_sistema
  # 1. Fichero de clave de /home (lo creó cifrado-preparar.sh en el sistema; si faltara, se crea)
  if [[ ! -s $K ]]; then aviso "no estaba $CLAVE_HOME: se crea ahora"; install -d -m 700 "${K%/*}"; (umask 077; head -c 64 /dev/urandom > "$K"); fi
  chmod 400 "$K"; chmod 700 "${K%/*}"
  if CS open --test-passphrase --key-file "$K" "$HOME_DEV"; then ok "/home ya abre con el fichero de clave"
  else CS luksAddKey --key-file "$FRASE" "$HOME_DEV" "$K" || falla "no se pudo añadir el fichero de clave a /home" "$RES" "Si no arranca"
       CS open --test-passphrase --key-file "$K" "$HOME_DEV" && ok "fichero de clave añadido a /home y probado" || falla "el fichero de clave no abre /home" "$RES" "Si no arranca"
  fi
  # 2. crypttab (sistema): /home con el fichero de clave
  bak_una_vez "$MNT/etc/crypttab"
  { grep -vE "^\s*$HOME_MAP\s" "$MNT/etc/crypttab" 2>/dev/null; echo "$HOME_MAP UUID=$HOME_LUKS $CLAVE_HOME luks,discard"; } > "$MNT/etc/crypttab.nuevo"
  mv "$MNT/etc/crypttab.nuevo" "$MNT/etc/crypttab"; chmod 600 "$MNT/etc/crypttab"; ok "crypttab: $HOME_MAP con su fichero de clave"
  # 3. crypttab.initramfs: la raíz se abre desde el propio initramfs (también en las entradas de instantáneas)
  bak_una_vez "$MNT/etc/crypttab.initramfs"
  echo "$RAIZ_MAP UUID=$RAIZ_LUKS none luks,discard" > "$MNT/etc/crypttab.initramfs"; chmod 600 "$MNT/etc/crypttab.initramfs"
  ok "crypttab.initramfs: $RAIZ_MAP (frase o TPM2+PIN al arrancar)"
  # 4. mkinitcpio con sd-encrypt (antes de filesystems)
  bak_una_vez "$MNT/etc/mkinitcpio.conf"
  grep -qE '^HOOKS=.*\bsd-encrypt\b' "$MNT/etc/mkinitcpio.conf" || sed -i -E '/^HOOKS=/ s/\bfilesystems\b/sd-encrypt filesystems/' "$MNT/etc/mkinitcpio.conf"
  grep -qE '^HOOKS=.*\bsystemd\b.*\bsd-encrypt\b.*\bfilesystems\b' "$MNT/etc/mkinitcpio.conf" \
    && ok "mkinitcpio: $(grep -E '^HOOKS=' "$MNT/etc/mkinitcpio.conf")" || falla "HOOKS de mkinitcpio sin systemd o sin sd-encrypt antes de filesystems" "$RES" "Si no arranca"
  # 5. /etc/default/limine: rd.luks.name delante de root=
  bak_una_vez "$MNT/etc/default/limine"
  grep -q "rd.luks.name=$RAIZ_LUKS=$RAIZ_MAP" "$MNT/etc/default/limine" \
    || sed -i "s|root=UUID=$RAIZ_BTRFS|rd.luks.name=$RAIZ_LUKS=$RAIZ_MAP root=UUID=$RAIZ_BTRFS|" "$MNT/etc/default/limine"
  grep -q "rd.luks.name=$RAIZ_LUKS=$RAIZ_MAP root=UUID=$RAIZ_BTRFS" "$MNT/etc/default/limine" \
    && ok "/etc/default/limine con rd.luks.name" || falla "no se pudo poner rd.luks.name en /etc/default/limine (¿usa root=UUID=?)" "$RES" "Si no arranca"
  # 6. Regenerar initramfs y entradas de Limine
  con_tiempo 1200 "limine-mkinitcpio (initramfs y entradas)" arch-chroot "$MNT" /usr/bin/limine-mkinitcpio \
    || falla "limine-mkinitcpio falló" "$RES" "Si no arranca"
  if [[ -x $MNT/usr/bin/limine-snapper-sync ]]; then
    con_tiempo 600 "limine-snapper-sync (entradas de instantáneas)" arch-chroot "$MNT" /usr/bin/limine-snapper-sync \
      || aviso "limine-snapper-sync no terminó bien aquí; se repite en cifrado-primer-arranque.sh (no impide arrancar)"
  fi
  # 7. Comprobaciones del resultado
  mid=$(cat "$MNT/etc/machine-id")
  for ent in $KERNELS; do
    img="$MNT$ESP_MONTAJE/$mid/$ent/initramfs"
    [[ -s $img ]] || { mal "no existe el initramfs de $ent ($img)"; continue; }
    cont=$(arch-chroot "$MNT" lsinitcpio "$ESP_MONTAJE/$mid/$ent/initramfs" 2>/dev/null)
    [[ $cont == *systemd-cryptsetup* && $cont == *etc/crypttab* ]] && ok "initramfs de $ent con sd-encrypt y crypttab" || mal "initramfs de $ent sin sd-encrypt o sin crypttab"
  done
  principales=$(sed '/\/\/Snapshots/q' "$lc" | grep -c "cmdline:.*rd.luks.name=$RAIZ_LUKS=$RAIZ_MAP")
  (( principales >= 1 )) && ok "limine.conf: $principales entradas principales llevan rd.luks.name" || mal "limine.conf: ninguna entrada principal con rd.luks.name"
  echo "     entradas de instantáneas: $(sed -n '/\/\/Snapshots/,$p' "$lc" | grep -c 'cmdline:'), con rd.luks.name: $(sed -n '/\/\/Snapshots/,$p' "$lc" | grep -c 'cmdline:.*rd.luks.name') (las anteriores a la preparación no arrancan cifradas; es lo esperado)"
  [[ $FALLOS -eq 0 ]] || falla "la configuración de arranque no quedó bien ($FALLOS problemas)" "$RES" "Si no arranca"
  desmontar_sistema
  ok "arranque configurado"
}

cerrar_todo() { desmontar_sistema; umount "$MNT_BRUTO" 2>/dev/null; local m; for m in "$HOME_MAP" "$RAIZ_MAP"; do [[ -e /dev/mapper/$m ]] && cryptsetup close "$m"; done; sync; return 0; }

# ---------- sistema instalado ----------
# comprobar_sistema_instalado: / y /home salen de los mapeos de cifrado.conf
es_sistema_cifrado() {
  [[ $(findmnt -n -o SOURCE /) == "/dev/mapper/$RAIZ_MAP"* && $(findmnt -n -o SOURCE /home) == "/dev/mapper/$HOME_MAP"* ]]
}
tpm_disponible() {
  [[ -e /dev/tpmrm0 ]] && systemd-cryptenroll --tpm2-device=list </dev/null 2>/dev/null | grep -q /dev/
}
guardar_referencia_tpm() {
  install -d -m 755 "$DIR_TPM_REFERENCIA"
  systemd-analyze pcrs "${TPM_PCRS%%[+,]*}" 2>/dev/null | awk 'NR==2{print $3}' > "$DIR_TPM_REFERENCIA/pcr"
  cat /sys/class/dmi/id/bios_version > "$DIR_TPM_REFERENCIA/bios" 2>/dev/null
  date '+%F %T' > "$DIR_TPM_REFERENCIA/fecha"; chmod 644 "$DIR_TPM_REFERENCIA"/*
}
# Montaje del destino en red (si está configurado). Devuelve 1 si no hay destino o no se pudo montar.
montar_red() {
  [[ -n $COPIA_RECURSO ]] || return 1
  install -d -m 700 "$MNT_RED"
  mountpoint -q "$MNT_RED" && return 0
  mount -t cifs "$COPIA_RECURSO" "$MNT_RED" -o "credentials=$COPIA_CREDENCIALES,$COPIA_OPCIONES_CIFS"
}
desmontar_red() { mountpoint -q "$MNT_RED" && umount "$MNT_RED"; return 0; }
# Lista de ficheros que se copian (y se comprueban con SHA256SUMS) al USB, la ESP y la red
ficheros_publicables() { (cd "$BASE" && ls -1 cifrado-*.sh cifrado.conf README.md 2>/dev/null); }
# copiar_a DESTINO: copia los ficheros de SHA256SUMS y los verifica
copiar_a() {
  local f
  mkdir -p "$1" || return 1; chmod 700 "$1" 2>/dev/null   # exFAT/vfat no guardan permisos: no es un error
  for f in $(awk '{print $2}' "$BASE/SHA256SUMS") SHA256SUMS; do
    cp -- "$BASE/$f" "$1/$f" || return 1; chmod 600 "$1/$f" 2>/dev/null
  done
  (cd "$1" && sha256sum --quiet -c SHA256SUMS)
}
