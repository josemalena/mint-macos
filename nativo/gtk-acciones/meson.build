# libmint-macos-acciones.so: módulo GTK3 que exporta el grupo «win» de las apps gtkmm (GTK_MODULES). Va a ~/.local/lib/mint-macos/ (compilar-desde-head.sh).
gmodule_dep = dependency('gmodule-2.0')
shared_module('mint-macos-acciones', 'acciones-module.c',
  dependencies: [gtk_dep, gmodule_dep],
  name_prefix: 'lib',
  install: false)
