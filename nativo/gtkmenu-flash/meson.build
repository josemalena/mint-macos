# libmint-macos-menu-flash.so: módulo GTK3 con el parpadeo de los menús (GTK_MODULES). Va a ~/.local/lib/mint-macos/ (instalar.sh).
gmodule_dep = dependency('gmodule-2.0')
shared_module('mint-macos-menu-flash', 'menu-flash-module.c',
  dependencies: [gtk_dep, gmodule_dep],
  name_prefix: 'lib',
  install: false)
