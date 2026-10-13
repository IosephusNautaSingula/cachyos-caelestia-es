<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# Perfiles de energía de Caelestia con power-profiles-daemon

El selector de la ventana de la batería de Caelestia (Ahorro / Equilibrado / Rendimiento) no hace nada por sí
mismo: escribe la propiedad `ActiveProfile` de **power-profiles-daemon** por D-Bus, igual que `powerprofilesctl set`.
Esta guía explica cómo comprobar que los tres perfiles cambian de verdad el firmware, el procesador y el consumo,
y cómo hacer que el perfil elegido se aplique desde el arranque.

## Requisitos

- `power-profiles-daemon` instalado y **ningún otro gestor de energía** a la vez: tlp, auto-cpufreq, tuned o
  system76-power. Su unidad declara `Conflicts=` con ellos.
- Procesador Intel con `intel_pstate` en modo activo (o AMD con `amd_pstate`) y, si el portátil lo ofrece,
  `/sys/firmware/acpi/platform_profile`.

## Cómo comprobar si le afecta

```bash
powerprofilesctl list                          # perfiles, CpuDriver y PlatformDriver
systemctl is-enabled power-profiles-daemon     # «disabled» = solo lo arranca D-Bus al iniciar sesión
cat /sys/firmware/acpi/platform_profile_choices
for s in tlp auto-cpufreq tuned thermald; do systemctl is-active $s; done   # deben estar inactivos
```

Si `powerprofilesctl list` muestra `PlatformDriver: placeholder`, el firmware no ofrece perfiles. En ese caso solo
cambia el procesador (EPP), y el perfil «Rendimiento» puede no estar disponible.

## Qué cambia cada perfil

Con `intel_pstate` y `platform_profile`, power-profiles-daemon ajusta:

| Perfil | platform_profile | EPP (`energy_performance_preference`) | EPB (`energy_perf_bias`) |
|---|---|---|---|
| Rendimiento | performance | performance | 0 |
| Equilibrado | balanced | balance_performance (con cargador) / balance_power (con batería) | 6 / 8 |
| Ahorro | low-power | power | 15 |

El governor sigue siendo `powersave` en todos los núcleos: es lo normal con `intel_pstate` activo, porque quien
decide es el EPP. Los límites de RAPL (`constraint_*_power_limit_uw`) no cambian. La diferencia de consumo la ponen
el firmware y el EPP.

Lea los valores así:

```bash
cat /sys/firmware/acpi/platform_profile
sort /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference | uniq -c
sort /sys/devices/system/cpu/cpu*/power/energy_perf_bias | uniq -c
```

## Medir el consumo

La potencia del paquete se calcula con el contador de energía de RAPL. Para leerlo sin root, instale el componente
`energia` de `sistema/`, que crea el grupo `energia`. Ejemplo con la misma carga fija para cada perfil (4 bucles de
bash durante 20 s):

```bash
R=/sys/class/powercap/intel-rapl:0
for p in performance balanced power-saver; do
  powerprofilesctl set "$p"; sleep 5
  for i in 1 2 3 4; do timeout 20 bash -c 'while :; do :; done' & done
  e0=$(cat $R/energy_uj); sleep 20; e1=$(cat $R/energy_uj); wait
  echo "$p: $(( (e1 - e0) / 20000000 )) W"
done
powerprofilesctl set balanced     # o el que tuviera
```

Orden de magnitud en un portátil Intel de bajo consumo, con batería:

| Perfil | Con la carga fija | En reposo |
|---|---|---|
| Rendimiento | ≈ 30 W | ≈ 5 W |
| Equilibrado | ≈ 11 W | ≈ 2,5 W |
| Ahorro | ≈ 7 W | ≈ 2,5 W |

«Rendimiento» casi duplica el consumo en reposo.

## Aplicar el perfil desde el arranque

El paquete deja el servicio sin habilitar: D-Bus lo arranca cuando alguien lo consulta, normalmente la shell al
iniciar sesión. Hasta entonces, es decir, durante la pantalla del PIN del disco y el gestor de inicio de sesión, rige
el perfil por defecto del firmware. Para que el perfil guardado se aplique desde el arranque:

```bash
sudo systemctl enable power-profiles-daemon.service
```

O con el instalador: `sudo bash sistema/instalar.sh --solo energia`. Si ya estaba habilitado, el instalador no lo
toca, y `desinstalar.sh` no lo deshabilita.

El perfil se guarda en `/var/lib/power-profiles-daemon/state.ini`. power-profiles-daemon escucha `PrepareForSleep`
de logind y lo vuelve a aplicar al despertar de la suspensión.

## Caelestia y la tecla del fabricante

- Caelestia sigue los cambios hechos desde fuera (`powerprofilesctl`, otra aplicación): el botón resaltado de la
  ventana de la batería cambia al momento. En un portátil, el icono de la barra muestra la batería, no el perfil.
- En algunos portátiles Lenovo, **Fn + Q** cambia el perfil en el firmware. `ideapad_laptop` avisa del cambio de
  `platform_profile` y power-profiles-daemon lo recoge, así que Caelestia también lo muestra. Compruébelo pulsando
  Fn + Q y mirando `powerprofilesctl get`.

## Marcha atrás

```bash
sudo systemctl disable power-profiles-daemon.service   # vuelve a la activación por D-Bus
```
