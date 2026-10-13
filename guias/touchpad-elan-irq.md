<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# Touchpad ELAN (I2C-HID) que desaparece al arrancar: «controller timed out» por una IRQ desactivada

Algunos portátiles (por ejemplo, varios Lenovo con touchpad ELAN, ACPI `ELAN06FA` y similares, conectado por I2C a un
controlador Intel LPSS) arrancan **a veces sin touchpad**. Pasa sobre todo cuando el arranque se detiene antes de
cargar el sistema, como al **pedir el PIN o la frase de un disco cifrado**. Componentes: el fragmento de mkinitcpio
`/etc/mkinitcpio.conf.d/20-estacion-touchpad.conf` (el arreglo) y `estacion-touchpad` (+ `estacion-touchpad.service`
y `/usr/lib/systemd/system-sleep/estacion-touchpad`), una red de seguridad.

## Requisitos

- Kernel de Arch/CachyOS con mkinitcpio (o `limine-mkinitcpio`). Initramfs basado en systemd o udev: da igual.
- Variable `TOUCHPAD_HID` en `/etc/estacion/estacion.conf` (p. ej. `TOUCHPAD_HID="ELAN06FA"`).

## Cómo comprobar si le afecta

1. ¿El touchpad es I2C-HID y cuál es su HID ACPI?
   ```bash
   ls /sys/bus/acpi/devices/ | grep -iE '^(ELAN|SYNA|MSFT|ALPS)'
   cat /sys/bus/acpi/devices/ELAN06FA:00/status        # 15 = presente y activo
   ls -l /sys/bus/i2c/devices/ | grep -i elan          # i2c-ELAN06FA:00 → …/i2c_designware.N/…
   grep -A1 -i touchpad /proc/bus/input/devices
   ```
2. ¿El controlador I2C es Intel LPSS (`intel_lpss_pci` + `i2c_designware` + `idma64`)? ¿Qué pinctrl tiene?
   ```bash
   readlink -f /sys/bus/i2c/devices/i2c-ELAN06FA:00      # la ruta pasa por el dispositivo PCI del controlador
   lspci -k | grep -A3 -i 'serial io i2c'                # Kernel driver in use: intel-lpss
   lsmod | grep -E '^pinctrl_|^intel_lpss|^i2c_hid|^hid_multitouch'
   ```
3. En un arranque **sin** touchpad, el registro del kernel:
   ```bash
   journalctl -k -b | grep -E 'nobody cared|Disabling IRQ|controller timed out|i2c_hid|ELAN'
   ```
   La firma del fallo, en este orden:
   - `irq NN: nobody cared (try booting with the "irqpoll" option)` con `handlers: idma64_irq, i2c_dw_isr`;
   - `Disabling IRQ #NN`;
   - más tarde, `i2c_designware …: controller timed out` → `i2c_hid_acpi …: reading report descriptor failed` →
     `probe … failed with error -110`.
4. Compare con un arranque **bueno** (`journalctl -k -b -1 …`): no aparece «nobody cared» y el touchpad se registra
   en pocos segundos.
5. La IRQ compartida del controlador: `grep -E 'idma64|i2c_designware' /proc/interrupts`.

Si ve esa secuencia, le afecta.

## Causa

La IRQ del controlador I2C la comparten `idma64` (DMA) e `i2c_designware`. Si el touchpad todavía **no se ha
inicializado** pasados unos segundos del arranque (en el equipo analizado, unos 8 s), llegan interrupciones que
ningún manejador reconoce; el kernel las declara «nobody cared» y **desactiva la IRQ**. Sin IRQ, el controlador ya no
avisa de nada y la primera lectura del touchpad da «controller timed out».

¿Por qué solo a veces? En los arranques buenos el touchpad se inicializa antes de ese límite. Con el disco cifrado,
el módulo del touchpad (`i2c_hid_acpi`) no está en el initramfs y se carga **después del PIN**: si tarda en
teclearlo, el touchpad llega tarde. En un live (más lento) puede pasar lo mismo, lo que confunde el diagnóstico.

Reiniciar el controlador (unbind/bind del dispositivo PCI en `intel-lpss`) vuelve a pedir la IRQ: por eso funciona
como remedio en caliente.

### Hipótesis descartadas (y por qué)

| Hipótesis | Por qué se descartó |
|---|---|
| El cifrado o el TPM | Falla igual abriendo con la frase (sin TPM) y con TPM2 + PIN; systemd no usa el TPM en el initrd fuera del desbloqueo. Lo que importa es el **tiempo** hasta cargar el módulo, no el cifrado. |
| Un cambio de kernel, firmware o paquetes | El registro de pacman no mostraba cambios de sistema entre arranques buenos y malos. |
| Ahorro de energía del controlador («se duerme» antes de la primera lectura) | Experimento: con el controlador ya suspendido y esperas de 2, 4, 6, 10 y 20 s antes de cargar `i2c_hid_acpi`, funcionó siempre (0 timeouts). No hace falta regla udev `power/control=on`. La tormenta de IRQ solo se da en el arranque. |
| Arranque en frío frente a reinicio | Fallaban ambos. |
| El aviso de frecuencia del bus (p. ej. 400000 Hz) | Aparece también en los arranques buenos. |
| Hardware averiado | El touchpad responde siempre tras reiniciar el controlador. |
| Interruptor del touchpad (Fn+Fx) | No existe en el controlador de plataforma de esos equipos. |

## Pasos

### 1. Arreglo: el touchpad en el initramfs

Así se inicializa en el initrd (en torno a 1–2 s), **antes** de pedir el PIN:

```bash
# Ajuste el pinctrl al de su equipo (lsmod | grep pinctrl_): tigerlake, alderlake, cannonlake, icelake, meteorlake…
echo 'MODULES+=(pinctrl_tigerlake intel_lpss_pci i2c_hid_acpi hid_multitouch)' \
  | sudo tee /etc/mkinitcpio.conf.d/20-estacion-touchpad.conf
sudo limine-mkinitcpio            # o: sudo mkinitcpio -P
```

Compruebe que cada initramfs lleva los módulos (y, si tiene el disco cifrado, que sigue llevando
`systemd-cryptsetup` y `etc/crypttab`):

```bash
for i in /boot/*/*/initramfs-* /boot/initramfs-*.img; do [ -e "$i" ] || continue
  echo "== $i"; lsinitcpio "$i" | grep -E 'i2c-hid-acpi|hid-multitouch|intel-lpss-pci|pinctrl|systemd-cryptsetup|etc/crypttab'
done
```

Antes, por prudencia, haga una instantánea (`sudo snapper -c root create -d "Antes del touchpad en el initramfs"`) y
compruebe que aparece en Limine → Snapshots.

### 2. Red de seguridad: estacion-touchpad

Si al arrancar o al volver de suspensión falta el touchpad, reinicia su controlador I2C (hasta 5 intentos) y lo
registra con `journalctl -t estacion-touchpad`. La dirección PCI del controlador **no** es fija: se calcula en cada
ejecución siguiendo sysfs desde `i2c-${TOUCHPAD_HID}:00` (o desde el nodo ACPI) hasta su antecesor PCI.

```bash
estacion-touchpad --diagnostico                 # muestra HID, dispositivo I2C, controlador PCI y driver; no cambia nada
sudo systemctl enable estacion-touchpad.service
ls -l /usr/lib/systemd/system-sleep/estacion-touchpad
```

El gancho de suspensión lanza la recuperación con `systemd-run --no-block` para que salga del grupo de control de
`systemd-suspend.service` (que es oneshot y mataría el proceso al terminar) y no retrase el despertar.

Equivalente manual del reinicio del controlador (sustituya la dirección por la suya):

```bash
d=$(readlink -f /sys/bus/i2c/devices/i2c-ELAN06FA:00)      # sube por sysfs hasta el dispositivo PCI
while [ "$d" != / ] && ! basename "$d" | grep -qE '^[0-9a-f]{4}:[0-9a-f]{2}:[0-9a-f]{2}\.[0-7]$'; do d=$(dirname "$d"); done
PCI=$(basename "$d"); echo "$PCI"                           # compruebe que es del tipo 0000:00:xx.x
echo "$PCI" | sudo tee /sys/bus/pci/drivers/intel-lpss/unbind
sleep 2; echo "$PCI" | sudo tee /sys/bus/pci/drivers/intel-lpss/bind
```

## Verificación

Tras reiniciar (teclee el PIN despacio a propósito, más de 10 s):

```bash
journalctl -k -b | grep -cE 'nobody cared|controller timed out'     # 0
journalctl -k -b | grep -iE 'ELAN.*(input|hid-multitouch)'           # registrado en el initrd, antes del PIN
journalctl -b -t estacion-touchpad                                    # vacío: la red de seguridad no tuvo que actuar
systemctl status estacion-touchpad.service --no-pager
```

Pruebe también varias suspensiones (cierre la tapa) y compruebe el touchpad al volver.

## Marcha atrás

```bash
sudo rm /etc/mkinitcpio.conf.d/20-estacion-touchpad.conf && sudo limine-mkinitcpio
sudo systemctl disable estacion-touchpad.service
sudo rm /usr/lib/systemd/system-sleep/estacion-touchpad
```
