// SPDX-License-Identifier: GPL-3.0-or-later
// xdano: cuenta el daño que declara una ventana X (XWayland) durante N segundos, sin crear ventanas.
// Uso: xdano <segundos> [patrón de WM_CLASS, por defecto "potify" (Spotify)]
// Compilar: make xdano (necesita libx11 y libxdamage).
// Agrupa en «fotogramas» los rectángulos que llegan con menos de 4 ms de separación.
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/extensions/Xdamage.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>

static double ahora(void) { struct timeval t; gettimeofday(&t, NULL); return t.tv_sec + t.tv_usec / 1e6; }
static Window mejor = 0; static long mejor_area = 0;

static void buscar(Display *d, Window w, const char *pat) {
    XClassHint ch;
    if (XGetClassHint(d, w, &ch)) {
        int coincide = (ch.res_class && strstr(ch.res_class, pat)) || (ch.res_name && strstr(ch.res_name, pat));
        XWindowAttributes a;
        if (coincide && XGetWindowAttributes(d, w, &a) && a.map_state == IsViewable && (long)a.width * a.height > mejor_area) {
            mejor = w; mejor_area = (long)a.width * a.height;
        }
        if (ch.res_class) XFree(ch.res_class);
        if (ch.res_name) XFree(ch.res_name);
    }
    Window r, p, *h; unsigned n;
    if (XQueryTree(d, w, &r, &p, &h, &n)) { for (unsigned i = 0; i < n; i++) buscar(d, h[i], pat); if (h) XFree(h); }
}

int main(int argc, char **argv) {
    double dur = argc > 1 ? atof(argv[1]) : 10; const char *pat = argc > 2 ? argv[2] : "potify";
    Display *d = XOpenDisplay(NULL); if (!d) { fprintf(stderr, "sin DISPLAY\n"); return 1; }
    int ev, er; if (!XDamageQueryExtension(d, &ev, &er)) { fprintf(stderr, "sin XDamage\n"); return 1; }
    buscar(d, DefaultRootWindow(d), pat);
    if (!mejor) { fprintf(stderr, "no encuentro ventana visible con «%s»\n", pat); return 1; }
    XWindowAttributes a; XGetWindowAttributes(d, mejor, &a);
    XDamageCreate(d, mejor, XDamageReportRawRectangles);
    long rects = 0, frames = 0, completos = 0; double area = 0, max_frame_area = 0, frame_area = 0, ult = 0;
    double t0 = ahora(), fin = t0 + dur; int fd = ConnectionNumber(d);
    while (ahora() < fin) {
        if (!XPending(d)) { fd_set s; FD_ZERO(&s); FD_SET(fd, &s); struct timeval tv = {0, 20000}; select(fd + 1, &s, NULL, NULL, &tv); continue; }
        XEvent e; XNextEvent(d, &e);
        if (e.type == ev + XDamageNotify) {
            XDamageNotifyEvent *n = (XDamageNotifyEvent *)&e; double t = ahora();
            double ar = (double)n->area.width * n->area.height;
            if (t - ult > 0.004) { if (frames) { if (frame_area > max_frame_area) max_frame_area = frame_area; if (frame_area >= 0.9 * a.width * a.height) completos++; } frames++; frame_area = 0; }
            frame_area += ar; area += ar; rects++; ult = t;
        }
    }
    if (frames) { if (frame_area > max_frame_area) max_frame_area = frame_area; if (frame_area >= 0.9 * a.width * a.height) completos++; }
    double win = (double)a.width * a.height, seg = ahora() - t0;
    printf("ventana 0x%lx %dx%d · %.1f s · fotogramas %ld (%.1f/s) · rectángulos %ld · área media/fotograma %.1f %% de la ventana · máx %.1f %% · fotogramas de ventana completa %ld\n",
           mejor, a.width, a.height, seg, frames, frames / seg, rects, frames ? 100 * area / frames / win : 0, 100 * max_frame_area / win, completos);
    return 0;
}
