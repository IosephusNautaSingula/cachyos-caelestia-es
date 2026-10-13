#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# cifrado-preparar.sh — PREPARAR, en el sistema instalado (aún sin cifrar), justo antes de apagar para cifrar.
# NO CIFRA NADA. Pasos:
#  1. Comprueba: equipo y usuario, cargador, disco y particiones de cifrado.conf, destino en red, el USB (por su
#     etiqueta y número de serie), que el USB multiarranque (ventoy.json) permite montar su partición en el live (VTOY_LINUX_REMOUNT), los scripts
#     del USB contra SHA256SUMS, y que «cifrado-live.sh --prueba» SE NIEGA aquí (no es el live; discos montados).
#  2. Plan B: copia de los scripts en la ESP, por si en el live no se puede montar el USB.
#  3. Fichero de clave de /home (64 bytes al azar, 0400), excluido de la copia de seguridad.
#  4. initramfs con sd-encrypt y /etc/crypttab.initramfs con «nofail» y 15 s de espera: no cambia este arranque (como
#     mucho 15 s más) y hace que la instantánea «Antes del cifrado» arranque también ya cifrada.
#  5. Copia de seguridad nueva y su comprobación (COPIA_AHORA y COPIA_COMPROBAR; si no hay, confirmación tecleada).
#  6. Instantáneas «Antes del cifrado (LUKS)» (important=yes) y entradas de Limine.
#  7. Copia de los scripts en el destino en red (si lo hay) y verificación.
# Cada fichero del sistema que se cambia se copia antes como <fichero>.bak.<fecha>-cifrado.
set -uo pipefail
# shellcheck source=cifrado-comun.sh
source "$(cd "$(dirname "$0")" && pwd)/cifrado-comun.sh"

ayuda() {
  cat <<EOF
cifrado-preparar.sh — prepara el sistema instalado (sin cifrar) para el cifrado en el sitio. No cifra nada, pero
SÍ escribe: fichero de clave de /home, crypttab.initramfs, mkinitcpio.conf, initramfs, entradas de Limine,
instantáneas, ficheros de exclusión de la copia y copias de los scripts en la ESP y en la red.

  sudo bash $0 --ejecutar --acepto-perdida-de-datos

Antes: cifrado-inventario.sh, cifrado.conf rellenado, cifrado-prueba-loop.sh y cifrado-copiar.sh.
Sin argumentos: muestra esta ayuda y sale.
EOF
}
leer_opciones "$@"
(( ${#OTRAS[@]} == 0 )) || { echo "Opción desconocida: ${OTRAS[*]}" >&2; ayuda; exit 2; }
if [[ -n $AYUDA || ( -z $EJECUTAR && -z $ACEPTO ) ]]; then ayuda; exit 0; fi
exigir_banderas
exigir_root
[[ -n ${SUDO_USER:-} && $SUDO_USER != root ]] || { echo "ERROR: ejecútelo con sudo desde su usuario: sudo bash $0 ..." >&2; exit 1; }
exec </dev/null
cargar_conf
confirmar_riesgo "${DISCO##*/}" "preparar el arranque de $DISCO para el cifrado (initramfs, crypttab, Limine, fichero de clave)"
iniciar_log "cifrado-preparar"
HOY=$(date +%F); BAK=".bak.$HOY-cifrado"
bak() { [[ -e $1 && ! -e $1$BAK ]] && cp -p "$1" "$1$BAK"; return 0; }
FICHEROS_OK=
DESMONTAR_USB=
trap '[[ -n $DESMONTAR_USB ]] && umount "$USB"; desmontar_red; borrar_secretos' EXIT

paso "1. Comprobaciones"
[[ -z $EQUIPO || $(cat /proc/sys/kernel/hostname) == "$EQUIPO" ]] && ok "equipo esperado" || para "este equipo no es el de cifrado.conf (EQUIPO)"
[[ -z $USUARIO || $SUDO_USER == "$USUARIO" ]] && ok "usuario esperado" || para "el usuario no es el de cifrado.conf (USUARIO)"
es_sistema_cifrado && para "el sistema ya está cifrado: no hay nada que preparar"
[[ $(findmnt -n -o SOURCE /) == "$RAIZ_DEV"* && $(findmnt -n -o SOURCE /home) == "$HOME_DEV"* ]] \
  && ok "/ y /home salen de las particiones de cifrado.conf" || para "/ o /home no salen de las particiones de cifrado.conf"
corriente_ok && ok "cargador conectado (o equipo sin batería)" || para "enchufe el cargador y repita"
comprobar_disco
[[ $FALLOS -eq 0 ]] || para "el disco no coincide con cifrado.conf"
for c in limine-mkinitcpio lsinitcpio cryptsetup systemd-cryptenroll btrfs; do command -v "$c" >/dev/null && ok "$c disponible" || mal "falta $c"; done
grep -qE '^HOOKS=.*\bsystemd\b' /etc/mkinitcpio.conf && ok "initramfs basado en systemd (sd-encrypt compatible)" \
  || mal "HOOKS de /etc/mkinitcpio.conf sin «systemd»: sd-encrypt no funcionaría (vea la guía)"
if [[ -n $COPIA_RECURSO && -n $COPIA_NAS ]]; then
  timeout 5 bash -c "exec 3<>/dev/tcp/$COPIA_NAS/$COPIA_PUERTO" 2>/dev/null && ok "el destino en red responde" || para "el destino en red no responde: enciéndalo y repita"
fi
USBDEV=$(readlink -f "/dev/disk/by-label/$USB_ETIQUETA" 2>/dev/null); USBDISCO=$(disco_de "$USBDEV")
[[ -n $USB_ETIQUETA && -b $USBDEV && -n $USBDISCO && $USBDISCO != "$DISCO" ]] || para "no encuentro el USB (USB_ETIQUETA de cifrado.conf)"
serie=$(udevadm info -q property -n "$USBDISCO" | sed -n 's/^ID_SERIAL=//p')
[[ $serie == "${USB_SERIE%-0:0}" || $serie == "$USB_SERIE" ]] && ok "USB $USBDISCO con la serie esperada" || para "el USB $USBDISCO no tiene la serie de cifrado.conf"
USB=$(findmnt -rn -S "$USBDEV" -o TARGET | head -1)
if [[ -z $USB ]]; then USB=/mnt/estacion-cifrado-usb; install -d "$USB"; mount "$USBDEV" "$USB" || para "no se pudo montar el USB"; DESMONTAR_USB=1; fi
findmnt -rn -o OPTIONS -T "$USB" | grep -qw rw && ok "USB montado con escritura en $USB" || para "el USB está solo lectura"
if [[ -n $VENTOY_JSON ]]; then
  grep -q '"VTOY_LINUX_REMOUNT"[[:space:]]*:[[:space:]]*"1"' "$USB/$VENTOY_JSON" 2>/dev/null && ok "ventoy.json: VTOY_LINUX_REMOUNT=1 (el live podrá montar el USB)" \
    || mal "sin VTOY_LINUX_REMOUNT=1 en $VENTOY_JSON: en el live quizá no se pueda montar el USB (plan B: la ESP)"
fi
[[ -s $BASE/SHA256SUMS ]] && (cd "$BASE" && sha256sum --quiet -c SHA256SUMS) || para "faltan o no coinciden las sumas locales: ejecute antes cifrado-copiar.sh"
cmp -s "$BASE/SHA256SUMS" "$USB/$DIR_EN_USB/SHA256SUMS" && (cd "$USB/$DIR_EN_USB" && sha256sum --quiet -c SHA256SUMS) \
  && ok "scripts del USB idénticos a los locales (sha256)" || para "los scripts del USB no coinciden: ejecute cifrado-copiar.sh"
# El modo --prueba tiene que NEGARSE aquí (no es el live y los discos están montados)
NEG="$LOGDIR/prueba-negativa-$(date +%Y%m%d-%H%M%S).txt"
(umask 077; bash "$BASE/cifrado-live.sh" --prueba > "$NEG" 2>&1); rc=$?
if [[ $rc -ne 0 ]] && grep -q "NO es el entorno live" "$NEG" && grep -q "MONTADO" "$NEG"; then
  ok "cifrado-live.sh --prueba SE NIEGA aquí (no es el live; particiones montadas): $(grep -c 'MAL' "$NEG") problemas"
else mal "cifrado-live.sh --prueba NO se negó como debía (código $rc): revise $NEG"; fi
[[ $FALLOS -eq 0 ]] || para "$FALLOS problema(s) en las comprobaciones"

paso "2. Plan B: copia de los scripts en la ESP ($ESP_MONTAJE/$DIR_EN_USB)"
copiar_a "$ESP_MONTAJE/$DIR_EN_USB" && ok "copia en la ESP verificada ($(du -sh "$ESP_MONTAJE/$DIR_EN_USB" | cut -f1))" || para "la copia en la ESP no coincide"

paso "3. Fichero de clave de /home"
install -d -m 700 "${CLAVE_HOME%/*}"
if [[ -s $CLAVE_HOME ]]; then ok "ya existía $CLAVE_HOME"; else (umask 077; head -c 64 /dev/urandom > "$CLAVE_HOME"); ok "creado $CLAVE_HOME"; fi
chmod 400 "$CLAVE_HOME"; [[ $(stat -c '%a %s' "$CLAVE_HOME") == "400 64" ]] && ok "64 bytes, permisos 0400 (root)" || para "el fichero de clave no quedó bien"
for e in "${COPIA_EXCLUIR[@]}"; do
  [[ -e $e ]] || { aviso "no existe el fichero de exclusión $e: no se toca"; continue; }
  grep -qx "${CLAVE_HOME%/*}" "$e" || { bak "$e"; printf '%s\n' '# Cifrado: el fichero de clave de /home no sale del equipo (con la frase se abre /home sin él)' "${CLAVE_HOME%/*}" >> "$e"; }
  grep -qx "${CLAVE_HOME%/*}" "$e" && ok "excluido de la copia en $e" || para "no se pudo excluir en $e"
done
(( ${#COPIA_EXCLUIR[@]} > 0 )) || aviso "COPIA_EXCLUIR vacío: asegúrese de que su copia de seguridad NO incluye ${CLAVE_HOME%/*}"

paso "4. initramfs con sd-encrypt y crypttab.initramfs"
bak /etc/crypttab.initramfs
echo "$RAIZ_MAP UUID=$RAIZ_LUKS none luks,discard,nofail,x-systemd.device-timeout=15s" > /etc/crypttab.initramfs; chmod 600 /etc/crypttab.initramfs
bak /etc/mkinitcpio.conf
grep -qE '^HOOKS=.*\bsd-encrypt\b' /etc/mkinitcpio.conf || sed -i -E '/^HOOKS=/ s/\bfilesystems\b/sd-encrypt filesystems/' /etc/mkinitcpio.conf
grep -E '^HOOKS=' /etc/mkinitcpio.conf | sed 's/^/  /'
grep -qE '^HOOKS=.*\bsystemd\b.*\bsd-encrypt\b.*\bfilesystems\b' /etc/mkinitcpio.conf || para "HOOKS sin sd-encrypt antes de filesystems"
timeout 1200 /usr/bin/limine-mkinitcpio || para "limine-mkinitcpio falló (copia de mkinitcpio.conf en $BAK)"
mid=$(cat /etc/machine-id)
for k in $KERNELS; do
  c=$(lsinitcpio "$ESP_MONTAJE/$mid/$k/initramfs" 2>/dev/null)
  [[ $c == *systemd-cryptsetup* && $c == *etc/crypttab* ]] && ok "initramfs de $k con sd-encrypt y crypttab" || para "initramfs de $k sin sd-encrypt"
done

paso "5. Copia de seguridad nueva y comprobación"
if (( ${#COPIA_AHORA[@]} > 0 )); then
  "${COPIA_AHORA[@]}" || para "la copia de seguridad falló: NO cifre"
  if (( ${#COPIA_COMPROBAR[@]} > 0 )); then "${COPIA_COMPROBAR[@]}" || para "la comprobación de la copia encontró errores: NO cifre"; fi
  ok "copia de seguridad hecha y comprobada"
else
  aviso "COPIA_AHORA vacío: este script no puede hacer la copia por usted."
  read -r -p "  Si tiene una copia COMPLETA, RECIENTE y COMPROBADA fuera de este disco, escriba «tengo copia»: " r </dev/tty
  [[ $r == "tengo copia" ]] || para "sin copia de seguridad comprobada no se sigue"
  ok "copia de seguridad confirmada por el usuario"
fi

paso "6. Instantáneas «Antes del cifrado (LUKS)»"
for c in $SNAPPER_CONFIGS; do
  n=$(snapper -c "$c" create --description "Antes del cifrado (LUKS)" --userdata important=yes --print-number) && ok "snapper $c #$n" || mal "snapper $c"
done
if command -v limine-snapper-sync >/dev/null; then timeout 600 limine-snapper-sync >/dev/null 2>&1 && ok "entradas de Limine al día" || mal "limine-snapper-sync"; fi

paso "7. Copia de los scripts en el destino en red"
if [[ -z $COPIA_RECURSO ]]; then aviso "sin destino en red configurado: los scripts quedan en el USB y en la ESP"
elif montar_red; then copiar_a "$MNT_RED/$COPIA_SUBDIR" && ok "copia en la red verificada" || mal "la copia de la red no coincide"; desmontar_red
else mal "no se pudo montar el destino en red"; fi

echo
[[ $FALLOS -eq 0 ]] && echo "${V}#### PREPARADO. Suma de control (compárela con la de su gestor de contraseñas): SHA256SUMS = $(sha256sum "$BASE/SHA256SUMS" | cut -c1-64)${N}" \
  || echo "${R}#### $FALLOS problema(s): revise las líneas MAL antes de apagar.${N}"
echo "  Siguiente (guía): reiniciar una vez para comprobar que arranca normal (unos 15 s más lento); luego apagar"
echo "  y arrancar el live desde el USB."
echo "  Registro: $LOG"
