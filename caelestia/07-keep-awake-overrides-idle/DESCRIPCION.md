<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# fix(idle): make the "Keep awake" toggle disable every idle timeout

**Target:** upstream (caelestia-dots/shell). Base: v2.5.0. Independent of the other patches.

## What

`modules/IdleMonitors.qml` now returns `enabled: false` for all idle monitors while the shell's own idle inhibitor
(the "Keep awake" card in the utilities, `IdleInhibitor.enabled`) is on.

`IdleInhibitor` is imported through a `qs.services as QsServices` alias because `Quickshell.Wayland`, also imported in
that file, has a type with the same name.

## Why

The toggle works by creating a Wayland idle inhibitor. Timeouts configured with `respectInhibitors: false` (a common
setup for the lock timeout, so that a video player does not prevent locking) ignore every inhibitor, including the
shell's own. The result is that "Keep awake" says "Preventing sleep mode" while the screen still locks or turns off.
An explicit user choice in the shell should win over that setting.

## How to test

```bash
patch -p1 < 07-keep-awake-overrides-idle.patch
```

1. In `shell.json`, add an idle timeout with a short `timeout` (e.g. 30 s) and `"respectInhibitors": false`.
2. Build and run; enable "Keep awake" in the utilities and wait: nothing happens.
3. Disable it and wait: the timeout fires as before.

Transparency: prepared with AI assistance and reviewed by a person.

---

# fix(idle): «Mantener activo» desactiva todos los temporizadores de inactividad

**Destino:** upstream. Base: v2.5.0. Independiente de los demás parches.

## Qué

Mientras «Mantener activo» (tarjeta de las utilidades) está encendido, `IdleMonitors.qml` desactiva todos los
temporizadores de inactividad.

## Por qué

Un temporizador con `respectInhibitors: false` (habitual en el de bloqueo, para que un reproductor no lo impida) ignora
también el inhibidor de la propia shell: la tarjeta dice «Evita la suspensión» y la pantalla se bloquea
igualmente. La elección explícita del usuario debe mandar.

## Cómo probar

Configure un temporizador corto con `respectInhibitors: false`, active «Mantener activo» y espere: no ocurre nada. Al
desactivarlo, el temporizador vuelve a actuar.
