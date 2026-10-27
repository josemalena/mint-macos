# libmint-macos-semaforos.so: módulo GTK3 con el hover de los tres semáforos a la vez (GTK_MODULES).
gmodule_dep = dependency('gmodule-2.0')
shared_module('mint-macos-semaforos', 'semaforos-module.c',
  dependencies: [gtk_dep, gmodule_dep],
  name_prefix: 'lib',
  install: false)
