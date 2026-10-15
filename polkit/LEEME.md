# Agente de polkit estilo Catalina

El diálogo de «Enter your password to allow this» de la Mac, para todo lo que pide permiso con
`pkexec`: Startup Disk, Modifier Keys, Sharing, y lo ajeno (Mint, el sistema) con el botón «Authorize».
Capturas de Catalina: 1.11.51 PM, 1.16.09 PM, 1.33.32 PM y 12.21.58 AM.

- **User Name** siempre editable y preescrito con el nombre completo (el GECOS de `passwd`). Se acepta el
  usuario (`jmalena`) o el nombre completo con sus espacios, sin importar mayúsculas, siempre que polkit lo
  autorice; se resuelve **antes** de autenticar.
- **Clave mala** (o usuario que no es nadie): la ventana solo se sacude, sin mensaje, y se vuelve a intentar.
- **El botón y el ícono** salen de dos anotaciones de la acción en su `.policy`:
  `org.mintmacos.boton` (el texto) y `org.mintmacos.icono` (el id del panel de System Preferences, cuyo
  ícono va como insignia del candado). Sin ellas, «Authorize» y solo el candado.
- **La clave** solo la toca `PolkitAgent.Session` (`.response()`) y su ayudante setuid. Este código la deja en
  el campo mientras se teclea, la borra al terminar y no la guarda, escribe ni imprime.

## Cómo funciona

`agente.py` implementa por D-Bus la interfaz `org.freedesktop.PolicyKit1.AuthenticationAgent` y se
registra en polkitd para la sesión de login del proceso. No usa `PolkitAgent.Listener`: PyGObject no sabe
completar el callback asíncrono de su método virtual y el proceso se cae. Polkit permite **un solo agente por
sesión**: si Cinnamon ya tiene el suyo, este sale con código 3 sin hacer nada.

`mint-macos-polkit` es el supervisor: relanza el agente si se cae y, si falla 3 veces en 60 s, devuelve el de
Cinnamon en caliente (`Eval` de `imports.ui.polkitAuthenticationAgent.init()`). Así nadie se queda sin poder
autenticar. Login (lightdm) y `sudo` en terminal no dependen de polkit.

## Instalar, activar y quitar (nada pide root)

```
./instalar.sh             copia el agente y deja el arranque con la sesión (inofensivo: sale solo si hay otro)
./instalar.sh --activar   apaga el agente de Cinnamon (enable-polkit-agent=false): surte efecto cuando
                          Cinnamon vuelva a arrancar. Reiniciar Cinnamon necesita el sí de José.
./instalar.sh --quitar    lo deja todo como estaba y vuelve a registrar el de Cinnamon sin reiniciar
```

Las anotaciones viven en los `.policy` de `settings/` y se instalan con sus `instalar-root.sh` (hay que
volver a correrlos para que el agente lea el botón y el ícono nuevos). Date & Time usa una acción del
sistema (timedated), que no se puede anotar: sale como «Authorize».

## Cómo se probó sin tocar la sesión de José

Con una **sesión de logind aparte**: `ssh localhost` crea otra sesión, el agente se registra para esa y
el diálogo sale en un Xephyr. Ahí se comprobó, con `pkexec /bin/true`: el registro, el diálogo, un usuario
inexistente (sacude sin llegar a PAM), el login y el nombre completo (con y sin mayúsculas) con clave mala
(llegan a PAM y sacude), y Cancel (pkexec sale con «Not authorized» y el agente sigue vivo). No se probó
una clave **buena**: eso solo lo puede hacer José con la suya.
