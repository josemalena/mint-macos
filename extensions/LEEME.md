# Extensiones de Cinnamon

```
./instalar.sh              # copia las extensiones a ~/.local/share/cinnamon/extensions
./instalar.sh --encender   # además las enciende, sin apagar las que ya estén
```

Antes de tocar `enabled-extensions` respalda en
`~/.local/share/respaldos/extensiones-<fecha>/` y deja ahí **`volver.sh`**, que deja
todo como estaba.

| Extensión | Qué hace |
|---|---|
| `cmdtab@macos` | el ⌘Tab de Catalina; encendida reemplaza el selector de Cinnamon, apagada vuelve el de Cinnamon |
| `misioncontrol@macos` | ⌃↑ todas las ventanas, ⌃↓ las de la app del frente, ⌃← ⌃→ entre escritorios (necesita la capa `[control]` de `keyd/default.conf`) |
| `entrada@macos` | la espera de Catalina al iniciar sesión (abajo) |
| `magiclamp.sh` y `parches/` | el efecto genio de [Magic Lamp](https://github.com/klangman/CinnamonMagicLamp) (de klangman, no es de este repo): se baja en un commit fijo y se le aplica `parches/magiclamp-sin-icono-va-al-dock.patch` (una ventana sin ícono en el panel va al Dock) |

## entrada@macos: la espera al iniciar sesión

Después de poner la clave, Catalina deja el fondo solo y muestra la barra de menú con
un fundido cuando todo lo que se espera ya está. La extensión oculta el panel **por
opacidad** (no con `hide()`: así no cambia el espacio de las ventanas ni salta nada)
y lo muestra con un fundido de 500 ms cuando llega:

1. el marcador `$XDG_RUNTIME_DIR/mint-macos-listo` con el id de **esta** sesión
   (`$XDG_SESSION_ID`), que escribe `fynder-desktop` cuando iCloud montó y el Finder
   leyó el disco; o, mientras `fynder-desktop` no lo escriba,
2. iCloud montado (si `~/Desktop` vive ahí), `~/Desktop` legible y 1.5 s de aire.

**Tope de 150 s** (`TOPE_S` en `extension.js`): si nada llega, la barra sale igual,
nunca se queda sin ella. Solo actúa al entrar a la sesión: el marcador
`mint-macos-entrada` guarda el id de la sesión que ya pasó, así que reiniciar Cinnamon
o encender la extensión con la sesión andando no toca la barra. El Dock (Plank) no está
cubierto por la espera.
