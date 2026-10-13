# SPDX-License-Identifier: GPL-3.0-or-later
# huerfanos-snapper.sh — función para los comprobadores (se carga con «source»; necesita root para leer .snapshots).
# huerfanos_snapper CONFIG DIR: directorios numéricos de DIR (p. ej. home /home/.snapshots) que «snapper -c CONFIG list»
# no lista. Imprime una línea por cada uno:
#   «normal N»               directorio VACÍO con número mayor que todas las instantáneas listadas: lo conserva snapper a
#                            propósito por UNIQUE_NUMBERS (>= 0.13.2, por defecto yes) para no reutilizar el número.
#   «huerfano N (contenido)» cualquier otro (con contenido, o vacío pero con número no más alto): esto sí es un fallo.
huerfanos_snapper() {
  local cfg=$1 base=$2 lista n d max=0 cont
  lista=" $(snapper -c "$cfg" --csvout list --columns number | tail -n +2 | paste -sd' ') "
  for n in $lista; do (( n > max )) && max=$n; done
  for d in "$base"/*/; do
    n=$(basename "$d"); [[ $n =~ ^[0-9]+$ ]] || continue
    [[ $lista == *" $n "* ]] && continue
    cont=$(ls -A "$d" 2>/dev/null | paste -sd' ' || true)
    if [[ -z $cont ]] && (( n > max )); then echo "normal $n"; else echo "huerfano $n (${cont:-vacío, pero no es el número más alto})"; fi
  done
  return 0
}
