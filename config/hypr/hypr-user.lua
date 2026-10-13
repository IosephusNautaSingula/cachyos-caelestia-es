-- SPDX-License-Identifier: GPL-3.0-or-later
-- Ajustes de usuario para la configuración de Hyprland (Lua) de los dots de Caelestia.
-- Ruta: ~/.config/caelestia/hypr-user.lua (la cargan los dots después de su configuración).

local bin = os.getenv("HOME") .. "/.local/bin/"

-- 1. PANTALLA: escala 1 en cualquier monitor (ajuste a su gusto: 1.25, 1.5…)
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })

-- 2. ENTRADA: teclado español y desplazamiento natural en el touchpad
hl.config({
    input = {
        kb_layout = "es",
        accel_profile = "adaptive",
        sensitivity = 0,                 -- entre -1.0 y 1.0
        touchpad = { natural_scroll = true, scroll_factor = 1 },
    }
})

-- 3. ASPECTO: sin pantalla de bienvenida ni logotipo de Hyprland
hl.config({
    misc = {
        disable_splash_rendering = true,
        disable_hyprland_logo    = true,
    }
})

-- 4. CERRAR SESIÓN: vuelve siempre al gestor de inicio de sesión (estacion-cerrar-sesion)
hl.bind("SUPER + SHIFT + E", hl.dsp.exec_cmd(bin .. "estacion-cerrar-sesion"))

-- 5. REPRODUCTORES (etiqueta music_player de los dots): efecto vidrio solo con opacidad, sin desenfoque ni sombra.
--    Spotify (XWayland) repinta la ventana entera mientras suena; sin blur la GPU trabaja bastante menos.
hl.window_rule({ match = { tag = "music_player", fullscreen = false }, opacity = "0.85 override 0.80 override", no_blur = true, no_shadow = true })

-- 6. VOLUMEN, MICRÓFONO Y BRILLO con aceleración al mantener pulsada la tecla (estacion-ajuste: 1 % por pulsación
--    suelta; de 0 a 100 en unos 2 s con repeat_delay 250 y repeat_rate 35). Sustituye a los atajos de los dots.
local ajuste = bin .. "estacion-ajuste "
local repetir = { locked = true, repeating = true }
for _, tecla in ipairs({ "XF86AudioRaiseVolume", "XF86AudioLowerVolume", "XF86MonBrightnessUp", "XF86MonBrightnessDown" }) do
    hl.unbind(tecla)
end
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd(ajuste .. "volumen subir"), repetir)
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd(ajuste .. "volumen bajar"), repetir)
-- Micrófono: Mayús + teclas de volumen
hl.bind("SHIFT + XF86AudioRaiseVolume", hl.dsp.exec_cmd(ajuste .. "micro subir"), repetir)
hl.bind("SHIFT + XF86AudioLowerVolume", hl.dsp.exec_cmd(ajuste .. "micro bajar"), repetir)
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd(ajuste .. "brillo subir"), repetir)
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd(ajuste .. "brillo bajar"), repetir)

-- 7. ACTIVACIÓN: una aplicación que pide el foco (p. ej. al recibir un mensaje) NO cambia de ventana ni de espacio de
--    trabajo; solo queda marcada como urgente (los dots ponen focus_on_activate = true). Para ir a ella, pulse su
--    notificación (parche 10 de caelestia/) o mire el indicador de urgente de la barra (parche 11).
hl.config({ misc = { focus_on_activate = false } })
-- 7b. Excepción: el navegador SÍ toma el foco al abrir un enlace desde otra aplicación (xdg-open).
--     Cambie la clase si usa otro navegador ("firefox", "chromium"…).
hl.window_rule({ match = { class = "^(zen)$" }, focus_on_activate = true })
