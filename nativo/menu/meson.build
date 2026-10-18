# El servicio del menú de la app (org.mintmacos.Menu1): lee GMenuModel y dbusmenu y se lo da aplanado al applet.
# Lo comparten el binario suelto (mac-menu) y el residente mac-ventanas.
menu_lib_fuentes = files('menu_nodo.vala', 'menu_atajos.vala', 'menu_fuente.vala', 'menu_gtk.vala', 'menu_dbusmenu.vala',
                         'menu_servicio.vala')
dbusmenu_vapi_dep = meson.get_compiler('vala').find_library('Dbusmenu-0.4', required: false)

executable('mac-menu', menu_lib_fuentes + files('menu_main.vala'),
  dependencies: [gtk_dep, gtk_x11_dep, glib_dep, gio_dep, gobject_dep, dependency('x11'), posix_dep, m_dep],
  install: false)
