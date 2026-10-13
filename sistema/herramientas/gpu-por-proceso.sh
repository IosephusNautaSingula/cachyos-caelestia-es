#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Uso de GPU por proceso y motor (i915/xe) sin root, para auditorías de consumo.
# Lee /proc/<pid>/fdinfo/* (drm-engine-<motor>: ns de ocupación por cliente DRM) en dos muestras separadas N segundos.
# Compara con el total por sysfs (100 % − residencia RC6) y, en batería, la potencia de todo el sistema (power_now).
# RAPL (/sys/class/powercap/intel-rapl*) no se usa: con la regla 90-estacion-powercap.rules solo lo lee el grupo energia.
# Uso: gpu-por-proceso.sh [segundos=20] [etiqueta]
# Salida: tabla legible y, al final, una línea «CSV;…» por proceso y motor para juntar escenarios.
set -u
N=${1:-20}; ETQ=${2:-}
G=; for c in /sys/class/drm/card*/gt/gt0; do [[ -r $c/rc6_residency_ms ]] && { G=$c; break; }; done
FREQ=; for c in /sys/class/drm/card*/gt_act_freq_mhz; do [[ -r $c ]] && { FREQ=$c; break; }; done
BAT=; for b in /sys/class/power_supply/BAT*; do [[ -r $b/power_now ]] && { BAT=$b; break; }; done

# Una línea por cliente DRM: pid comm client-id motor ns  (se deduplica por client-id: un cliente puede tener varios fd)
muestra() {
  # Solo los fd que apuntan a /dev/dri, leídos todos con un único awk
  local fds=()
  mapfile -t fds < <(find /proc/[0-9]*/fd -maxdepth 1 -lname '/dev/dri/*' 2>/dev/null | sed 's|/fd/|/fdinfo/|')
  [[ ${#fds[@]} -eq 0 ]] && return
  awk 'FNR==1 {if (id!="") for (m in e) print p, id, m, e[m]; delete e; id=""; split(FILENAME,f,"/"); p=f[3]}
       /^drm-client-id:/ {id=$2}
       /^drm-engine-[a-z-]+:/ && $3=="ns" {m=$1; sub(/^drm-engine-/,"",m); sub(/:$/,"",m); e[m]=$2}
       END {if (id!="") for (m in e) print p, id, m, e[m]}' "${fds[@]}" 2>/dev/null | sort -u -k2,2 -k3,3
}

a=$(mktemp); b=$(mktemp); trap 'rm -f "$a" "$b"' EXIT
r0=$( [[ -n $G ]] && cat $G/rc6_residency_ms ); t0=$(date +%s%N)
muestra > "$a"
sf=0; sn=0; sp=0; np=0
fin=$(( $(date +%s) + N ))
while [[ $(date +%s) -lt $fin ]]; do
  [[ -n $FREQ ]] && { sf=$((sf + $(cat $FREQ))); sn=$((sn+1)); }
  [[ -n $BAT && $(cat $BAT/status) == Discharging ]] && { sp=$((sp + $(cat $BAT/power_now))); np=$((np+1)); }
  sleep 0.5
done
muestra > "$b"
r1=$( [[ -n $G ]] && cat $G/rc6_residency_ms ); t1=$(date +%s%N)
dt=$(( (t1 - t0) / 1000000 ))   # ms

total=$( [[ -n $G ]] && awk -v r=$((r1-r0)) -v t=$dt 'BEGIN{printf "%.1f", 100-100*r/t}' )
freq=$( [[ $sn -gt 0 ]] && echo $((sf/sn)) )
watt=$( [[ $np -gt 0 ]] && awk -v s=$sp -v n=$np 'BEGIN{printf "%.2f", s/n/1e6}' )

if [[ -n $watt ]]; then pot="$watt W (batería)"; else pot="sin dato (no está en batería)"; fi
echo "== ${ETQ:-medición} · ${dt} ms · GPU total (sysfs, 100−RC6): ${total:-?} % · frecuencia media ${freq:-?} MHz · sistema $pot"
# Delta por cliente y motor → agregado por proceso (comm) y motor; % de un motor durante el intervalo
join -j1 <(awk '{print $2"|"$3, $1, $4}' "$a" | sort) <(awk '{print $2"|"$3, $1, $4}' "$b" | sort) |
  awk -v dt=$dt '{split($1,k,"|"); d=$5-$3; if (d>0) {pid=$4; cmd="ps -o comm= -p " pid; c=""; cmd | getline c; close(cmd); if (c=="") c="(terminado)";
        key=c" ("pid")|"k[2]; s[key]+=d}}
       END {for (x in s) {split(x,y,"|"); printf "%.2f\t%s\t%s\n", 100*s[x]/(dt*1e6), y[1], y[2]}}' |
  sort -rn > "$a.res"
if [[ -s $a.res ]]; then
  printf '%-30s %-14s %8s\n' "proceso (pid)" "motor" "uso"
  awk -F'\t' '{printf "%-30s %-14s %6.2f %%\n", $2, $3, $1}' "$a.res"
  awk -F'\t' -v e="${ETQ:-medición}" -v t="${total:-}" -v w="${watt:-}" '{print "CSV;" e ";" $2 ";" $3 ";" $1 ";" t ";" w}' "$a.res"
else
  echo "(ningún cliente DRM con actividad en el intervalo)"
fi
rm -f "$a.res"
