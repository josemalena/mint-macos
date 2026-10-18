#!/usr/bin/env python3
"""Recorre org.mintmacos.Monitor1 como lo hará Activity Monitor (lo corre prueba.sh
en un bus aparte, contra el /proc de verdad, solo leyendo)."""
import os, subprocess, sys, time
from gi.repository import Gio, GLib

N, R = "org.mintmacos.Monitor1", "/org/mintmacos/Monitor1"
bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
fallas, hechas = [], [0]
senales = []
bus.signal_subscribe(N, N, None, R, None, 0, lambda c, s, r, i, n, p: senales.append((n, p.unpack())))
ctx = GLib.MainContext.default()

def comprobar(d, ok, x=""):
    hechas[0] += 1
    if not ok:
        fallas.append(d); print("  ✗", d, x)

def llamar(m, f=None, a=()):
    r = bus.call_sync(N, R, N, m, GLib.Variant(f, a) if f else None, None, 0, 20000, None).unpack()
    return r[0] if len(r) == 1 else r

def esperar(nombre, s, cond=lambda a: True):
    fin = time.time() + s
    while time.time() < fin:
        while ctx.pending(): ctx.iteration(False)
        for n, a in senales:
            if n == nombre and cond(a): return a
        time.sleep(0.05)

t0 = time.time()
llamar("Suscribir", "(u)", (1000,))
comprobar("Muestreado llega", esperar("Muestreado", 5) is not None)
print("  · primera muestra: %.2f s" % (time.time() - t0))
senales.clear()
esperar("Muestreado", 3)  # la segunda: ya hay porcentajes
p = llamar("Procesos", "(as)", ([],))
yo = os.getpid()
mio = next((x for x in p if x["pid"] == yo), None)
comprobar("hay procesos y estoy yo", len(p) > 20 and mio is not None, len(p))
comprobar("el mío trae cpu, memoria, hilos y disco", mio and "cpu" in mio and mio.get("memoria", 0) > 0 and mio["hilos"] >= 1 and "leido" in mio, mio)
uno = next((x for x in p if x["pid"] == 1), None)
comprobar("el de root: memoria sí, disco no", uno and uno.get("memoria", 0) > 0 and "leido" not in uno, uno)
comprobar("ninguna fila trae energía ni red", all("energia" not in x and "red_enviada" not in x for x in p))
cols = {c[0]: c for c in llamar("Columnas")}
comprobar("energía: sin fuente", cols["energia"][1] == "" and cols["energia"][2] == "sin fuente")
comprobar("red por proceso: sin fuente sin root", cols["red_enviada"][2] == "sin fuente sin root")
solo = llamar("Procesos", "(as)", (["pid", "cpu"],))
comprobar("Procesos con columnas pedidas", all(set(x) <= {"pid", "cpu"} for x in solo))
h = llamar("Historial", "(su)", ("cpu", 60))
comprobar("historial de cpu", len(h) >= 1 and all(0 <= v <= 100 for _, v in h), h)
comprobar("historial por núcleo", len(llamar("Historial", "(su)", ("cpu.0", 60))) >= 1)
rs = llamar("Resumen")
comprobar("resumen", rs.get("mem_fisica", 0) > 0 and "cpu_usuario" in rs and rs.get("nucleos", 0) >= 1, rs)
# Quit y Force Quit: solo lo propio.
s1 = subprocess.Popen(["sleep", "300"]); s2 = subprocess.Popen(["sleep", "301"])
comprobar("Salir de uno mío", llamar("Salir", "(i)", (s1.pid,)) is True)
comprobar("ProcesoTermino", esperar("ProcesoTermino", 5, lambda a: a[0] == s1.pid) is not None)
comprobar("ForzarSalida de uno mío", llamar("ForzarSalida", "(i)", (s2.pid,)) is True)
s1.wait(); s2.wait()
comprobar("Force Quit mata con SIGKILL", s2.returncode == -9, s2.returncode)
comprobar("al de root no", llamar("Salir", "(i)", (1,)) is False)
# Soltar: deja de medir.
llamar("Soltar")
time.sleep(1.5); senales.clear(); time.sleep(3)
while ctx.pending(): ctx.iteration(False)
comprobar("sin clientes no mide", not any(n == "Muestreado" for n, _ in senales), senales[:2])
print("  %s %d de %d comprobaciones" % ("✓" if not fallas else "✗", hechas[0] - len(fallas), hechas[0]))
sys.exit(1 if fallas else 0)
