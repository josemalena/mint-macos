wnck_dep = dependency('libwnck-3.0')
gio_unix_dep = dependency('gio-unix-2.0')

executable('mac-forcequit', files('apps.vala', 'ventana.vala', 'frente.vala', 'main.vala'),
  dependencies: [wnck_dep, gio_unix_dep, gtk_dep, glib_dep, gio_dep, posix_dep],
  c_args: ['-DWNCK_I_KNOW_THIS_IS_UNSTABLE'],
  install: false)
