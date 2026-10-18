# mint-macos-monitor: la interfaz D-Bus de Activity Monitor

El servicio de datos de Activity Monitor, sin ventana (José, 18-10-2026). La
ventana (Dev-Dock, en Vala) solo dibuja: el diseño de Catalina más una pestaña
«Resources» con gráficas como las de GNOME System Monitor (CPU por núcleo,
memoria y swap, red en el tiempo).

**Estado: propuesta (18-10-2026), sin implementar.** Las columnas exactas de cada
pestaña salen de las capturas de Catalina, que todavía no hay: lo marcado
**(hipótesis)** se confirma o cambia con ellas.

## Dónde vive

| | |
|---|---|
| Bus | de sesión |
| Nombre / objeto / interfaz | `org.mintmacos.Monitor1` en `/org/mintmacos/Monitor1` |
| Arranque | activación por D-Bus; se va solo a los 2 min sin clientes |
| Peso | mide **solo mientras haya un cliente** (`Suscribir`); sin clientes no lee nada. Cada muestra lee /proc una vez para todos. nice 19 |

## Fuentes (sin sudo)

| Dato | De dónde | Para quién |
|---|---|---|
| CPU por proceso (%) | `/proc/<pid>/stat` (utime + stime) entre dos muestras | todos |
| Hilos, usuario, nombre, comando | `/proc/<pid>/status`, `cmdline`, `comm` | todos |
| Memoria por proceso | RSS de `/proc/<pid>/statm` para todos; PSS de `smaps_rollup` para los de José (los de otros usuarios no se pueden leer) | todos / solo de José |
| Disco por proceso (bytes leídos y escritos) | `/proc/<pid>/io` | **solo los de José** (los de root piden ptrace) |
| Red por proceso | **no hay fuente sin root** (haría falta eBPF o nethogs). Solo totales del sistema | — |
| Energía por proceso | **no hay fuente** (powertop pide root y no da lo que la Mac llama «Energy Impact»). **(hipótesis)** una aproximación con CPU y despertares (`voluntary_ctxt_switches`), dicha como aproximación, o la pestaña sin esa columna | — |
| CPU por núcleo, total | `/proc/stat` | gráficas |
| Memoria y swap | `/proc/meminfo` (MemTotal, MemAvailable, Cached, SwapTotal/SwapFree, presión: `/proc/pressure/memory`) | gráficas |
| Red del sistema | `/proc/net/dev` (sin `lo`) | gráficas |
| Disco del sistema | `/proc/diskstats` (discos enteros, no particiones) | gráficas |
| Batería y energía del sistema | `/sys/class/power_supply` si hay batería | pestaña Energy |

## Métodos

| Método | Entrada | Salida | |
|---|---|---|---|
| `Suscribir` | `u intervalo_ms` | — | Empieza a medir (1000-5000 ms; 2000 por defecto). Uno por cliente: si el cliente se va del bus, cuenta como `Soltar` |
| `Soltar` | — | — | |
| `Procesos` | `as columnas` | `aa{sv}` | Una fila por proceso con las columnas pedidas (ver abajo), de la última muestra |
| `Historial` | `s serie, u segundos` | `a(xd)` | (unix ms, valor) de una serie: `cpu`, `cpu.<n>`, `mem.usada`, `mem.cache`, `swap.usada`, `red.rx`, `red.tx`, `disco.leido`, `disco.escrito`. Se guardan 10 min |
| `Resumen` | — | `a{sv}` | Lo de abajo de cada pestaña de Catalina: % de sistema/usuario/ocioso, hilos y procesos; memoria física, usada, cache, swap y presión; totales de disco y red **(hipótesis: los campos exactos según las capturas)** |
| `Salir` | `i pid` | `b` | Quit: SIGTERM. false si el proceso no es de José |
| `ForzarSalida` | `i pid` | `b` | Force Quit: SIGKILL. false si no es de José |
| `Muestra` | `i pid` | `s` | Sample Process: la pila de cada hilo (`/proc/<pid>/task/*/stack` no se puede leer sin root; **(hipótesis)** `gdb -batch` si está instalado). Puede quedar fuera |

Los procesos de otros usuarios (root) no se cierran desde aquí: en la Mac eso pide
la clave de administrador; si hace falta, va por polkit y mac-polkit, en otra
versión.

## Columnas de `Procesos`

Cada fila es `a{sv}`; una clave sin dato **no viene** (nunca un 0 inventado).

| clave | tipo | pestaña de Catalina |
|---|---|---|
| `pid`, `ppid` | i | todas |
| `nombre` | s | todas («Process Name»: el nombre de la app si tiene .desktop, si no `comm`) |
| `icono` | s | todas (el de su .desktop, por WM_CLASS o por el ejecutable) |
| `usuario` | s | todas |
| `cpu` | d | CPU («% CPU», 100 = un núcleo, como la Mac) |
| `tiempo_cpu` | t | CPU («CPU Time», ms) |
| `hilos` | u | CPU («Threads») |
| `despertares` | u | CPU («Idle Wake Ups» **(hipótesis)**: cambios de contexto voluntarios por segundo) |
| `memoria` | t | Memory («Memory», bytes: PSS si se puede, si no RSS) |
| `memoria_fuente` | s | `pss` o `rss` |
| `comprimida` | t | Memory («Compressed Mem»: la parte en zram/swap, `VmSwap`) |
| `puertos` | — | Memory («Ports»): no existe en Linux; no viene |
| `leido`, `escrito` | t | Disk («Bytes Read/Written»; solo procesos de José) |
| `tipo` | s | todas («Kind»: **(hipótesis)** `64-bit`; o el origen: apt, flatpak, AppImage) |

## Señales

| Señal | Argumentos | |
|---|---|---|
| `Muestreado` | `x unix_ms` | Hay una muestra nueva: la ventana pide `Procesos` y lo que esté enseñando |
| `ProcesoTermino` | `i pid` | Uno que se pidió cerrar ya no está |

## Lo que no se hace

- Nada como root, ni medir sin un cliente conectado.
- Red y energía por proceso: no hay fuente; no se inventan.
