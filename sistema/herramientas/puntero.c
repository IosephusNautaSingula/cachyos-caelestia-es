// SPDX-License-Identifier: GPL-3.0-or-later
// puntero: mueve el cursor como un ratón real (protocolo wlr-virtual-pointer), sin abrir ventanas.
// Compilar: make (genera protocolo/vp.c y vp.h con wayland-scanner; vea el README).
// Uso: puntero X1 Y1 [X2 Y2 | clic | clicd | clicc | pulsa | suelta ...]  — recorre los puntos en línea recta (25 pasos de 8 ms entre cada par);
//      «clic» pulsa y suelta el botón izquierdo donde esté el cursor; «clicd»/«clicc», el derecho/central;
//      «pulsa» y «suelta», el izquierdo por separado (para arrastrar: pulsa, puntos, suelta).
// A diferencia de hl.dsp.cursor.move, genera eventos de entrada normales: cambia el foco del puntero (enter/leave).
#include <wayland-client.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <linux/input-event-codes.h>
#include "protocolo/vp.h"

static struct zwlr_virtual_pointer_manager_v1 *gestor;
static struct wl_seat *asiento;

static void global(void *d, struct wl_registry *r, uint32_t n, const char *i, uint32_t v) {
    if (!strcmp(i, zwlr_virtual_pointer_manager_v1_interface.name)) gestor = wl_registry_bind(r, n, &zwlr_virtual_pointer_manager_v1_interface, 1);
    else if (!strcmp(i, wl_seat_interface.name) && !asiento) asiento = wl_registry_bind(r, n, &wl_seat_interface, 1);
}
static void global_fuera(void *d, struct wl_registry *r, uint32_t n) {}
static const struct wl_registry_listener reg = {global, global_fuera};
static uint32_t ms(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec * 1000 + t.tv_nsec / 1000000; }

int main(int argc, char **argv) {
    if (argc < 3) { fprintf(stderr, "uso: puntero X1 Y1 [X2 Y2 | clic ...]\n"); return 2; }
    // Tamaño de la superficie de coordenadas: el de la pantalla en píxeles lógicos (PUNTERO_ANCHO x PUNTERO_ALTO).
    const char *ea = getenv("PUNTERO_ANCHO"), *eh = getenv("PUNTERO_ALTO");
    const uint32_t W = ea ? (uint32_t)atoi(ea) : 1920, H = eh ? (uint32_t)atoi(eh) : 1080;
    struct wl_display *d = wl_display_connect(NULL); if (!d) { fprintf(stderr, "sin Wayland\n"); return 1; }
    struct wl_registry *r = wl_display_get_registry(d); wl_registry_add_listener(r, &reg, NULL); wl_display_roundtrip(d);
    if (!gestor) { fprintf(stderr, "el compositor no ofrece wlr-virtual-pointer\n"); return 1; }
    struct zwlr_virtual_pointer_v1 *p = zwlr_virtual_pointer_manager_v1_create_virtual_pointer(gestor, asiento);
    double x = atof(argv[1]), y = atof(argv[2]);
    zwlr_virtual_pointer_v1_motion_absolute(p, ms(), (uint32_t)x, (uint32_t)y, W, H); zwlr_virtual_pointer_v1_frame(p); wl_display_flush(d); usleep(20000);
    for (int a = 3; a < argc; a += 2) {
        const char *t = argv[a];
        int boton = !strcmp(t, "clicd") ? BTN_RIGHT : !strcmp(t, "clicc") ? BTN_MIDDLE : BTN_LEFT;
        int pulsar = !strcmp(t, "clic") || !strcmp(t, "clicd") || !strcmp(t, "clicc") || !strcmp(t, "pulsa");
        int soltar = !strcmp(t, "clic") || !strcmp(t, "clicd") || !strcmp(t, "clicc") || !strcmp(t, "suelta");
        if (pulsar || soltar) {
            if (pulsar) { zwlr_virtual_pointer_v1_button(p, ms(), boton, WL_POINTER_BUTTON_STATE_PRESSED); zwlr_virtual_pointer_v1_frame(p); wl_display_flush(d); usleep(40000); }
            if (soltar) { zwlr_virtual_pointer_v1_button(p, ms(), boton, WL_POINTER_BUTTON_STATE_RELEASED); zwlr_virtual_pointer_v1_frame(p); wl_display_flush(d); usleep(40000); }
            a -= 1; continue;
        }
        if (a + 1 >= argc) break;
        double tx = atof(argv[a]), ty = atof(argv[a + 1]);
        for (int s = 1; s <= 25; s++) {
            double cx = x + (tx - x) * s / 25.0, cy = y + (ty - y) * s / 25.0;
            zwlr_virtual_pointer_v1_motion_absolute(p, ms(), (uint32_t)(cx + 0.5), (uint32_t)(cy + 0.5), W, H);
            zwlr_virtual_pointer_v1_frame(p); wl_display_flush(d); usleep(8000);
        }
        x = tx; y = ty;
    }
    wl_display_roundtrip(d); zwlr_virtual_pointer_v1_destroy(p); wl_display_flush(d); wl_display_disconnect(d);
    return 0;
}
