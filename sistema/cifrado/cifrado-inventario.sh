#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# cifrado-inventario.sh — INVENTARIO DE SOLO LECTURA antes del cifrado en el sitio. No cambia nada (ni discos, ni TPM,
# ni paquetes, ni /etc) y no guarda nada: todo sale por la salida estándar.
#  · ESP y limine.conf, crypttab, btrfs (uso, subvolúmenes y tamaño mínimo), entradas EFI, TPM2 (dispositivo y política
#    de bloqueo, con una orden TPM2_GetCapability de solo lectura a /dev/tpmrm0), Secure Boot.
#  · Al final, una PROPUESTA de cifrado.conf leída del sistema (con «--conf», solo la propuesta).
set -uo pipefail
exec </dev/null
# shellcheck source=cifrado-comun.sh
source "$(cd "$(dirname "$0")" && pwd)/cifrado-comun.sh"

ayuda() {
  cat <<EOF
cifrado-inventario.sh — inventario de solo lectura y propuesta de cifrado.conf (en el sistema instalado, sin cifrar).

  sudo bash $0                       inventario completo + propuesta de cifrado.conf (necesita root)
  bash $0 --conf > cifrado.conf.propuesta
                                     solo la propuesta de cifrado.conf (funciona también sin root)
  bash $0 --ayuda                    esta ayuda

No escribe nada en ningún sitio: revise la propuesta y guárdela usted como cifrado.conf.
EOF
}

SOLO_CONF=
for a in "$@"; do
  case $a in
    --conf) SOLO_CONF=1;;
    -h|--help|--ayuda) ayuda; exit 0;;
    *) echo "Opción desconocida: $a" >&2; ayuda >&2; exit 2;;
  esac
done

opcion_de() { tr ',' '\n' <<<"$1" | sed -n "s/^$2=//p" | head -1; }   # opcion_de "rw,subvol=/@" subvol

propuesta() {
  local rs rp hs hp disco esp esp_t subvol opc comp subs t s o sv k kernels="" mid lc usb="" u sp bytes_r bytes_h
  rs=$(findmnt -n -o SOURCE /); rp=${rs%%\[*}
  hs=$(findmnt -n -o SOURCE /home 2>/dev/null); hp=${hs%%\[*}
  echo "# SPDX-License-Identifier: GPL-3.0-or-later"
  echo "# cifrado.conf — PROPUESTA generada por cifrado-inventario.sh el $(date +%F). REVÍSELA línea a línea antes de usarla."
  echo "# Las explicaciones de cada variable están en cifrado.conf.example."
  [[ $(findmnt -n -o FSTYPE /) == btrfs ]] || echo "# !! La raíz NO es btrfs: estos scripts no sirven para este equipo."
  # Si ya están cifradas, se usa la partición que hay debajo del mapeo (los UUID de LUKS serán los actuales)
  local rm="" hm="" rl="" hl=""
  if [[ $rp == /dev/mapper/* ]]; then
    echo "# !! La raíz ya está en un dispositivo mapeado ($rp): ¿ya está cifrada? Se proponen los valores actuales."
    rm=$rp; rp=/dev/$(lsblk -rsno NAME,TYPE "$rm" | awk '$2=="part"{print $1; exit}'); rl=$(lsblk -dno UUID "$rp" 2>/dev/null)
  fi
  if [[ $hp == /dev/mapper/* ]]; then hm=$hp; hp=/dev/$(lsblk -rsno NAME,TYPE "$hm" | awk '$2=="part"{print $1; exit}'); hl=$(lsblk -dno UUID "$hp" 2>/dev/null); fi
  if [[ -z $hp || $hp == "$rp" ]]; then
    echo "# !! /home NO está en su propia partición: estos scripts necesitan raíz y /home en particiones btrfs distintas."
  fi
  disco=$(disco_de "$rp")
  read -r esp esp_t < <(findmnt -rn -t vfat -o SOURCE,TARGET | grep -E ' /(boot|efi|boot/efi)$' | head -1)
  echo
  echo "EQUIPO=\"$(cat /proc/sys/kernel/hostname)\""
  echo "USUARIO=\"${SUDO_USER:-$(id -un)}\""
  echo
  echo "DISCO=\"$disco\""
  echo "DISCO_SERIE=\"$(lsblk -dno SERIAL "$disco" 2>/dev/null | sed 's/ *$//')\""
  echo "DISCO_MODELO=\"$(lsblk -dno MODEL "$disco" 2>/dev/null | sed 's/ *$//')\""
  echo
  echo "ESP_PARTUUID=\"$(lsblk -dno PARTUUID "$esp" 2>/dev/null)\""
  echo "ESP_UUID=\"$(lsblk -dno UUID "$esp" 2>/dev/null)\""
  echo "ESP_MONTAJE=\"${esp_t:-/boot}\""
  lc=""; for k in limine.conf limine/limine.conf EFI/limine/limine.conf; do [[ -e ${esp_t:-/boot}/$k ]] && { lc=${esp_t:-/boot}/$k; break; }; done
  echo "LIMINE_CONF=\"${lc:-/boot/limine.conf}\"$([[ -z $lc ]] && echo '   # !! no se encontró limine.conf: ¿usa Limine?')"
  mid=$(cat /etc/machine-id 2>/dev/null)
  for k in $(pacman -Qq 2>/dev/null | grep -E '^linux(-[a-z0-9]+)*$' | grep -vE -- '-(headers|firmware|api-headers|docs)$|^linux-firmware'); do
    [[ -d ${esp_t:-/boot}/$mid/$k ]] && kernels+="${kernels:+ }$k"
  done
  if [[ -z $kernels ]]; then   # sin permiso para leer la ESP (sin root): los kernels instalados, sin comprobar
    kernels=$(pacman -Qq 2>/dev/null | grep -E '^linux(-[a-z0-9]+)*$' | grep -vE -- '-(headers|firmware|api-headers|docs)$|^linux-firmware' | paste -sd' ')
    echo "KERNELS=\"$kernels\"   # sin comprobar en la ESP (ejecute con sudo para comprobarlo)"
  else echo "KERNELS=\"$kernels\""; fi
  echo
  opc=$(findmnt -n -o OPTIONS /); subvol=$(opcion_de "$opc" subvol); comp=$(opcion_de "$opc" compress)
  subs=""
  while read -r t s o; do
    [[ ${s%%\[*} == "${rm:-$rp}" && $t != / ]] || continue
    sv=$(opcion_de "$o" subvol); [[ -n $sv && $sv != / ]] || continue
    subs+="${subs:+ }${t#/}:${sv#/}"
  done < <(findmnt -rn -t btrfs -o TARGET,SOURCE,OPTIONS)
  bytes_r=$(lsblk -bdno SIZE "$rp" 2>/dev/null)
  echo "RAIZ_PARTUUID=\"$(lsblk -dno PARTUUID "$rp" 2>/dev/null)\""
  echo "RAIZ_BYTES=\"$bytes_r\""
  echo "RAIZ_BTRFS=\"$(lsblk -dno UUID "${rm:-$rp}" 2>/dev/null)\""
  echo "RAIZ_LUKS=\"${rl:-$(cat /proc/sys/kernel/random/uuid)}\"$([[ -z $rl ]] && echo '   # nuevo, generado ahora')"
  echo "RAIZ_MAP=\"cryptroot\""
  echo "RAIZ_SUBVOL=\"${subvol#/}\""
  echo "OPCIONES_BTRFS=\"${comp:+compress=$comp}\""
  echo "SUBVOLUMENES_RAIZ=\"$subs\""
  echo
  if [[ -n $hp && $hp != "$rp" ]]; then
    bytes_h=$(lsblk -bdno SIZE "$hp" 2>/dev/null)
    echo "HOME_PARTUUID=\"$(lsblk -dno PARTUUID "$hp" 2>/dev/null)\""
    echo "HOME_BYTES=\"$bytes_h\""
    echo "HOME_BTRFS=\"$(lsblk -dno UUID "${hm:-$hp}" 2>/dev/null)\""
    [[ $(disco_de "$hp") == "$disco" ]] || echo "# !! /home está en otro disco ($(disco_de "$hp")): no es el caso previsto por estos scripts."
  else
    bytes_h=0
    echo "HOME_PARTUUID=\"\"   # !! sin partición propia"
    echo "HOME_BYTES=\"\""; echo "HOME_BTRFS=\"\""
  fi
  echo "HOME_LUKS=\"${hl:-$(cat /proc/sys/kernel/random/uuid)}\"$([[ -z $hl ]] && echo '   # nuevo, generado ahora')"
  echo "HOME_MAP=\"crypthome\""
  echo "CLAVE_HOME=\"/etc/cryptsetup-keys.d/crypthome.key\""
  echo
  echo "CIFRADO=(--type luks2 --cipher aes-xts-plain64 --key-size 512 --hash sha256 --pbkdf argon2id --reduce-device-size 32M)"
  echo "REDUCIR_BTRFS=\"256M\""
  # Tiempo máximo: 3 veces lo que se tardaría a 100 MiB/s, como mínimo 30 min (mida la velocidad real con la prueba)
  max_de() { local s=$(( ${1:-0} / 104857600 * 3 )); (( s < 1800 )) && s=1800; echo $s; }
  echo "MAX_RAIZ=\"$(max_de "$bytes_r")\""
  echo "MAX_HOME=\"$(max_de "$bytes_h")\""
  echo
  echo "FRASE_PALABRAS=\"6\""
  echo "PIN_MIN=\"6\""
  echo "TPM_PCRS=\"7\""
  echo "DIR_TPM_REFERENCIA=\"/var/lib/estacion-tpm\""
  echo
  echo "# USB candidatos (disco USB con una partición exFAT o vfat):"
  for u in $(lsblk -dnro NAME,TRAN | awk '$2=="usb"{print $1}'); do
    while read -r sp; do
      [[ -n $sp ]] || continue
      echo "#   /dev/$u · partición $sp · etiqueta «$(lsblk -dno LABEL "/dev/$sp")» · $(lsblk -dno FSTYPE "/dev/$sp") · serie $(udevadm info -q property -n "/dev/$u" | sed -n 's/^ID_SERIAL=//p')"
      [[ -z $usb ]] && usb="$(lsblk -dno LABEL "/dev/$sp")|$(udevadm info -q property -n "/dev/$u" | sed -n 's/^ID_SERIAL=//p')"
    done < <(lsblk -lnro NAME,FSTYPE "/dev/$u" | awk '$2=="exfat"||$2=="vfat"{print $1}')
  done
  echo "USB_ETIQUETA=\"${usb%%|*}\""
  echo "USB_SERIE=\"${usb#*|}\""
  echo "DIR_EN_USB=\"estacion-cifrado\""
  echo "VENTOY_JSON=\"ventoy/ventoy.json\""
  echo
  echo "DIR_REGISTROS=\"\""
  echo "DIR_TRABAJO=\"\""
  echo
  if [[ -r /etc/estacion/estacion.conf ]]; then
    echo "# Copia y destino en red: tomados de /etc/estacion/estacion.conf (revíselos)"
    # Se lee como texto (no se ejecuta): solo las variables que hacen falta
    _v() { sed -nE "s/^[[:space:]]*$1=[\"']?([^\"'#]*)[\"']?.*/\1/p" /etc/estacion/estacion.conf | tail -1 | sed 's/[[:space:]]*$//'; }
    echo "COPIA_AHORA=(/usr/local/bin/estacion-copia --ahora)"
    echo "COPIA_COMPROBAR=(/usr/local/bin/estacion-copia restic check)"
    echo "COPIA_RESTIC=(/usr/local/bin/estacion-copia restic)"
    x=$(_v COPIA_EXCLUIR); echo "COPIA_EXCLUIR=(\"${x:-/etc/estacion/excluir.txt}\")"
    echo "COPIA_NAS=\"$(_v COPIA_NAS)\""; x=$(_v COPIA_PUERTO); echo "COPIA_PUERTO=\"${x:-445}\""
    echo "COPIA_RECURSO=\"$(_v COPIA_RECURSO)\""; echo "COPIA_CREDENCIALES=\"$(_v COPIA_CREDENCIALES)\""
  else
    echo "# Copia de seguridad y destino en red: rellénelos usted (vea cifrado.conf.example). Vacíos = sin copia automática."
    echo "COPIA_AHORA=()"; echo "COPIA_COMPROBAR=()"; echo "COPIA_RESTIC=()"; echo "COPIA_EXCLUIR=()"
    echo "COPIA_NAS=\"\""; echo "COPIA_PUERTO=\"445\""; echo "COPIA_RECURSO=\"\""; echo "COPIA_CREDENCIALES=\"\""
  fi
  echo "COPIA_CERROJO=\"/run/estacion-copia.lock\""
  echo "COPIA_OPCIONES_CIFS=\"vers=3.1.1,seal,uid=0,gid=0,file_mode=0600,dir_mode=0700,noperm\""
  echo "COPIA_SUBDIR=\"reconstruir/cifrado\""
  echo "DIR_CABECERAS=\"/var/lib/estacion-copia/sistema/luks\""
  echo
  echo "SNAPPER_CONFIGS=\"$(snapper --csvout list-configs --columns config 2>/dev/null | tail -n +2 | paste -sd' ')\""
}

if [[ -n $SOLO_CONF ]]; then propuesta; exit 0; fi

if [[ $EUID -ne 0 ]]; then
  echo "cifrado-inventario.sh: el inventario completo necesita root (lee el TPM, la tabla EFI y el tamaño mínimo de btrfs)." >&2
  echo "  Ejecútelo así:   sudo bash $0" >&2
  echo "  Solo la propuesta de cifrado.conf (sin root):   bash $0 --conf" >&2
  echo "No se ha hecho nada." >&2
  exit 1
fi

t() { echo; echo "======== $* ========"; }
echo "#### Inventario de solo lectura · $(date '+%F %T') · $(uname -r)"

t "ESP: árbol y espacio"
read -r _ esp_t < <(findmnt -rn -t vfat -o SOURCE,TARGET | grep -E ' /(boot|efi|boot/efi)$' | head -1)
esp_t=${esp_t:-/boot}
find "$esp_t" -maxdepth 4 \( -type f -o -type d \) -printf '  %M %10s %TY-%Tm-%Td %p\n' 2>/dev/null | grep -v "/limine_history/.*/" | head -60
df -h "$esp_t" | sed 's/^/  /'

t "limine.conf (sin sumas)"
L=$(ls "$esp_t/limine.conf" "$esp_t/limine/limine.conf" "$esp_t/EFI/limine/limine.conf" 2>/dev/null | head -1); echo "  fichero: ${L:-NO ENCONTRADO}"
if [[ -n $L ]]; then
  sed -E 's/#[0-9a-f]{64,}//' "$L" | grep -E "^\s*(/|//|///|cmdline|kernel_cmdline|kernel_path|module_path|protocol|timeout|default_entry|remember)" | head -60 | sed 's/^/  /'
  echo "  entradas: $(grep -cE '^\s*/' "$L")"
fi
[[ -r /etc/default/limine ]] && { echo "  /etc/default/limine:"; grep -vE '^\s*#|^\s*$' /etc/default/limine | sed 's/^/    /'; }

t "mkinitcpio: HOOKS"
grep -E '^HOOKS=' /etc/mkinitcpio.conf | sed 's/^/  /'
grep -qE '^HOOKS=.*\bsystemd\b' /etc/mkinitcpio.conf && echo "  initramfs basado en systemd: sí (sd-encrypt es compatible)" \
  || echo "  !! initramfs SIN el hook systemd: sd-encrypt no funcionará así (vea la guía)"

t "crypttab y claves"
grep -vE '^\s*#|^\s*$' /etc/crypttab 2>/dev/null | sed 's/^/  /' || echo "  (vacío)"
[[ -e /etc/crypttab.initramfs ]] && grep -vE '^\s*#|^\s*$' /etc/crypttab.initramfs | sed 's/^/  initramfs: /'
ls -la /etc/cryptsetup-keys.d 2>/dev/null | sed 's/^/  /'

t "Discos y particiones"
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS | sed 's/^/  /'

t "btrfs: dispositivos, uso, subvolúmenes y tamaño mínimo"
for m in / /home; do
  echo "  -- $m ($(findmnt -n -o SOURCE "$m"))"
  btrfs filesystem show "$m" | sed 's/^/     /'
  btrfs filesystem usage -b "$m" 2>/dev/null | grep -E "Device size|Device allocated|Used:|Free \(estimated\)" | sed 's/^/     /'
  echo "     min-dev-size: $(btrfs inspect-internal min-dev-size "$m" 2>&1)"
  btrfs subvolume list "$m" | sed 's/^/     /' | head -30
done

t "Entradas EFI"
efibootmgr 2>&1 | sed 's/^/  /'

t "TPM2 (solo lectura)"
if [[ -e /dev/tpmrm0 ]]; then
  systemd-cryptenroll --tpm2-device=list 2>&1 | sed 's/^/  /'
  python3 -I - <<'PY' || echo "  (no se pudo leer la política de bloqueo)"
import os, struct
def getcap(fd, prop, count):
    # TPM2_GetCapability(TPM_CAP_TPM_PROPERTIES): orden estándar de solo lectura
    cmd = struct.pack(">HII", 0x8001, 22, 0x17A) + struct.pack(">III", 6, prop, count)
    os.write(fd, cmd); r = os.read(fd, 4096)
    tag, size, rc = struct.unpack(">HII", r[:10])
    if rc: raise SystemExit(f"  TPM rc=0x{rc:x}")
    more, cap, n = struct.unpack(">BII", r[10:19]); out = {}
    for i in range(n):
        p, v = struct.unpack(">II", r[19+8*i:27+8*i]); out[p] = v
    return out
fd = os.open("/dev/tpmrm0", os.O_RDWR)
fx = getcap(fd, 0x100, 64); va = getcap(fd, 0x200, 32); os.close(fd)
print(f"  versión de la especificación TPM 2.0: rev {fx.get(0x102,0)/100}")
perm = va.get(0x200, 0)
print(f"  inLockout: {'SÍ' if perm & (1<<9) else 'no'}  lockoutAuthSet: {'sí' if perm & 4 else 'no'}  ownerAuthSet: {'sí' if perm & 1 else 'no'}")
print(f"  fallos de autorización ahora (LOCKOUT_COUNTER): {va.get(0x20E)}")
print(f"  intentos antes del bloqueo (MAX_AUTH_FAIL):     {va.get(0x20F)}")
print(f"  se perdona un fallo cada (LOCKOUT_INTERVAL):    {va.get(0x210)} s")
print(f"  espera tras usar mal lockoutAuth (RECOVERY):    {va.get(0x211)} s")
PY
else
  echo "  !! no existe /dev/tpmrm0: sin TPM2 utilizable (se puede cifrar igual, solo con frase)"
fi

t "Secure Boot y PCR 7"
bootctl status 2>/dev/null | grep -iE "secure boot|setup mode|TPM2" | sed 's/^/  /'
systemd-analyze pcrs 7 2>/dev/null | sed 's/^/  /'

t "PROPUESTA DE cifrado.conf (revísela; no se ha guardado en ningún sitio)"
propuesta
echo
echo "#### Fin $(date '+%T')"
