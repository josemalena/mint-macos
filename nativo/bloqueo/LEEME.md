# mac-bloqueo: la pantalla de bloqueo de mint-macos

Lock Screen (⌃⌘Q) **dentro de la sesión**, como loginwindow: no pasa por `dm-tool lock` ni por el greeter de LightDM (que levanta otro X en otro VT
y es lo que asustaba con mensajes FATAL). Decisión de José, 19-10-2026. Por ahora es un binario aparte; en el paso (d) del plan se junta con
`mac-sesion` (`mac-sesion bloquear`, `mac-sesion bloquear --vigilar`).

**Estado: compilado y probado en Xvfb (casos 92, 93 y 94), NO instalado ni cableado.** No se activa hasta que José lo pida y lea el apartado de abajo.

## Qué hace

| Orden | Qué |
|---|---|
| `mac-bloqueo` | bloquea: supervisor + pantalla; sale cuando se desbloquea. Si ya hay un bloqueo, no hace nada |
| `mac-bloqueo --pantalla` | solo la pantalla (la lanza el supervisor) |
| `mac-bloqueo --vigilar` | el vigilante: si debe haber bloqueo y nadie lo sostiene, lo relanza (servicio de usuario con `Restart=always`) |
| `mac-bloqueo --liberar` | **salida de emergencia**, ver abajo |
| `mac-bloqueo --estado` | imprime `bloqueado` o `libre` (sale 0 si bloqueado) |

- **Fail-closed.** El estado `$XDG_RUNTIME_DIR/mint-macos/bloqueado` se escribe antes de dibujar nada. El supervisor (sin GTK) lanza la pantalla y,
  si cae de cualquier forma que no sea «clave correcta» (salida 0), la relanza al instante. Si matan al supervisor, queda el estado y el vigilante
  lo relanza.
- **Pantalla.** Una ventana sin gestor (override-redirect) por monitor con grab de teclado y ratón (reintenta sin parar, y si lo pierde lo retoma) y
  subida al frente cada medio segundo: ninguna notificación, menú ni el Dock queda encima, y nada de lo que se teclea llega a la app del frente
  (caso 93).
- **Clave.** PAM con el servicio `cinnamon-screensaver` del sistema (pam_unix → unix_chkpwd, sin setuid propio). La clave no se guarda: se pasa a PAM
  y se borra la copia. `pam_ayuda.c` declara la ABI mínima de PAM, así que no hace falta `libpam0g-dev` para compilar.
- **Aspecto.** Fondo de escritorio desenfocado, avatar de 144 px, nombre en negrita y «Enter Password» (cadena de LoginUICore). Las medidas son las del
  login de Catalina (slick-greeter-mac): **PROVISIONAL**, no hay captura del bloqueo de Catalina. Hay que compararlo apenas haya una (lo más fácil, por
  VNC en la MacBook de la esposa, que es High Sierra: marcarla «de High Sierra»). Los botones de abajo (Sleep, Restart…) no se dibujan: no se sabe si
  salen en el bloqueo.

## Salida de emergencia (leer antes de activarlo)

Si el bloqueo deja a José fuera (no entra la clave, la pantalla no responde…), desde **otro lado ya autenticado** se quita el bloqueo con un solo comando.
Ese otro lado pide la clave de la cuenta, así que no abre nada a un extraño.

**Por la consola.** `Ctrl+Alt+F3` (si no responde, `Ctrl+Alt+F4`), entrar con usuario y clave, y:

```
XDG_RUNTIME_DIR=/run/user/$(id -u) ~/.local/bin/mac-bloqueo --liberar
```

Imprime `liberado`. Volver a la sesión con `Ctrl+Alt+F7` (o `F1`, según donde esté la sesión gráfica; `loginctl list-sessions` y `loginctl show-session N -p VTNr` lo dicen).

**Por ssh desde otra computadora:**

```
ssh jmalena@macmini-1 'XDG_RUNTIME_DIR=/run/user/$(id -u) ~/.local/bin/mac-bloqueo --liberar'
```

(`macmini-1` es el nombre que ya se usa para llegar a la Mac mini; si no resuelve, la IP.)

`--liberar` borra primero el estado (para que el vigilante no relance nada), mata al supervisor y mata la pantalla. No toca la sesión: las ventanas
quedan como estaban. Si ni la consola ni ssh funcionan, queda reiniciar con el botón (se pierde lo no guardado).

**Para Infra, al pedirle el sí a José:** dárselo en el mismo mensaje, con estos dos comandos copiables, y comprobar antes de activar que `Ctrl+Alt+F3` abre
una consola en esta máquina y que ssh a la Mac mini entra.

## Cableado (de Infra, cuando se active)

- ⌃⌘Q, Apple ▸ Lock Screen y la esquina activa «Lock Screen» → `mac-bloqueo` (hoy llaman a `login/bloquear.sh` / `dm-tool lock`).
- `xss-lock` (lock al suspender y por inactividad) → `xss-lock -- mac-bloqueo`; que no lance otro mientras el suyo siga vivo (el supervisor ya ignora un segundo).
- Servicio de usuario `mac-bloqueo-vigilante.service`: `ExecStart=%h/.local/bin/mac-bloqueo --vigilar`, `Restart=always`, `RestartSec=1`.
- Quitar de `login/bloqueo.sh` el custom-screensaver-command de `dm-tool lock` cuando se active.

**Hecho (Infra, 19-10-2026), sin activar:** `login/bloqueo.sh --en-sesion` cablea todo lo de arriba (custom-screensaver-command →
`mac-bloqueo`, que cubre ⌃⌘Q, Lock Screen, la esquina y la suspensión; xss-lock → `mac-bloqueo`; `mac-bloqueo-vigilante.service`).
`login/bloqueo.sh` sin nada vuelve a `dm-tool lock` y quita el vigilante. `nativo/compilar-desde-head.sh` instala el binario.

## Pruebas

- 92: clave mala, matar la pantalla (vuelve en menos de 1 s) y clave buena. PAM de mentira por `LD_PRELOAD` (`pruebas/ayudantes/pam-falso.c`): solo en pruebas; el binario no trae ninguna clave ni atajo.
- 93: con Cinnamon real, la pantalla queda encima de una notificación y lo tecleado no llega a xed.
- 94: `--liberar`.

Pendiente: suspensión (lock on suspend), `mac-sesion bloquear`, el residente `org.mintmacos.Sesion1`, cambiar de usuario.
