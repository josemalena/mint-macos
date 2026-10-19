# org.mintmacos.Calendario1

Los eventos del calendario de Thunderbird para el widget Calendar del Notification Center (Today).
Lo pidió José el 18-10-2026, y el contrato es el que aprobó Dev-Dock.

- **Servicio:** `mint-macos-calendario` (rust/calendario), solo lectura y sin root.
- **Activación:** la arranca D-Bus; sin llamadas se va a los 2 minutos.
- **Bus y ruta:** bus de sesión, nombre `org.mintmacos.Calendario1`, ruta `/org/mintmacos/Calendario1`.

## Interfaz

| | |
|---|---|
| `Eventos(x desde_ms, x hasta_ms) → aa{sv}` | Los eventos que se cruzan con el intervalo, en ms desde 1970 (UTC), ordenados por inicio |
| Señal `Cambio()` | Thunderbird escribió en su calendario: el widget vuelve a pedir `Eventos` |

Cada evento trae:
- `id` (s): `<calendario>/<evento>/<ocurrencia en ms>`, único por ocurrencia;
- `titulo` (s) y `lugar` (s): el `LOCATION` del evento, o el de su excepción;
- `inicio` (x) y `fin` (x): en ms desde 1970, UTC;
- `todo_el_dia` (b);
- `calendario` (s): el nombre del registro de Thunderbird;
- `color` (s): `#RRGGBB`, el del registro; sin color propio, uno de la paleta de Calendar de la Mac.

Sin Thunderbird, sin perfil o sin calendario, la lista viene vacía.

## De dónde sale

- **El perfil:** el de `~/.thunderbird/profiles.ini`, el `Default=1` o el primero con `calendar-data/`.
- **Los calendarios:** `prefs.js` → `calendar.registry.<id>.name|color|disabled`. Los apagados no salen.
- **Las bases:** `calendar-data/cache.sqlite` (los de CalDAV de iCloud) y `local.sqlite` (los locales), con este procedimiento:
  1. se copian con su `-wal` a `$XDG_RUNTIME_DIR/mint-macos-calendario-<pid>-<base>/` (0700);
  2. se abre la copia y no el original, que nunca se abre;
  3. la copia se borra al terminar la llamada.
- **Las tablas:**
  - `cal_events`: `event_start` y `event_end` en µs, con su zona en `event_start_tz`;
  - `cal_recurrence`: las líneas `RRULE`, `EXDATE` y `RDATE`;
  - `cal_properties`: el `LOCATION`;
  - las filas con `recurrence_id`: una ocurrencia cambiada, que reemplaza a la original.
- **Las recurrencias:** con el crate `rrule` 0.14. Se le pasan el `DTSTART` en la zona del evento y las líneas de Thunderbird tal cual. El tope es 2,000 ocurrencias por intervalo.
- **Las zonas:**
  - la de cada evento, por su nombre IANA (`America/Santo_Domingo`, `US/Eastern`);
  - `GMT-0400`, como `Etc/GMT+4`;
  - `floating` (y los de todo el día, que Thunderbird guarda como reloj a las 00:00), en la hora local de la máquina, así que un evento de todo el día del 19 empieza a las 00:00 del 19 en Santo Domingo.

**Ojo:** el widget ve lo que Thunderbird tiene guardado. Si Thunderbird no está abierto y no sincroniza, lo nuevo de iCloud no aparece hasta que lo haga.

## Privacidad

- Nada de títulos, lugares ni asistentes en el registro ni en el journal.
- Las pruebas usan un perfil de mentira, nunca una copia del real.
- La copia de trabajo vive solo durante la llamada, en `$XDG_RUNTIME_DIR` (0700).

## Avisos sin sondeo

Un hilo vigila `calendar-data/` con inotify (escrituras, cierres y renombres). Cada ráfaga de escrituras de Thunderbird da un solo `Cambio`, después de 1.5 s de calma.

## Costo (18-10-2026, con el calendario de José: 697 eventos en 4 calendarios)

- **Tiempo:** 0.35 s para leer un año, con la copia de 4 MB incluida, y 0.1 s para una semana.
- **RSS:** 8.6 MB mientras corre.
- **Sin llamadas:** se va a los 2 minutos.

## Pruebas

`cargo test -p mint-macos-calendario` corre con un perfil de mentira. Comprueba:
- un evento con zona cerca de la medianoche UTC;
- uno de todo el día que no se corre de día;
- una regla semanal con un `EXDATE` y una ocurrencia movida;
- un calendario apagado;
- `GMT-0400`;
- una regla semanal en Nueva York que cruza el 1-11-2026 (fin del horario de verano): sigue a las 10:00 de allá y pasa de 14:00 a 15:00 UTC;
- el orden;
- que la copia se borre.

Quitando el reemplazo de las excepciones, la prueba falla.
