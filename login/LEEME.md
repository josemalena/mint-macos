# Pantalla de inicio de sesión (Catalina)

La pantalla de entrada de macOS Catalina, hecha con un fork de slick-greeter
(`slick-greeter-mac`, repo [mint-macos-greeter](https://github.com/josemalena/mint-macos-greeter))
que se instala **al lado** del slick-greeter de Mint, sin reemplazarlo. La misma
pantalla sirve para entrar y para desbloquear.

```
./desde-mac.sh --login                      # (en la raíz del repo, sin sudo, una vez) el fondo y la foto de la Mac
sudo login/instalar.sh                      # instala, SIN cambiar el login
sudo login/instalar.sh --activar            # además, lo pone como pantalla de inicio
sudo login/instalar.sh --deshacer           # quita todo y vuelve al de Mint
sudo login/instalar.sh --fuente DIR         # prueba un fork local en vez de clonar el publicado
login/bloqueo.sh [--deshacer]               # bloquear con esta pantalla (sin sudo)
```

**LightDM solo lee su configuración al arrancar**: después de `--activar` (o de
cambiar `/etc/lightdm/slick-greeter-mac.conf`) hay que reiniciar para verlo.

## Cómo se ve

- La lista de usuarios va sobre el fondo **claro** de Catalina y, al elegir a
  alguien con estilo oscuro, el fondo hace un fundido de 700 ms al **oscuro**.
  «Other…» queda claro. Quién es oscuro lo dice `usuarios-oscuros=` en
  `slick-greeter-mac.conf`, que `instalar.sh` escribe leyendo el estilo del usuario
  que corre sudo; sin esa clave todos son oscuros.
- Una flecha ‹ junto al campo de clave vuelve a la lista. Sleep, Restart y Shut Down
  se quedan abajo; Cancel no sale.
- El fondo del login sale del cuadro 0 (claro) y del 1 (oscuro) de `Catalina.heic`
  de la Mac, sin desenfocar; si el escritorio del sistema no es el de Catalina,
  `instalar.sh` usa el del sistema.

## El fondo es el tuyo (no el de Catalina)

Como la Mac, el login y el bloqueo enseñan el **fondo de escritorio de la persona**: en la lista, el de la última que
entró; al elegir a alguien o al bloquear, el de esa persona. Si no hay uno exportado (o el escritorio es un color liso),
sale el de Catalina de siempre (claro en la lista, oscuro según el estilo de la cuenta).

El greeter corre como `lightdm` y no lee tu `$HOME`, así que cada sesión deja una copia en
`/var/lib/mint-macos/login-fondos/<usuario>.jpg`:

```
sudo login/instalar.sh        # crea la carpeta (de root, sin escritura) y un archivo vacío por cuenta, que solo su dueño escribe
login/fondo.sh                # (sin sudo) instala el exportador y un servicio de usuario: copia el fondo al entrar y al salir
login/fondo.sh --quitar       # vuelta atrás para esa cuenta (el greeter vuelve a Catalina)
login/bloqueo.sh              # (sin sudo, otra vez) para que cada bloqueo deje el fondo al día antes de cambiar de pantalla
```

La copia es un JPEG de a lo sumo 3840 px y sin metadatos; solo se rehace si cambia la foto. «Último usuario» sale del
estado que el propio greeter ya guarda (`last-user`); no hay otra lista. Sin la carpeta, `fondo.sh` no hace nada.
Cambiar la foto del escritorio se nota en el login desde el siguiente bloqueo o cierre de sesión.

## Vuelta atrás: que nadie se quede sin entrar

La activación es **un archivo**, `/etc/lightdm/lightdm.conf.d/90-mint-macos-login.conf`,
y un comando que se instala antes que él. Si la pantalla de inicio no sale:
`Ctrl+Alt+F2`, entrar y

```
sudo login-mac-revertir
```

Quita ese archivo y reinicia LightDM (desde una sesión gráfica no lo reinicia: vale
para el próximo inicio). El binario, su `.conf` y el fondo quedan instalados y no
estorban.

## Qué instala

| Dónde | Qué |
|---|---|
| `/usr/local/sbin/slick-greeter-mac` | el greeter |
| `/usr/local/share/xgreeters/slick-greeter-mac.desktop` | para que LightDM lo conozca |
| `/usr/local/share/slick-greeter-mac/` | sus datos |
| `/etc/lightdm/slick-greeter-mac.conf` | fondos, usuarios oscuros |
| `/etc/lightdm/lightdm.conf.d/90-mint-macos-login.conf` | **lo activa** (el único que `login-mac-revertir` quita) |
| `xss-lock` (paquete) | el bloqueo por inactividad de `bloqueo.sh` |

Sin `--fuente`, se clona el fork en el hash fijo `GREETER_HASH` de `instalar.sh` (lo
que se instala es lo que se probó) dentro de `~/.cache/mint-macos/src/`. El hash
apunta a un commit del fork; si ese commit aún no está publicado, se instala con
`--fuente` apuntando a la copia local.

## Lo de Apple

Los fondos, la foto de la cuenta y los iconos de Sleep, Restart y Shut Down salen de
la Mac con `desde-mac.sh` (en solo lectura) a `~/.local/share/constanza/login/`.
**Nunca van al repo.**

## Bloquear con esta pantalla

`bloqueo.sh` hace que ⌃⌘Q, «Lock Screen» del menú Apple y el bloqueo antes de
suspender usen `dm-tool lock` (LightDM cambia al greeter y vuelve a la sesión al
poner la clave). La inactividad la toma `xss-lock` con el mismo tiempo de Cinnamon.
`--deshacer` devuelve el bloqueo de Cinnamon.
