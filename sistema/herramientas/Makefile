# SPDX-License-Identifier: GPL-3.0-or-later
# Herramientas de prueba en C. Necesita: wayland (wayland-scanner, libwayland-client), libx11, libxdamage.
# El XML del protocolo wlr-virtual-pointer-unstable-v1 NO se incluye (otra licencia): descárguelo del proyecto
# wlr-protocols (https://gitlab.freedesktop.org/wlroots/wlr-protocols, unstable/wlr-virtual-pointer-unstable-v1.xml)
# y déjelo en protocolo/, o indique su ruta con XML=…
XML ?= protocolo/wlr-virtual-pointer-unstable-v1.xml
CFLAGS ?= -O2 -Wall

all: puntero xdano

protocolo/vp.h: $(XML)
	wayland-scanner client-header $< $@

protocolo/vp.c: $(XML)
	wayland-scanner private-code $< $@

puntero: puntero.c protocolo/vp.c protocolo/vp.h
	$(CC) $(CFLAGS) -o $@ puntero.c protocolo/vp.c -lwayland-client

xdano: xdano.c
	$(CC) $(CFLAGS) -o $@ xdano.c -lX11 -lXdamage

clean:
	rm -f puntero xdano protocolo/vp.c protocolo/vp.h

.PHONY: all clean
