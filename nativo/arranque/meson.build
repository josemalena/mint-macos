sn_dep = dependency('libstartup-notification-1.0')

executable('mint-macos-arranque', 'arranque.c',
  dependencies: [sn_dep, wnck_dep, gtk_dep, gtk_x11_dep],
  c_args: ['-DWNCK_I_KNOW_THIS_IS_UNSTABLE'],
  install: false)
