<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# feat(notifs): clicking a notification takes you to its app

**Target:** upstream (caelestia-dots/shell). Base: v2.5.0. Independent of the other patches.

## What

Clicking a notification, either the popup or an entry in the sidebar history, now calls a new
`NotifData.activate()`, which does the first thing that applies:

1. **The notification is still alive and has a `default` action** (the freedesktop convention for "activate"):
   invoke it (e.g. a chat app opens the conversation), then focus the app's window. A second focus attempt 700 ms
   later covers apps that map their window late; the notification is closed then.
2. **It carries an `x-caelestia-log` hint**: open that log in the configured terminal
   (`general.apps.terminal`). Accepted values, and nothing else:
   - `journal:<unit>`: runs `journalctl -e -n 300 -u <unit>` (the unit name is validated against
     `[A-Za-z0-9@._-]+`);
   - an absolute path to a file inside the user's state directory (`$XDG_STATE_HOME`, default `~/.local/state`),
     without `..`: opens it with `less +G`.
   Arguments are always passed as a list to `execDetached`, never through a shell, because any client can send
   hints.
3. **Otherwise**: focus the app's window, matched against the window class/initial class using the notification's
   `desktop-entry` hint, its app name, and the `.desktop` id and `StartupWMClass`, even on another workspace. If the app
   has no window (tray-only or closed), launch it from its `.desktop` file. The `desktop-entry` hint is only used when
   it is a plain id (no `/` or `..`).

Other changes needed for this:

- The `default` action is kept apart in `NotifData.defaultAction` and no longer shown as a button (it is the click
  target); `actions` only holds the button actions. Actions with an empty label fall back to their identifier.
- `desktopEntry` and `logTarget` are saved in `notifs.json`, so focusing/launching the app and opening logs also work
  for notifications restored after a shell restart.
- In the sidebar history, a successful activation closes the sidebar. Clicks that are part of a swipe-to-dismiss
  (`|x| > 4 px`) or on a link in the body are ignored.

This replaces the behaviour behind `notifs.actionOnClick` (off by default), which only invoked the action when there
was exactly one. If maintainers prefer, the new behaviour can easily be gated behind that same option.

## Why

Clicking a notification is the most natural way to go to its source, and it is what other desktops do. Today the
click does nothing by default, and with `misc:focus_on_activate` disabled in Hyprland the app cannot raise itself
after its action runs, so the shell has to focus it. The `x-caelestia-log` hint lets local scripts (backups, updates,
system checks) send a notification that opens their log when clicked, without the shell running arbitrary commands.

## How to test

```bash
patch -p1 < 10-notification-click-to-app.patch
```

Build and run the shell, then:

```bash
# 1. default action: the click prints "default" in this terminal
notify-send --action=default=Open --action=other=Other "Test" "Click the body" &
# 2. log hints
notify-send -h string:x-caelestia-log:journal:systemd-journald.service "Journal" "Click to open the journal"
mkdir -p "${XDG_STATE_HOME:-$HOME/.local/state}/test" && date > "${XDG_STATE_HOME:-$HOME/.local/state}/test/log.txt"
notify-send -h "string:x-caelestia-log:${XDG_STATE_HOME:-$HOME/.local/state}/test/log.txt" "File" "Click to open the log"
notify-send -h string:x-caelestia-log:/etc/passwd "Rejected" "Outside the state dir: falls back to the app"
# 3. app focus: send from a terminal and click it while that terminal is on another workspace
notify-send -h string:desktop-entry:foot "Focus" "Click to focus foot"
```

Check that only the `Other` button is shown in case 1, that cases 2 open a terminal, that the `/etc/passwd` one does
not, and that the history entries in the sidebar behave the same after restarting the shell (except case 1, whose
action no longer exists). Remove the test file afterwards.

Transparency: prepared with AI assistance and reviewed by a person.

---

# feat(notifs): al pulsar una notificación se va a su aplicación

**Destino:** upstream. Base: v2.5.0. Independiente de los demás parches.

## Qué

Al pulsar una notificación (emergente o en el historial de la barra lateral) se llama a `NotifData.activate()`:

1. Si sigue viva y tiene acción `default`, la invoca y enfoca la ventana de la aplicación (con un segundo intento a
   los 700 ms).
2. Si lleva el hint `x-caelestia-log`, abre ese registro en el terminal configurado. Solo se aceptan
   `journal:<unidad>` (nombre validado) o una ruta absoluta dentro del directorio de estado del usuario
   (`$XDG_STATE_HOME`, por defecto `~/.local/state`) sin `..`. Los argumentos van en lista, nunca por una shell.
3. Si no, enfoca la ventana de la aplicación (por `desktop-entry`, nombre de la aplicación, id del `.desktop` o
   `StartupWMClass`) aunque esté en otro espacio de trabajo, o la lanza desde su `.desktop` si no tiene ventana.

La acción `default` ya no aparece como botón; `desktopEntry` y `logTarget` se guardan en `notifs.json`. Sustituye al
comportamiento de `notifs.actionOnClick` (desactivado por defecto), que solo invocaba la acción si había exactamente
una; si los mantenedores lo prefieren, puede condicionarse a esa misma opción.

Nota: en esta versión publicada la acción `default` se separa al construir la lista de acciones (`defaultAction`)
en lugar de filtrarla en la interfaz; así el parche no toca las líneas de colores de `Notification.qml` y aplica
también junto con el parche opcional `08`.

## Por qué

Pulsar una notificación es la forma natural de ir a su origen. Con `misc:focus_on_activate` desactivado en Hyprland,
la aplicación no puede traerse sola al frente tras su acción, así que lo hace la shell. El hint `x-caelestia-log`
permite que scripts locales (copias de seguridad, actualizaciones, comprobaciones) abran su registro al pulsar el aviso.

## Cómo probar

Aplique el parche, compile y arranque; envíe las notificaciones de prueba del apartado en inglés con `notify-send` y
compruebe cada caso (acción `default`, registro del journal, fichero en `~/.local/state`, ruta rechazada y foco de
la aplicación). Borre después el fichero de prueba.
