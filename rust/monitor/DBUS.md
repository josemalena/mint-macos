# mint-macos-monitor: la interfaz D-Bus de Activity Monitor

El servicio de datos de Activity Monitor, sin ventana (José, 18-10-2026). La
ventana (Dev-Dock, en Vala) solo dibuja: el diseño de Catalina más una pestaña
«Resources» con gráficas como las de GNOME System Monitor (CPU por núcleo,
memoria y swap, red en el tiempo).

**Estado (18-10-2026): implementado** (`rust/monitor`, prueba de punta a punta en
`rust/monitor/prueba.sh`: 17 comprobaciones). Las columnas salen de las capturas de
Activity Monitor de High Sierra 10.13.6 que José dio como fuente para Catalina
(`~/.local/share/mint-macos/referencias/activity-monitor-20261018`, fuera del repo:
traen datos de terceros). Lo que Catalina tenga distinto, sin captura todavía.

**Lo que gasta** (medido con `prueba.sh`, binario release, ~390 procesos):
sin clientes **0 ticks en 30 s** (no lee nada) y 5.2 MB de RSS; con un cliente cada
2 s, **51 ticks en 30 s** (1.7 % de un núcleo) y 5.4 MB. La primera muestra tarda
0.08 s. Leer `smaps_rollup` (PSS) de todos los procesos costaba 0.62 s por muestra:
por eso la memoria es RssAnon y no PSS.

**Regla 0: sin fuente no se muestra.** Energía y red por proceso no tienen fuente
en Linux sin root: esas columnas existen en el contrato, pero vienen vacías y
marcadas (ver `Columnas`).

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
| Memoria por proceso | `RssAnon` de `/proc/<pid>/status` (lo más parecido al «Memory» de la Mac: su memoria propia, sin lo compartido con archivos) y `VmRSS` aparte | todos |
| Disco por proceso (bytes leídos y escritos) | `/proc/<pid>/io` | **solo los de José** (los de root piden ptrace) |
| Red por proceso | **sin fuente sin root** (haría falta eBPF o nethogs). Solo totales del sistema | — |
| Energía por proceso | **sin fuente** (powertop pide root y no da lo que la Mac llama «Energy Impact»). No se aproxima | — |
| CPU por núcleo, total | `/proc/stat` | gráficas |
| Memoria y swap | `/proc/meminfo` (MemTotal, MemAvailable, Cached, SwapTotal/SwapFree, presión: `/proc/pressure/memory`) | gráficas |
| Red del sistema | `/proc/net/dev` (sin `lo`) | gráficas |
| Disco del sistema | `/proc/diskstats` (discos enteros, no particiones) | gráficas |
| Batería y energía del sistema | `/sys/class/power_supply` si hay batería | pestaña Energy |

## Métodos

| Método | Entrada | Salida | |
|---|---|---|---|
| `Suscribir` | `u intervalo_ms` | — | Empieza a medir (1000-5000 ms). Uno por cliente: si el cliente se va del bus, cuenta como `Soltar` |
| `Soltar` | — | — | |
| `Procesos` | `as columnas` | `aa{sv}` | Una fila por proceso con las columnas pedidas (vacío = todas), de la última muestra |
| `Columnas` | — | `a(sss)` | (clave, fuente, motivo): de dónde sale cada columna, o por qué no hay |
| `Historial` | `s serie, u segundos` | `a(xd)` | (unix ms, valor) de una serie, hasta 600 s (ver «Series») |
| `Resumen` | — | `a{sv}` | Los paneles de abajo (ver «Paneles») |
| `Salir` | `i pid` | `b` | Quit: SIGTERM. false si no es de José, es el 1 o es el servicio |
| `ForzarSalida` | `i pid` | `b` | Force Quit: SIGKILL. Igual |

Los procesos de otros usuarios (root) no se cierran desde aquí: en la Mac eso pide
la clave de administrador; si hace falta, va por polkit y mac-polkit, en otra
versión. Sample Process (el menú del engranaje) no está.

## Las pestañas: columnas de `Procesos`

Una clave sin dato **no viene** (nunca un 0 inventado). `Columnas()` dice la fuente.

| Pestaña (captura) | Columna de la Mac | clave | tipo | |
|---|---|---|---|---|
| todas | Process Name | `nombre`, `icono` | s | el de la app si el proceso es la app (por Flatpak, por el ejecutable, por el guion de un intérprete o por StartupWMClass, contra el Exec de su .desktop). Un ayudante de la app (el binario `-bin` detrás del guion del Exec, o otro ejecutable en la carpeta propia de la app: los procesos de Firefox) lleva el `icono` de la app y su propio nombre. Si no, el nombre del proceso: completo aunque `comm` venga cortado en 15 («keyd-application-mapper», del argumento que empieza igual), y el del guion para un intérprete (`python3 …/ulauncher` → «ulauncher»). Los que reescriben su argv (Firefox: «Isolated Web Co») se quedan con el `comm`. Demonios e hilos del kernel, sin `icono`, como en la Mac |
| todas | PID / User | `pid`, `ppid` / `usuario` | i / s | |
| CPU | % CPU | `cpu` | d | 100 = un núcleo entero, como la Mac |
| CPU | CPU Time | `tiempo_cpu` | t | ms |
| CPU, Memory | Threads | `hilos` | u | |
| CPU | Idle Wake Ups | `despertares` | u | cambios de contexto voluntarios por segundo; solo procesos de José |
| Memory | Memory | `memoria` | t | RssAnon, bytes |
| Memory | Compressed Mem | `comprimida` | t | VmSwap (lo del proceso en swap/zram) |
| Memory | Ports | `puertos` | — | **sin fuente**: Linux no tiene puertos de Mach |
| Disk | Bytes Written / Bytes Read | `escrito` / `leido` | t | solo procesos de José |
| Disk | Kind | `tipo` | s | «64 bit» o «32 bit» (ELF); solo procesos de José |
| Energy | Energy Impact, Avg Energy Impact | `energia`, `energia_promedio` | — | **sin fuente** |
| Energy | App Nap, Requires High Perf GPU | `app_nap`, `gpu_alto_rendimiento` | — | **sin fuente** |
| Network | Sent/Rcvd Bytes, Sent/Rcvd Packets | `red_enviada`, `red_recibida`, `paquetes_enviados`, `paquetes_recibidos` | — | **sin fuente sin root** |
| (extra) | — | `memoria_residente`, `origen` | t, s | VmRSS; `flatpak` o `nativo` |

Energy en la Mac lista apps («App Name», «Applications in last 12 hours»), no
procesos: sin ninguna columna con fuente, la ventana puede enseñar la pestaña con
la lista de apps y las columnas vacías, o no enseñarla.

## Paneles: `Resumen`

| Pestaña | De la Mac | clave | |
|---|---|---|---|
| CPU | System / User / Idle | `cpu_sistema`, `cpu_usuario`, `cpu_ocioso` | % de /proc/stat entre dos muestras (sistema = system + irq + softirq; ocioso = idle + iowait) |
| CPU | Threads / Processes | `hilos`, `procesos` | |
| Memory | Physical Memory / Memory Used / Cached Files / Swap Used | `mem_fisica`, `mem_usada` (MemTotal − MemAvailable), `mem_cache` (Cached + Buffers), `swap_usada` | |
| Memory | App Memory / Wired Memory / Compressed | `mem_app` (AnonPages), `mem_wired` (SUnreclaim + KernelStack + PageTables + Unevictable), `mem_comprimida` (Zswap; no viene si no hay zswap) | equivalentes de Linux, no iguales |
| Memory | Memory Pressure | `mem_presion` | avg10 de /proc/pressure/memory |
| Disk | Reads in / Writes out, Data read / Data written | `disco_lecturas`, `disco_escrituras`, `disco_leido`, `disco_escrito` | desde que arrancó el sistema; los «/sec» salen de las series |
| Network | Packets in / out, Data received / sent | `red_paquetes_recibidos`, `red_paquetes_enviados`, `red_recibido`, `red_enviado` | sin lo |
| Energy | Remaining charge | `bateria_carga`, `bateria_estado` | solo si hay batería; Graphics Card sale de equipo.json; Time remaining y la gráfica de 12 h no están |
| — | | `nucleos`, `cuando` | |

## Series de `Historial`

`cpu`, `cpu.<n>` (por núcleo), `cpu.usuario`, `cpu.sistema` (la gráfica CPU LOAD),
`mem.usada`, `mem.cache`, `swap.usada`, `mem.presion`, `red.rx`, `red.tx`,
`red.paquetes_rx`, `red.paquetes_tx` (bytes y paquetes por segundo),
`disco.leido`, `disco.escrito`, `disco.lecturas`, `disco.escrituras` (por segundo).
Se guardan 10 minutos.

## Señales

| Señal | Argumentos | |
|---|---|---|
| `Muestreado` | `x unix_ms` | Hay una muestra nueva: la ventana pide `Procesos` y lo que esté enseñando |
| `ProcesoTermino` | `i pid` | Uno que se pidió cerrar ya no está (o quedó zombi) |

## Lo que no se hace

- Nada como root, ni medir sin un cliente conectado.
- Energía, puertos y red por proceso: no hay fuente; no se inventan ni se aproximan.
