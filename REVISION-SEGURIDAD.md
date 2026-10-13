<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# Revisión de seguridad y privacidad antes de publicar

Este informe dice **qué tipo** de dato se quitó o se convirtió en variable y dónde. No contiene ningún dato real.
Estado: preparado para revisión. No se ha publicado nada ni se ha creado ningún repositorio remoto.

## 1. Omitido por completo (sin sustituto)

- **Secretos:** claves, frases de paso, PIN, claves de recuperación, ficheros de clave y cabeceras LUKS.
- **Certificados y credenciales:** certificados (.p12 y almacenes NSS), contraseñas, credenciales SMB, clave del repositorio restic y tokens.
- **Gestor de contraseñas:** su configuración y los nombres de sus elementos; donde hace falta se dice «su gestor de contraseñas». También la línea del socket de su agente SSH en `uwsm/env` y en fish.
- **Registros privados:** logs, historiales, instantáneas, el registro técnico del proyecto privado y su lista de pendientes.
- **Identidad y marca:** cualquier mención de la organización o de personas, correos, el nombre privado del proyecto (en ficheros, unidades, variables y comentarios) y el usuario de GitHub.
- **Identidad visual que podía ser de marca:**
  - paquetes locales de tema SDDM y esquema de color;
  - logotipo e imágenes de Caelestia;
  - tipografías elegidas y el generador de la variante «LF» de una de ellas, con sus paquetes;
  - color de fondo de Hyprland y colores propios de VS Code.
- **Scripts de una sola vez fechados:** se omiten. Lo reutilizable de ellos está en `sistema/instalar.sh` y en `guias/`.
- **Fechas e historia:** fechas, «fases» y números de instantánea que contaban la historia del equipo. Las fechas de los ejemplos de los PR se cambiaron por otras neutras.
- **Código de terceros:** `vp.c`, `vp.h` y el XML del protocolo `wlr-virtual-pointer`, por tener otra licencia. Se explica cómo generarlos.
- **Paquete de un asistente de IA concreto:** quitado de la lista de paquetes. Las líneas de su carpeta en `.chezmoiignore` pasan a un comentario genérico.
- **Ejemplo de IP de la traducción:** el texto original de Caelestia (msgid, que no se puede cambiar) trae su propio ejemplo de red privada; la traducción usa una dirección de documentación de la RFC 5737 (`192.0.2.10/24`). El catálogo está completo (821 cadenas).

## 2. Convertido en variable (con ejemplo ficticio de rangos de documentación)

| Tipo de dato | Variable | Ficheros |
|---|---|---|
| Usuario de escritorio | `ESTACION_USUARIO` (y `USUARIO` en cifrado) | `sistema/estacion.conf.example`, `bin/estacion-copia-aviso`, `bin/spotify-spicetify-acl`, `instalar.sh`, `cifrado/cifrado.conf.example` |
| Rutas de /home | `$HOME`, `/home/*`, `/home/usuario`, `USUARIO` | scripts de `sistema/bin/`, `excluir.txt.example`, `config/spotify/config-xpui.ini.example`, guías |
| Nombre/IP del NAS, puerto, recurso SMB, punto de montaje, repositorio | `COPIA_NAS`, `COPIA_PUERTO`, `COPIA_RECURSO`, `COPIA_PUNTO_MONTAJE`, `COPIA_REPOSITORIO` | `estacion.conf.example`, `bin/estacion-copia`, `cifrado/cifrado.conf.example`, `cifrado-comun.sh`, guías de copias, restaurar y reinstalar |
| Rutas de credenciales (los ficheros no se publican) | `COPIA_CREDENCIALES`, `COPIA_CLAVE_RESTIC` | `estacion.conf.example`, `bin/estacion-copia`, `cifrado.conf.example` |
| Red de casa: UUID de la conexión, MAC del router, red CIDR | `CASA_CONEXION_UUID`, `CASA_ROUTER_MAC`, `CASA_RED`, `CASA_PUERTOS` | `networkmanager/90-estacion-cortafuegos-casa`, `estacion.conf.example`, `guias/endurecimiento.md` |
| UUID/PARTUUID de discos, LUKS y btrfs; tamaños; mapeos | `ESP_*`, `RAIZ_*`, `HOME_*` | `cifrado/cifrado.conf.example` y scripts `cifrado-*.sh`; `cifrado-inventario.sh` los propone leyendo el sistema |
| Número de serie y modelo del disco | `DISCO_SERIE`, `DISCO_MODELO` | `cifrado.conf.example`, `cifrado-comun.sh` |
| Etiqueta y número de serie del USB | `USB_ETIQUETA`, `USB_SERIE` | `cifrado.conf.example`, `cifrado-preparar.sh` |
| Nombre del equipo | `EQUIPO` | `cifrado.conf.example` |
| machine-id | se lee en tiempo de ejecución (`/etc/machine-id`) | `cifrado-comun.sh`, `cifrado-inventario.sh`, `cifrado-preparar.sh` |
| Identificador del touchpad | `TOUCHPAD_HID` (detección en `/sys/bus/acpi/devices`) | `estacion.conf.example`, `bin/estacion-touchpad`, `lib/comun.sh`, `instalar.sh`, guía del touchpad |
| Dirección PCI del controlador I2C | calculada desde sysfs, nunca fija | `bin/estacion-touchpad` |
| Adaptador Bluetooth, retroiluminación, perfiles de navegador | `BT_ADAPTADOR`, `AJUSTE_BACKLIGHT`, `ZEN_DIR`/`FIREFOX_DIR`/`NAVEGADOR` | `bin/estacion-bluetooth-reconectar`, `bin/estacion-ajuste`, `bin/estacion-autofirma-nss`, `bin/estacion-zen-tema` |
| Paquete local y rutas de PKGBUILD | `CAELESTIA_PKG`, `CAELESTIA_PKG_DIR`, `PKG_LOCALES_DIR` | `bin/estacion-comprobar-caelestia`, `bin/qt6-rebuild-aviso`, `bin/estacion-actualizar` |
| Horarios de los timers | valores por defecto neutros, distintos de los del equipo de origen | `systemd/*/*.timer`, `sistema/README.md`, `guias/copias-restic-smb.md` |

Los valores de ejemplo usan rangos de documentación y datos ficticios:

- IP: 192.0.2.x;
- red: 192.168.0.0/24;
- MAC: 00:00:5e:00:53:xx;
- UUID: 11111111-2222-…;
- nombres: `usuario`, `equipo`, `nas.local`, `MIUSB`.

Los scripts de cifrado se niegan a funcionar mientras queden UUID de ejemplo.

## 3. Hardware específico

- **Touchpad ELAN (IRQ desactivada):**
  - se instala solo si existe el dispositivo ACPI `TOUCHPAD_HID`;
  - los módulos del initramfs solo se instalan si además el controlador de pines es Tiger Lake;
  - la guía explica cómo comprobarlo.
  - El identificador ELAN06FA se mantiene como ejemplo y valor por defecto, porque el usuario lo pidió así.
- **TPM:** comprobaciones genéricas (`/dev/tpmrm0`, `systemd-cryptenroll --tpm2-device=list`), sin fabricante ni modelo.
- **Modelo del portátil:** no se nombra.

## 4. Cifrado en el sitio (riesgo de pérdida de datos)

- Ningún script que escriba en disco se ejecuta por defecto: sin argumentos, todos muestran la ayuda.
- El modo real exige a la vez `--ejecutar` y `--acepto-perdida-de-datos`, además de:
  - un aviso en mayúsculas sobre copia completa previa, modo de prueba y corriente conectada;
  - una confirmación tecleada.
- `cifrado.conf` solo se carga si nadie más ha podido cambiarlo: propietario y permisos correctos o, en exFAT/vfat, que coincida con `SHA256SUMS`.
- `.gitignore` impide subir `cifrado.conf`, sumas, registros y trabajos locales.

## 5. Pasada 1 (automática)

- **gitleaks** (`gitleaks dir --redact`) sobre todo el árbol: sin fugas.
- **Búsqueda de los datos concretos del equipo:** el escáner los saca del sistema en memoria y nunca los imprime.
  - Tipos buscados: usuario, hostname, machine-id, IP y prefijo de la red local, MAC, nombres y UUID de conexiones de red, dispositivos Bluetooth, UUID/PARTUUID y serie/modelo/etiqueta de discos, valores de la configuración del disco cifrado, nombre del NAS y usuario SMB, perfiles de navegador, correo y nombre de git, nombre real, organización, nombre privado del proyecto y modelo del equipo.
  - Más tres patrones genéricos: DNI, correos y `/home/<nombre>`.
  - En total, 38 tipos y 63 valores.
  - Primeras ejecuciones parciales, corregidas por cada parte:
    - traducción: una cadena con un ejemplo de red;
    - guías: etiqueta del USB y tamaño de reducción;
    - cifrado: valores por defecto que coincidían.
  - **Resultado final: 0 apariciones.**
- **Comprobaciones complementarias:**
  - el nombre privado del proyecto: 0;
  - todos los ficheros llevan `SPDX-License-Identifier: GPL-3.0-or-later`, salvo los JSON (cubiertos por `LICENSE`);
  - ningún `--noconfirm` ni permisos abiertos, aparte de textos que los prohíben;
  - sin ficheros ocultos (salvo `.gitignore`), binarios ni copias `.bak`.

## 6. Pasada 2 (manual e independiente)

Dos revisores sin acceso a la pasada 1 leyeron enteros los 154 ficheros que había entonces: 65 y 89. Antes recogieron por su cuenta los identificadores del equipo y los compararon sin mostrarlos.

- **Críticos (datos reales): 0.**
- **Dudosos: 8.** Todos se omitieron o neutralizaron, salvo el identificador del touchpad (ver el apartado 3):
  - referencias a un asistente de IA y a un gestor de contraseñas concretos en `.chezmoiignore`;
  - una frase que dejaba ver que había paquetes de marca;
  - tipografías y colores que podían ser de marca;
  - el tamaño de disco de un ejemplo, que coincidía con el real;
  - fechas y medidas de ejemplo del día real;
  - horarios por defecto idénticos a los del equipo de origen;
  - lista de exclusiones que describía las aplicaciones usadas (ahora son ejemplos comentados).
- **Menores y de coherencia: todos corregidos.**
  - Lectura de la configuración como texto, en vez de `source`, en `cifrado-inventario.sh`.
  - Comprobación de permisos o suma antes de cargar `cifrado.conf`.
  - Nota sobre la lectura del PKGBUILD local.
  - Permisos 0755 de `/etc/estacion` en la guía de copias.
  - Banderas de la prueba loop en la guía.
  - Descripción de `cifrado-copiar.sh`.
  - `.gitignore` para las configuraciones reales.
  - Coherencia entre partes:
    - nombre del paquete `caelestia-shell-es`;
    - fichero de referencia del TPM;
    - opción `--ayuda` del instalador.
- **Aceptado a conciencia:** el nombre del proyecto, «Estación», es una palabra común y no identifica por sí sola.

## 7. Pruebas

- `bash -n` / `sh -n` en los 35 scripts: 0 fallos.
- `instalar.sh --prueba`, `instalar.sh --prueba --usuario`, `desinstalar.sh --prueba` y `desinstalar.sh --prueba --usuario`:
  - sin root;
  - código 0;
  - sin ningún cambio en `/etc`, `/usr/local`, `/usr/lib/systemd`, `/var/lib`, `~/.local/bin`, `~/.config/systemd` ni `~/.local/state`, comprobado con `find -newer`.
- Scripts de cifrado sin argumentos: muestran la ayuda y no tocan nada.
- Parches de Caelestia: los 11 aplican en orden y sin desplazamiento (`patch -F0`) sobre los ficheros originales de v2.5.0. Las sumas de `PKGBUILD.example` coinciden, y el
  catálogo español pasa `msgfmt -c` con 821 cadenas traducidas.
- Construcción con `PKGBUILD.example` (conjunto por defecto: 01, 02, 04, 06, 07, 09, 10 y 11): `makepkg` y su
  `check()` correctos.
- Parche 10 probado en una sesión real con ese build, sin instalarlo: la shell arranca sin errores; al pulsar una
  notificación con acción «default» se invoca la acción y se enfoca la ventana de la aplicación en otro espacio de
  trabajo; sin acción, se enfoca la ventana. Al cerrarse la notificación quedan avisos «TypeError … of null» del
  desmontaje de la notificación, los mismos que da la versión sin reescribir.

## 8. Pendiente de decisión o prueba del usuario antes de enviar

- **Revisión final:** leer este árbol antes de cualquier envío. Para la publicación, crear un repositorio nuevo con un autor y un correo de git que no le identifiquen, si así lo desea; este árbol no lleva metadatos de git propios.
