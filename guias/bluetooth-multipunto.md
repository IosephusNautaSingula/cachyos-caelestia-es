<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# Auriculares Bluetooth multipunto (PC + móvil) sin tocar BlueZ

Objetivo: unos auriculares **multipunto** conectados a la vez al PC y al móvil; que el PC los conecte **solo cuando
se enciende el Bluetooth** (no en bucle, para respetar que los desconecte a mano) y que el Bluetooth **recuerde si
estaba encendido o apagado** entre reinicios. Todo sin parchear BlueZ. Componentes: `estacion-bluetooth-reconectar`
(servicio de usuario), `estacion-bluetooth-recordar` (servicio de sistema) y **blueman** como agente.

## Requisitos

- `bluez`, `bluez-utils`, PipeWire con `pipewire-audio` (trae `libspa-bluez5`) y `blueman`:
  ```bash
  sudo pacman -S --needed bluez bluez-utils blueman pipewire-audio
  ```
- Auriculares con **multipunto** activado (en muchos modelos se activa desde la app del fabricante en el móvil).

## Cómo comprobar si le afecta

```bash
bluetoothctl show | grep -E 'Powered|Name'
bluetoothctl devices Paired
bluetoothctl info <MAC> | grep -E 'Paired|Trusted|Connected'
grep -E '^\s*AutoEnable' /etc/bluetooth/main.conf
journalctl -b -u bluetooth | grep -E 'without agent|Access denied|Connection refused'
```

Síntomas típicos:

- **Se conectan y se cortan a los 2 s** con «Authentication attempt without agent» / «Access denied»: no hay un
  **agente** registrado y el dispositivo aún no es de confianza. Algunas interfaces (p. ej. Caelestia/quickshell)
  emparejan sin registrar agente.
- «Hands-Free Voice gateway failed connect: Connection refused (111)»: siguen ocupados por el móvil y el multipunto
  está desactivado. Actívelo, o apague el Bluetooth del móvil para probar.
- **El Bluetooth vuelve encendido tras reiniciar** aunque lo apagó: el botón de la interfaz cambia `Powered` por
  D-Bus (BlueZ no lo guarda) y BlueZ, con `AutoEnable=true`, enciende siempre al arrancar.

## Pasos

### 1. Agente permanente: blueman

blueman-applet registra un agente que **pregunta** al emparejar (a diferencia de `bt-agent` de bluez-tools como
servicio, que solo puede «aceptar todo»). Arranca solo por `/etc/xdg/autostart`. Para que no duplique el icono de la
bandeja ni toque el encendido:

```bash
gsettings set org.blueman.general plugin-list "['!StatusNotifierItem', '!PowerManager', '!KillSwitch']"
```

Tras emparejar, marque el dispositivo como de confianza: `bluetoothctl trust <MAC>`.

**No** use el complemento *AutoConnect* de blueman para esto: reconecta los servicios configurados **cada 60 s**, así
que si desconecta los auriculares a mano para usarlos solo en el móvil, el PC se los vuelve a quitar en un minuto.

### 2. Recordar encendido/apagado: AutoEnable=false + estacion-bluetooth-recordar

```bash
sudo cp -a /etc/bluetooth/main.conf /etc/bluetooth/main.conf.bak.$(date +%F)-autoenable
sudo sed -i -E 's/^#?\s*AutoEnable\s*=.*/AutoEnable=false/' /etc/bluetooth/main.conf
grep -E '^AutoEnable' /etc/bluetooth/main.conf || echo 'añada AutoEnable=false en [Policy]'
sudo systemctl enable estacion-bluetooth-recordar.service
sudo systemctl restart bluetooth
```

`estacion-bluetooth-recordar.service` va `After=`/`PartOf=bluetooth.service`: **guarda** el estado al pararse
(apagado del equipo o reinicio de bluetoothd) en `/var/lib/estacion-bluetooth/estado` y lo **restaura** al arrancar,
con espera a que el adaptador responda y 5 reintentos. Sin estado guardado, enciende. `rfkill` no sirve para esto:
con el bloqueo, la interfaz no puede volver a encender.

### 3. Reconectar solo al encender: estacion-bluetooth-reconectar

Las opciones de BlueZ (`[Policy] ReconnectUUIDs`, `ReconnectAttempts`, `ReconnectIntervals`) solo reconectan tras
**perder** el enlace, y `ResumeDelay` tras suspender; **no** hay ajuste para «conectar al encender». El servicio de
usuario escucha `org.bluez.Adapter1.Powered → true` por D-Bus (`gdbus monitor`, sin root) y conecta **una vez**
(3 intentos × 5 s) los dispositivos **emparejados y de confianza** que no estén conectados; también al iniciar la
sesión si ya está encendido. Sin bucle: respeta la desconexión manual.

```bash
systemctl --user enable --now estacion-bluetooth-reconectar.service
```

Detalle técnico: en una tubería, `gdbus monitor` guarda su salida en un búfer y la señal llega tarde o nunca; por eso
se lanza con `stdbuf -oL`.

## Verificación

```bash
bluetoothctl power off; sleep 2; bluetoothctl power on        # se reconectan en unos segundos
journalctl --user -u estacion-bluetooth-reconectar -n 5; journalctl -t estacion-bluetooth -n 5
pactl list cards short | grep bluez; pactl list sinks short | grep bluez     # perfil a2dp-sink y su códec
bluetoothctl disconnect <MAC>     # espere más de 60 s: NO deben volver solos
sudo systemctl restart bluetooth  # el estado (encendido/apagado) se conserva
```

Y en un reinicio real: apague el Bluetooth, reinicie y compruebe que sigue apagado
(`journalctl -b -t estacion-bluetooth`: «estado restaurado: apagado»).

Para depurar emparejamientos, `sudo btmon` graba todo el tráfico HCI. **Esa grabación puede contener claves de
enlace**: permisos `0600` y nunca a dotfiles ni a ningún sitio público.

## Marcha atrás

```bash
systemctl --user disable --now estacion-bluetooth-reconectar.service
sudo systemctl disable --now estacion-bluetooth-recordar.service
sudo cp -a /etc/bluetooth/main.conf.bak.<fecha>-autoenable /etc/bluetooth/main.conf && sudo systemctl restart bluetooth
gsettings reset org.blueman.general plugin-list
```
