project('mint-macos-nativo', ['c', 'vala'],
  version: '0.1.0',
  meson_version: '>= 0.60.0',
  default_options: ['warning_level=1', 'c_std=gnu11'])

# Las ventanas de mint-macos que se pasan de Python a binario: Vala + GTK3, sin intérprete.
# libmacos es lo común (alerta estilo Catalina, estilo CSS, íconos dibujados); cada binario vive en su carpeta.
# Los ayudantes de root y los servicios irán aparte, en Rust.
gtk_dep = dependency('gtk+-3.0', version: '>= 3.22')
glib_dep = dependency('glib-2.0')
gio_dep = dependency('gio-2.0')
gobject_dep = dependency('gobject-2.0')
posix_dep = meson.get_compiler('vala').find_library('posix')
m_dep = meson.get_compiler('c').find_library('m', required: false)

subdir('libmacos')
subdir('sesion')
