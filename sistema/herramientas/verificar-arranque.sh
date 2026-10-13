#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# verificar-arranque.sh: comprobación de solo lectura tras un arranque de prueba (desde una instantánea de snapper o
# con el kernel LTS): desde qué se ha arrancado y si la sesión está sana.
# Uso: verificar-arranque.sh [esperado]   esperado = normal | instantanea:<N> | lts
# Variables: SUBVOL_RAIZ (subvolumen de la raíz, por defecto /@, el de CachyOS).
set -u
esp=${1:-normal}
SUBVOL_RAIZ=${SUBVOL_RAIZ:-/@}
ok() { printf '  OK   %s\n' "$*"; }; mal() { printf '  !!   %s\n' "$*"; FALLOS=$((FALLOS+1)); }; FALLOS=0
echo "== Arranque $(date '+%F %T') · esperado: $esp"
fs=$(findmnt -no FSTYPE /); src=$(findmnt -no SOURCE /); opts=$(findmnt -no OPTIONS /)
echo "  / → $fs $src"
kern=$(uname -r); echo "  kernel: $kern"
sub=$(grep -oE 'rootflags=subvol=[^ ,]+' /proc/cmdline | sed 's/rootflags=subvol=//')
echo "  subvolumen pedido: ${sub:-?}"
case $esp in
  instantanea:*)
    id=${esp#instantanea:}
    [[ $sub == "$SUBVOL_RAIZ/.snapshots/$id/snapshot" ]] && ok "la línea de arranque apunta a la instantánea $id" || mal "subvolumen $sub (se esperaba $SUBVOL_RAIZ/.snapshots/$id/snapshot)"
    [[ $fs == overlay ]] && ok "raíz en overlay (instantánea de solo lectura + capa temporal)" || mal "raíz $fs (se esperaba overlay)"
    findmnt -rno OPTIONS / | tr ',' '\n' | grep -E '^(lowerdir|upperdir)=' | sed 's/^/       /'
    ;;
  normal|lts)
    [[ $sub == "$SUBVOL_RAIZ" ]] && ok "arranca del subvolumen normal $SUBVOL_RAIZ" || mal "subvolumen $sub (se esperaba $SUBVOL_RAIZ)"
    [[ $fs == btrfs && $opts == rw,* ]] && ok "raíz btrfs en lectura y escritura" || mal "raíz $fs $opts"
    if [[ $esp == lts ]]; then [[ $kern == *lts* ]] && ok "kernel LTS en uso" || mal "kernel $kern (se esperaba un LTS)"
    else [[ $kern != *lts* ]] && ok "kernel principal en uso" || mal "kernel $kern (se esperaba el principal)"; fi
    ;;
  *) echo "uso: ${0##*/} [normal | instantanea:<N> | lts]" >&2; exit 2 ;;
esac
findmnt -no FSTYPE,OPTIONS /home | grep -q '^btrfs rw' && ok "/home montado normal (rw)" || mal "/home: $(findmnt -no FSTYPE,OPTIONS /home)"
f=$(systemctl --failed --no-legend --plain | wc -l); [[ $f -eq 0 ]] && ok "sin servicios del sistema fallidos" || { mal "$f servicios del sistema fallidos:"; systemctl --failed --no-legend --plain | sed 's/^/       /'; }
fu=$(systemctl --user --failed --no-legend --plain | wc -l); [[ $fu -eq 0 ]] && ok "sin servicios de usuario fallidos" || { mal "$fu servicios de usuario fallidos:"; systemctl --user --failed --no-legend --plain | sed 's/^/       /'; }
pgrep -x Hyprland >/dev/null && ok "Hyprland en marcha" || mal "Hyprland no está en marcha"
pgrep -f '^qs -c caelestia' >/dev/null && ok "interfaz Caelestia (qs) en marcha" || mal "qs no está en marcha"
systemctl is-active --quiet NetworkManager && ok "red (NetworkManager) activa" || mal "NetworkManager inactivo"
echo "== $([[ $FALLOS -eq 0 ]] && echo 'TODO CORRECTO' || echo "$FALLOS PROBLEMA(S)")"
