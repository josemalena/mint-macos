# Parche de Muffin: los tres semáforos en hover a la vez

`0001-semaforos-hover-en-grupo.patch` es un solo cambio a `src/ui/frames.c` (+30 líneas) de Muffin 6.6.3
(linuxmint/muffin, etiqueta 6.6.3, la que trae Mint «zena»). Aplica limpio a esa etiqueta (`git apply --check`).

- `meta_ui_frame_paint`: si el control con el puntero es cerrar, minimizar o maximizar y el estado es prelight, los tres
  botones se pintan en prelight.
- `meta_ui_frame_update_prelit_control`: al entrar o salir de uno de los tres, se redibujan los cuatro controles
  (cerrar, minimizar, maximizar, restaurar).

**No está compilado ni probado**: faltan las dependencias de compilación (`dpkg-checkbuilddeps debian/control`) y no se
reemplaza el Muffin de Mint sin el sí de José. Las ventanas con barra propia (GTK) las cubre el módulo
`nativo/gtk-semaforos`, no este parche.

Receta (en una carpeta de trabajo, fuera del repo):

    git clone --depth 1 --branch 6.6.3 https://github.com/linuxmint/muffin && cd muffin
    git apply <repo>/tema/muffin/0001-semaforos-hover-en-grupo.patch
    dch --local +semaforos "semáforos en hover a la vez"     # 6.6.3+zena → versión propia mayor que la de Mint
    dpkg-buildpackage -us -uc -b
    # instalar los .deb de libmuffin0 y muffin; apt-mark hold muffin libmuffin0 si Mint no debe pisarlo

## 0002 — la hoja de macOS: posición por perfil y bloqueo de la madre

`0002-hoja-posicion-por-perfil-y-bloqueo-de-la-madre.patch` toca `src/core/constraints.c` y `src/core/events.c` (sobre 0001 o sobre la etiqueta
sola: no comparten archivos). Aplica a las ventanas DIALOG + MODAL + transient (attach-modal-dialogs en true) con `WM_WINDOW_ROLE`
**«mint-macos-hoja»**, aunque sean de otro proceso:

- **Posición** (`constrain_modal_dialog`): en X, centrada sobre el marco de la madre (como ya hace Muffin). En Y depende del perfil de
  macos.json (`$XDG_RUNTIME_DIR` y después `$XDG_CONFIG_HOME` /mint-macos/macos.json, clave «version»): hasta Catalina **colgada del borde
  de abajo de la barra de título** de la madre (High Sierra 10.13.6, capturas del 27-10-2026); desde Monterey (monterey, sequoia, macos-27…)
  **centrada en Y sobre el marco completo**, sin subir de ese borde (informe de Open/Save en Monterey 12.7.6, 28-10-2026). Sin archivo: Catalina.
- **Bloqueo** (`events.c`; también con el rol **«mint-macos-alerta»**, el panel de confirmación): un clic en el contenido de la madre con una hoja abierta no llega a la madre (`XISyncDevice` en vez de
  `XIReplayDevice`); la barra de título sí responde (se mueve) y el resto de la app queda libre. Igual desde Tiger según José.

**Probado** en Xvfb con la libmuffin compilada (caso 136: Catalina y Monterey, el control sin hoja y el clic bloqueado). **Falta**: el botón de
cerrar de la madre apagado mientras la hoja está abierta (frames.c) y la animación ±32 pt con fundido (279 ms al entrar, 260 al salir; va por
extensión de Cinnamon, no por Muffin). Instalar el .deb nuevo es con sudo y con el sí de José (versión sugerida 6.6.3+zena+semaforos2).
