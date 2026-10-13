<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# AutoFirma con el almacén de certificados (NSS) de Firefox o de Zen

AutoFirma (el cliente de firma electrónica de la Administración española) sabe buscar certificados en el almacén NSS
de **Firefox**, pero no conoce **Zen** y, con varios perfiles, puede elegir uno vacío. Esta guía hace que use el
almacén del perfil real de su navegador, que `afirma://` funcione desde la web y que el certificado nunca acabe en
sitios donde no debe. Componente: `estacion-autofirma-nss` (+ `estacion-autofirma-nss.path/.service`), la envoltura
`~/.local/bin/autofirma` y la entrada `config/applications/autofirma.desktop`.

## Requisitos

- `autofirma-bin` de AUR (descarga el zip **oficial** de firmaelectronica.gob.es y comprueba su suma; solo extrae el
  `.deb`, **sin** ejecutar su `postinst`, que metería una autoridad local en el almacén de todo el sistema) o
  `autofirma` de AUR (compila desde el código fuente oficial; pruébelo si alguna sede le falla con `-bin`). Revise el
  PKGBUILD antes de compilar:
  ```bash
  sudo pacman -S --needed --asdeps jre17-openjdk
  paru -S --needed autofirma-bin
  ```
- `nss` (`certutil`) y `openssl`.
- Firefox o Zen con su certificado personal **importado en el navegador** (Ajustes → Privacidad y seguridad →
  Certificados → Ver certificados → Sus certificados → Importar). Lo importa usted, tecleando la contraseña del
  `.p12`.
- Recomendado: **contraseña principal** del navegador (Ajustes → Privacidad y seguridad → Usar una contraseña
  principal). Sin ella, la clave privada de `key4.db` solo la protegen los permisos del fichero.

## Cómo comprobar si le afecta

```bash
grep -E '^\[|^Path=|^Default=' ~/.config/zen/profiles.ini ~/.mozilla/firefox/profiles.ini 2>/dev/null
# ¿En qué perfil está su certificado? (solo lectura; «u,u,u» = certificado personal con clave)
certutil -L -d "sql:$HOME/.config/zen/<perfil>"
ls ~/.afirma/AUTOFIRMA.afirma.log.xml 2>/dev/null && grep -o 'Fichero de perfiles[^<]*' ~/.afirma/*.xml | tail -2
```

Le afecta si usa Zen, si `profiles.ini` tiene varios perfiles (uno vacío marcado `Default=1` es frecuente) o si al
firmar AutoFirma solo le ofrece un `.p12` o ningún certificado.

## Dónde busca AutoFirma (versión 1.9)

En orden: almacén de Mozilla (el `profiles.ini` de Firefox o el que indique `AFIRMA_NSS_PROFILES_INI`), NSS
compartido (`~/.pki/nssdb`, `/etc/pki/nssdb`), PKCS#12 directo, PKCS#11 y DNIe.

**Detalle clave:** AutoFirma **solo lee** `AFIRMA_NSS_PROFILES_INI` si Java arranca con la propiedad
`-Des.gob.afirma.keystores.mozilla.UseEnvironmentVariables=true`. Sin ella ignora la variable, sigue buscando
`~/.mozilla/firefox/profiles.ini` y acaba en `~/.pki/nssdb` (donde solo está su propia autoridad).

## Pasos

1. Abra AutoFirma **una vez** desde el lanzador. Su lanzador crea por usuario `~/.afirma/Autofirma/`
   (`AutoFirma_ROOT.cer`, la autoridad local para el websocket de `afirma://`, y un `.pfx` para `127.0.0.1`).
   Ciérrelo.
2. **Cierre el navegador** (no se debe escribir su almacén con la aplicación abierta) y ejecute:
   ```bash
   estacion-autofirma-nss                 # NAVEGADOR=firefox estacion-autofirma-nss para forzar Firefox
   ```
   Hace dos cosas:
   - genera `${XDG_CONFIG_HOME:-~/.config}/estacion/afirma-profiles.ini`, un `profiles.ini` propio con **un único
     perfil** y su **ruta absoluta**: el que su navegador usa de verdad (el `Default=` de la sección `[Install…]` de
     su `profiles.ini`, no necesariamente el marcado `Default=1`);
   - importa `AutoFirma_ROOT.cer` en ese almacén como autoridad de confianza SSL (`certutil -A -t "C,,"`), para que
     la página pueda hablar con AutoFirma por `wss://127.0.0.1`.
3. Active la vigilancia (vuelve a importar la autoridad si AutoFirma la regenera):
   ```bash
   systemctl --user enable --now estacion-autofirma-nss.path
   ```
4. Que **toda** forma de lanzar AutoFirma lleve la variable **y** la propiedad:
   - `~/.local/bin/autofirma` (envoltura; `~/.local/bin` debe ir antes que `/usr/bin` en el `PATH`):
     ```sh
     export AFIRMA_NSS_PROFILES_INI="${XDG_CONFIG_HOME:-$HOME/.config}/estacion/afirma-profiles.ini"
     export JDK_JAVA_OPTIONS="-Des.gob.afirma.keystores.mozilla.UseEnvironmentVariables=true${JDK_JAVA_OPTIONS:+ $JDK_JAVA_OPTIONS}"
     exec /usr/bin/autofirma "$@"
     ```
   - `~/.local/share/applications/autofirma.desktop` (copia de la del sistema con las dos variables en `Exec=`),
     porque cuando el navegador abre `afirma://` lanza la entrada `.desktop`, no su terminal.
5. Asocie `afirma://` a esa entrada:
   ```bash
   xdg-mime default autofirma.desktop x-scheme-handler/afirma
   xdg-mime query default x-scheme-handler/afirma      # autofirma.desktop
   ```

## Verificación

```bash
estacion-autofirma-nss --comprobar      # perfil correcto y autoridad presente (navegador cerrado o abierto)
```

- Abra AutoFirma desde el lanzador → Firmar → un fichero cualquiera. Con contraseña principal, la pide **una vez**
  y le ofrece su certificado del almacén del navegador, sin pasar por un `.p12`. En el registro
  (`~/.afirma/AUTOFIRMA.afirma.log.xml`) deben aparecer «Fichero de perfiles de Firefox determinado a partir de la
  variable de entorno» y el almacén «NSS».
- Desde el navegador, en una página de prueba de AutoFirma de una sede oficial: Firmar → aceptar «abrir con
  AutoFirma» → contraseña principal → su certificado.

Escribir `autofirma` en una terminal **sin** la envoltura no usa este almacén (le falta la propiedad).

## El certificado: dónde puede estar y dónde no

- **Nunca** en dotfiles ni en copias sin cifrar. En chezmoi, ignore expresamente (`.chezmoiignore`):
  ```
  **/cert9.db
  **/key4.db
  **/cert8.db
  **/key3.db
  **/pkcs11.txt
  **/*.p12
  **/*.pfx
  .pki
  .afirma
  ```
  y compruébelo con `chezmoi add --dry-run --verbose <ruta>` («ignoring»).
- En la copia restic (cifrada) **sí** pueden entrar el perfil del navegador, `~/.pki/nssdb` y `~/.afirma`.
- Si guarda el `.p12`: carpeta `0700` y fichero `0600`, dentro de `/home` (cifrado si sigue
  [cifrado-luks2-tpm2-limine.md](cifrado-luks2-tpm2-limine.md)).
- Tras firmar alguna vez con el `.p12` directamente, compruebe que no quedan copias sueltas (`*.pem`, `*.key`) del
  certificado en su carpeta personal.
- El comprobador semanal (`estacion-comprobar-caelestia`) puede avisar si se rompe la integración y 30 días antes
  de que caduque un certificado personal del almacén (solo mira fecha y emisor).

## Marcha atrás

```bash
systemctl --user disable --now estacion-autofirma-nss.path
rm ~/.local/bin/autofirma ~/.local/share/applications/autofirma.desktop
rm "${XDG_CONFIG_HOME:-$HOME/.config}/estacion/afirma-profiles.ini"
# Con el navegador CERRADO, quitar la autoridad de AutoFirma de su almacén:
certutil -D -d "sql:$HOME/.config/zen/<perfil>" -n "AutoFirma ROOT"
sudo pacman -Rns autofirma-bin jre17-openjdk
```
