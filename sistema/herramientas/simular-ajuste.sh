#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Simula pulsaciones de las teclas de volumen, micrófono y brillo con la cadencia real de Hyprland
# (repeat_delay y repeat_rate de hyprctl getoption): primera pulsación en t=0, primera repetición a repeat_delay y
# después una cada 1000/repeat_rate ms. Llama a estacion-ajuste como lo haría el atajo y registra cada llamada
# (ESTACION_AJUSTE_LOG). Deja cada control como estaba al empezar (volumen, silencio y brillo).
# Uso: simular-ajuste.sh [control...]   (por defecto: volumen micro brillo). Salida: tabla en ${XDG_STATE_HOME:-~/.local/state}/estacion/.
set -u
export LC_NUMERIC=C
A=${AJUSTE:-$(command -v estacion-ajuste || echo "$HOME/.local/bin/estacion-ajuste")}
DELAY=$(hyprctl getoption input:repeat_delay | awk '/int:/{print $2}'); RATE=$(hyprctl getoption input:repeat_rate | awk '/int:/{print $2}')
PER_US=$(( 1000000 / RATE )); DELAY_US=$(( DELAY * 1000 ))
# CADENCIA=firmware: ritmo típico de las teclas de brillo que llegan del «Video Bus» de ACPI: 410 ms y luego cada 197 ms
if [[ ${CADENCIA:-teclado} == firmware ]]; then DELAY_US=410000; PER_US=197000; DELAY=410; RATE=5; fi
mkdir -p "${XDG_STATE_HOME:-$HOME/.local/state}/estacion"
OUT=${XDG_STATE_HOME:-$HOME/.local/state}/estacion/simular-ajuste-$(date +%F-%H%M%S)-${CADENCIA:-teclado}.txt
us() { local x=${1//[.,]/}; echo $((10#$x)); }
B=/sys/class/backlight/${AJUSTE_BACKLIGHT:-$(ls /sys/class/backlight | head -1)}
pct_brillo() { echo $(( ($(cat $B/brightness) * 100 + $(cat $B/max_brightness) / 2) / $(cat $B/max_brightness) )); }
pct_wp() { wpctl get-volume "$1" | awk '{printf "%d", $2*100+0.5}'; }
mute_wp() { wpctl get-volume "$1" | grep -q MUTED && echo 1 || echo 0; }
valor() { case $1 in volumen) pct_wp @DEFAULT_AUDIO_SINK@ ;; micro) pct_wp @DEFAULT_AUDIO_SOURCE@ ;; brillo) pct_brillo ;; esac; }
poner() { case $1 in   # pone el control en $2 % por la misma vía que el uso normal
  volumen) wpctl set-volume @DEFAULT_AUDIO_SINK@ "$2%" ;; micro) wpctl set-volume @DEFAULT_AUDIO_SOURCE@ "$2%" ;;
  brillo) qs -c caelestia ipc call brightness set "$2%" >/dev/null ;; esac; sleep 0.4; }

# Mantiene pulsado «subir» durante $3 ms (0 = pulsación suelta). Escribe una fila por pulsación.
mantener() {
  local c=$1 nombre=$2 dur_ms=$3 log; log=$(mktemp); local v0; v0=$(valor "$c")
  local t0; t0=$(us "$EPOCHREALTIME"); local k=0 objetivo=0 durs=()
  while :; do
    (( k == 0 )) && objetivo=0 || objetivo=$(( DELAY_US + (k - 1) * PER_US ))
    (( k > 0 && objetivo > dur_ms * 1000 )) && break
    local ahora; ahora=$(us "$EPOCHREALTIME"); local espera=$(( t0 + objetivo - ahora ))
    (( espera > 0 )) && sleep "$(printf '0.%06d' "$espera")"
    local s; s=$(us "$EPOCHREALTIME"); ESTACION_AJUSTE_LOG=$log "$A" "$c" subir >/dev/null; local e; e=$(us "$EPOCHREALTIME")
    durs+=( $(( e - s )) ); k=$((k + 1)); (( dur_ms == 0 )) && break
  done
  sleep 0.5; local vf; vf=$(valor "$c")
  # Valor paso a paso: el de partida más los pasos registrados, limitado como hace estacion-ajuste
  local i=0 v=$v0 t100=
  while read -r t n paso; do
    local tr=$(( (t - t0) / 1000 ))
    if [[ $c == brillo ]]; then (( v + paso > 100 )) && paso=$(( 100 - v )); fi
    v=$(( v + paso > 100 ? 100 : v + paso ))
    [[ -z $t100 && $v -ge 100 ]] && t100=$tr
    printf '%-8s %-12s %3d %6d ms  rep %3d  paso %d%%  → %3d %%  llamada %5.1f ms\n' \
      "$c" "$nombre" $((i + 1)) "$tr" "$n" "$paso" "$v" "$(awk -v x="${durs[$i]}" 'BEGIN{print x/1000}')" >> "$OUT"
    i=$((i + 1))
  done < "$log"
  printf '%-8s %-12s RESUMEN: %d pulsaciones, de %d %% a %d %% (calculado %d %%, leído %d %%)%s\n\n' "$c" "$nombre" "$i" "$v0" "$vf" "$v" "$vf" \
    "${t100:+, llega a 100 % en $t100 ms}" >> "$OUT"
  rm -f "$log"
}

echo "# simular-ajuste $(date '+%F %T') · cadencia ${CADENCIA:-teclado} · repeat_delay $DELAY ms · repeat_rate $RATE/s (una cada $((PER_US/1000)).$(( (PER_US%1000)/100 )) ms)" > "$OUT"
for c in "${@:-volumen micro brillo}"; do
  for c2 in $c; do
    ini=$(valor "$c2"); m0=; [[ $c2 == volumen ]] && m0=$(mute_wp @DEFAULT_AUDIO_SINK@); [[ $c2 == micro ]] && m0=$(mute_wp @DEFAULT_AUDIO_SOURCE@)
    echo "## $c2: valor inicial $ini %${m0:+ (silenciado: $m0)}" >> "$OUT"
    mantener "$c2" suelta 0
    "$A" "$c2" bajar >/dev/null; sleep 0.5                   # deshace la pulsación suelta
    [[ $c2 == brillo ]] && poner "$c2" 1 || poner "$c2" 0
    mantener "$c2" "1 s" 1000
    [[ $c2 == brillo ]] && poner "$c2" 1 || poner "$c2" 0
    mantener "$c2" "3 s" 3000
    poner "$c2" "$ini"                                      # vuelve al valor inicial
    [[ $c2 == volumen && $m0 == 1 ]] && wpctl set-mute @DEFAULT_AUDIO_SINK@ 1
    [[ $c2 == micro && $m0 == 1 ]] && wpctl set-mute @DEFAULT_AUDIO_SOURCE@ 1
    echo "## $c2: valor final $(valor "$c2") % (inicial $ini %)" >> "$OUT"
  done
done
echo "$OUT"
