#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Prueba de activación (XWayland): crea una ventana X11 «prueba-activacion» y, cuando se le pide, solicita su propia
# activación con _NET_ACTIVE_WINDOW (lo que hace una aplicación que quiere el foco, p. ej. al recibir un mensaje).
# Hyprland la trata como una petición de activación: con misc:focus_on_activate=true le da el foco y cambia de espacio;
# con false solo la marca como urgente.
# Uso: activacion-x11.py SEGUNDOS_ANTES_DE_PEDIR SEGUNDOS_TOTALES
import ctypes, ctypes.util, sys, time

x = ctypes.CDLL(ctypes.util.find_library("X11"))
x.XOpenDisplay.restype = ctypes.c_void_p
x.XDefaultRootWindow.restype = ctypes.c_ulong
x.XCreateSimpleWindow.restype = ctypes.c_ulong
x.XInternAtom.restype = ctypes.c_ulong
for f in ("XDefaultRootWindow", "XCreateSimpleWindow", "XMapWindow", "XStoreName", "XFlush", "XInternAtom",
          "XSendEvent", "XDestroyWindow", "XCloseDisplay", "XSetClassHint"):
    getattr(x, f).argtypes = None

class XClientMessageEvent(ctypes.Structure):
    _fields_ = [("type", ctypes.c_int), ("serial", ctypes.c_ulong), ("send_event", ctypes.c_int),
                ("display", ctypes.c_void_p), ("window", ctypes.c_ulong), ("message_type", ctypes.c_ulong),
                ("format", ctypes.c_int), ("l", ctypes.c_long * 5)]
class XEvent(ctypes.Union):
    _fields_ = [("xclient", XClientMessageEvent), ("pad", ctypes.c_long * 24)]
class XClassHint(ctypes.Structure):
    _fields_ = [("res_name", ctypes.c_char_p), ("res_class", ctypes.c_char_p)]

antes, total = float(sys.argv[1]), float(sys.argv[2])
d = ctypes.c_void_p(x.XOpenDisplay(None))
root = ctypes.c_ulong(x.XDefaultRootWindow(d))
w = ctypes.c_ulong(x.XCreateSimpleWindow(d, root, 0, 0, 300, 120, 0, ctypes.c_ulong(0), ctypes.c_ulong(0x202020)))
x.XStoreName(d, w, b"prueba-activacion")
h = XClassHint(b"prueba-activacion", b"prueba-activacion")
x.XSetClassHint(d, w, ctypes.byref(h))
x.XMapWindow(d, w); x.XFlush(d)
print("ventana creada", flush=True)
time.sleep(antes)
ev = XEvent()
ev.xclient.type = 33  # ClientMessage
ev.xclient.send_event = 1
ev.xclient.display = d
ev.xclient.window = w
ev.xclient.message_type = x.XInternAtom(d, b"_NET_ACTIVE_WINDOW", 0)
ev.xclient.format = 32
ev.xclient.l[0] = 1  # 1 = la propia aplicación pide la activación
x.XSendEvent(d, root, 0, ctypes.c_long((1 << 19) | (1 << 20)), ctypes.byref(ev))  # SubstructureNotify|Redirect
x.XFlush(d)
print("activación pedida", flush=True)
time.sleep(max(0.0, total - antes))
x.XDestroyWindow(d, w); x.XFlush(d); x.XCloseDisplay(d)
print("ventana destruida", flush=True)
