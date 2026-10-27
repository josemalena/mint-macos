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
