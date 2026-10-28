wnck_dep = dependency('libwnck-3.0')
gio_unix_dep = dependency('gio-unix-2.0')

# Lo que comparten el binario suelto y el residente mac-ventanas (todo menos el main.vala de cada uno).
forcequit_lib_fuentes = files('apps.vala', 'ventana.vala', 'frente.vala')

executable('mac-forcequit', forcequit_lib_fuentes + files('main.vala'),
  dependencies: [dependency('x11'), libmacos_dep, wnck_dep, gio_unix_dep, gtk_dep, gtk_x11_dep, glib_dep, gio_dep, posix_dep],
  c_args: ['-DWNCK_I_KNOW_THIS_IS_UNSTABLE'],
  install: false)
