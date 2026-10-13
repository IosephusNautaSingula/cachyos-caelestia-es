#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# cifrado-reanudar.sh — REANUDAR tras un corte de luz, un apagado o un error a mitad del cifrado (desde el live).
# Detecta el estado de cada partición y hace lo que toque:
#   en claro (el corte llegó antes de escribir la cabecera LUKS) → aparta la cabecera temporal LUKS2-temp si la hay,
#                                                                  comprueba el btrfs y cifra desde el principio;
#   LUKS a medio cifrar → cryptsetup repair y reencrypt --resume-only (con o sin LUKS2-temp: no hace falta);
#   cifrada → la abre, crece el btrfs y la verifica.
# Y termina como cifrado-live.sh: arranque configurado.
set -uo pipefail
ayuda() {
  cat <<AYUDA
cifrado-reanudar.sh — reanuda el cifrado en el sitio tras un corte o un error (entorno live).

  sudo bash $0 --ejecutar --acepto-perdida-de-datos

Es lo mismo que «cifrado-live.sh --reanudar --ejecutar --acepto-perdida-de-datos». Antes de reanudar puede ejecutar
«cifrado-live.sh --prueba» para ver el estado de cada partición sin escribir nada.
Sin argumentos: muestra esta ayuda y sale.
AYUDA
}
if [[ $# -eq 0 || " $* " == *" -h "* || " $* " == *" --ayuda "* || " $* " == *" --help "* ]]; then ayuda; exit 0; fi
exec bash "$(cd "$(dirname "$0")" && pwd)/cifrado-live.sh" --reanudar "$@"
