<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# Endurecimiento razonable de un portátil con CachyOS

Medidas que no rompen el uso habitual de escritorio. Componente `endurecimiento` de `instalar.sh` (sistema/).

## Requisitos

- NetworkManager, systemd-resolved y `ufw` (`sudo pacman -S --needed ufw`).
- Para las reglas «solo en casa»: el UUID de la conexión de casa y la MAC del router, en `/etc/estacion/estacion.conf`:
  ```bash
  CASA_CONEXION_UUID="11111111-2222-3333-4444-555555555555"   # nmcli -g UUID,NAME connection show
  CASA_ROUTER_MAC="00:00:5e:00:53:01"                         # ip neigh show $(ip -4 route show default | awk '{print $3; exit}')
  CASA_RED="192.168.0.0/24"
  ```

## Cómo comprobar si le afecta

```bash
sudo ufw status verbose
sudo ss -tulpn                                  # servicios a la escucha
resolvectl status | grep -E 'Protocols|DNS Servers'
sysctl fs.protected_fifos fs.protected_regular dev.tty.ldisc_autoload kernel.kexec_load_disabled
ls -l /sys/class/powercap/intel-rapl:0/energy_uj   # ¿legible por todos?
cat /etc/udev/rules.d/*powercap* 2>/dev/null
```

## Pasos

### 1. ufw: entrada denegada; reglas de casa solo en casa

```bash
sudo ufw default deny incoming && sudo ufw default allow outgoing && sudo ufw logging low
sudo ufw enable
```

Lo que solo debe abrirse en casa (p. ej. Spotify Connect, 57621 tcp/udp desde la red local) lo gestiona el
*dispatcher* de NetworkManager `/etc/NetworkManager/dispatcher.d/90-estacion-cortafuegos-casa` (root, `0755`):
en cada cambio de red comprueba que la conexión activa es la de casa (**UUID**) **y** que la puerta de enlace tiene
la **MAC del router** de casa. Si las dos cosas coinciden, añade las reglas con un comentario identificable; si no,
las quita. Así, en otra red que también use el mismo rango (hoteles, cafeterías), no entra nada.

```bash
journalctl -t estacion-cortafuegos -n 5
sudo ufw status | grep estacion-casa
```

### 2. sysctl (`/etc/sysctl.d/90-estacion.conf`)

```
fs.protected_fifos = 2
fs.protected_regular = 2
dev.tty.ldisc_autoload = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
kernel.kexec_load_disabled = 1
```

Protección de FIFOs y ficheros en directorios con *sticky bit*, sin carga de disciplinas TTY bajo demanda, sin
redirecciones ICMP (un portátil no es un router) y sin `kexec` (irreversible hasta reiniciar). **No** se tocan los
espacios de nombres de usuario (los usan Electron, VS Code, Spotify, Flatpak) ni `ptrace`.

```bash
sudo sysctl --system
```

### 3. LLMNR fuera y DNS cifrado oportunista

`/etc/systemd/resolved.conf.d/90-estacion.conf`:

```
[Resolve]
LLMNR=no
```

`/etc/systemd/resolved.conf.d/91-estacion-dot.conf` (opcional):

```
[Resolve]
DNS=1.1.1.1#cloudflare-dns.com 1.0.0.1#cloudflare-dns.com 2606:4700:4700::1111#cloudflare-dns.com
FallbackDNS=9.9.9.9#dns.quad9.net 2620:fe::9#dns.quad9.net
DNSOverTLS=opportunistic
Domains=~.
```

`opportunistic` cifra cuando puede; si una red (portal cautivo) bloquea DNS sobre TLS, cae a DNS normal en vez de
dejarle sin conexión. Los nombres `.local` (NAS, impresoras) siguen por mDNS. Elija el proveedor que prefiera.

```bash
sudo systemctl restart systemd-resolved
```

### 4. MAC estable por red

`/etc/NetworkManager/conf.d/90-estacion-mac.conf`:

```
[connection]
wifi.cloned-mac-address=stable
```

Cada red nueva ve una MAC distinta pero **estable** para esa red (no le rastrean entre redes y el router de cada sitio
le reconoce). La de casa puede conservar la real (útil si reserva IP en el router):

```bash
sudo nmcli connection modify "$CASA_CONEXION_UUID" 802-11-wireless.cloned-mac-address permanent
sudo nmcli general reload conf
```

### 5. RAPL (consumo de energía) sin canal lateral

Mission Center («Run Additional Setup») crea `99-powercap.rules`, que deja `energy_uj` de RAPL **legible por
todos**. Eso permite el canal lateral PLATYPUS (**CVE-2020-8694**): un proceso sin privilegios puede inferir datos
midiendo el consumo. Alternativa: legible solo por root y el grupo `energia`.

```bash
sudo groupadd -r energia && sudo gpasswd -a "$USER" energia
sudo mv /etc/udev/rules.d/99-powercap.rules /etc/udev/rules.d/99-powercap.rules.bak.$(date +%F)-rapl   # si existe
```

`/etc/udev/rules.d/90-estacion-powercap.rules` (`GROUP`/`MODE` de udev no se aplican a atributos de `/sys`, por eso
`RUN`):

```
SUBSYSTEM=="powercap", KERNEL=="intel-rapl*", RUN+="/usr/bin/chgrp energia /sys%p/energy_uj", RUN+="/usr/bin/chmod 0440 /sys%p/energy_uj"
```

```bash
sudo udevadm control --reload && sudo udevadm trigger --subsystem-match=powercap
```

El grupo surte efecto al volver a iniciar sesión. El comprobador semanal puede avisar si reaparecen reglas udev
ajenas (p. ej. si Mission Center vuelve a crear la suya).

### 6. Otros

- `fwupd` para el firmware: `fwupdmgr refresh && fwupdmgr get-updates` (aplicar solo con el cargador). Ojo: actualizar
  la BIOS o el dbx cambia el PCR 7 (vea [cifrado-luks2-tpm2-limine.md](cifrado-luks2-tpm2-limine.md)).
- `passim` (caché de firmware en la red local, dependencia de fwupd) escucha en todas las interfaces y se anuncia por
  mDNS; fwupd funciona sin él: `sudo systemctl mask --now passim.service`.
- Su usuario fuera del grupo `nopasswdlogin` si no usa inicio sin contraseña: `sudo gpasswd -d "$USER" nopasswdlogin`.

## Verificación

```bash
sudo ufw status verbose | grep 'deny (incoming), allow (outgoing)'
sudo ss -tulpn | grep -E ':5355|:27500' || echo "LLMNR y passim no escuchan"
resolvectl status | grep -i 'DNSOverTLS'
sudo -u nobody cat /sys/class/powercap/intel-rapl:0/energy_uj   # Permiso denegado
cat /sys/class/powercap/intel-rapl:0/energy_uj                  # con su usuario (grupo energia): un número
nmcli -f GENERAL.HWADDR device show wlan0                       # MAC distinta fuera de casa
```

## Marcha atrás

Borre (o restaure el `.bak` de) cada fichero añadido y recargue: `sudo sysctl --system`,
`sudo systemctl restart systemd-resolved`, `sudo nmcli general reload conf`, `sudo udevadm control --reload`.
`sudo ufw disable` desactiva el cortafuegos; `sudo systemctl unmask passim.service` lo devuelve.
