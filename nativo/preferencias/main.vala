/*
 * mac-preferencias: System Preferences en Vala + GTK3 (port de settings/preferencias.py, panel por panel).
 *
 *   mac-preferencias                 la cuadrícula
 *   mac-preferencias sound           un panel: por el nombre de Cinnamon…
 *   mac-preferencias Displays        …o el de Catalina (sin importar mayúsculas)
 *   mac-preferencias --lista         los paneles que hay
 *   mac-preferencias --residente     se arma escondido y espera
 *
 * Mismo id de aplicación y misma acción «abrir» que el de Python: solo uno de los dos es el residente. Los paneles que
 * todavía no están en Vala se abren con el de Python (otro id, sin residente).
 */
namespace Preferencias {

    public class Aplicacion : Gtk.Application {
        public Ventana? ventana = null;
        public bool residente = true;

        public Aplicacion () {
            Object (application_id: APP_ID, flags: ApplicationFlags.HANDLES_COMMAND_LINE);
        }

        protected override void startup () {
            base.startup ();
            hold ();                       // residente: sigue vivo con la ventana escondida
            // app.abrir("sound") desde otro proceso o desde un menú.
            var abrir = new SimpleAction ("abrir", VariantType.STRING);
            abrir.activate.connect ((p) => abrir_accion (p.get_string ()));
            add_action (abrir);
            var todo = new SimpleAction ("todo", null);
            todo.activate.connect (() => { if (ventana != null) ventana.mostrar_todo (); });
            add_action (todo);
            // El menú View (capturas 1.15.16 y 1.15.23 PM): Back, Forward, Show All Preferences, Customize…, Organize by
            // Categories / Alphabetically, Search y la lista de paneles. Organize Alphabetically y Customize… no tienen captura
            // de lo que hacen: van desactivados.
            var atras = new SimpleAction ("atras", null);
            atras.activate.connect (() => { if (ventana != null) ventana.ir (-1); });
            add_action (atras);
            var adelante = new SimpleAction ("adelante", null);
            adelante.activate.connect (() => { if (ventana != null) ventana.ir (1); });
            add_action (adelante);
            var buscar = new SimpleAction ("buscar", null);
            buscar.activate.connect (() => { if (ventana != null) ventana.buscar.grab_focus (); });
            add_action (buscar);
            add_action (new SimpleAction.stateful ("categorias", null, new Variant.boolean (true)));
            foreach (var nombre in new string[] { "alfabetico", "personalizar" }) {
                var a = new SimpleAction (nombre, null);
                a.set_enabled (false);
                add_action (a);
            }
            // System Preferences ▸ About System Preferences (el ítem del menú de la app lo activa por D-Bus: appmenu@macos busca la acción app.about)
            var acerca = new SimpleAction ("about", null);
            acerca.activate.connect (() => mostrar_acerca ());
            add_action (acerca);
            set_accels_for_action ("app.atras", { "<Primary>bracketleft" });
            set_accels_for_action ("app.adelante", { "<Primary>bracketright" });
            set_accels_for_action ("app.todo", { "<Primary>l" });
            set_accels_for_action ("app.buscar", { "<Primary>f" });
        }

        Gtk.AboutDialog? dialogo_acerca = null;

        /** «About System Preferences»: nombre, versión y derechos; si ya está abierto se trae al frente. */
        void mostrar_acerca () {
            if (dialogo_acerca != null) {
                dialogo_acerca.present ();
                return;
            }
            var d = MacOS.dialogo_acerca (TITULO, Path.build_filename (carpeta_apps (), "iconos", "sistema.png"), null, "preferences-system");
            d.destroy.connect (() => { dialogo_acerca = null; });
            dialogo_acerca = d;
            d.present ();
        }

        /** El menubar con View, que las apps GTK publican al menú global (appmenu-gtk-module). */
        void armar_menu () {
            var vista = new Menu ();
            var s1 = new Menu ();
            s1.append_item (item ("Back", "app.atras", "<Primary>bracketleft"));
            s1.append_item (item ("Forward", "app.adelante", "<Primary>bracketright"));
            s1.append_item (item ("Show All Preferences", "app.todo", "<Primary>l"));
            s1.append_item (item ("Customize…", "app.personalizar", null));
            vista.append_section (null, s1);
            var s2 = new Menu ();
            s2.append_item (item ("Organize by Categories", "app.categorias", null));
            s2.append_item (item ("Organize Alphabetically", "app.alfabetico", null));
            vista.append_section (null, s2);
            var s3 = new Menu ();
            s3.append_item (item ("Search", "app.buscar", "<Primary>f"));
            vista.append_section (null, s3);
            var s4 = new Menu ();
            var lista = new GenericArray<Panel> ();
            for (int i = 0; i < ventana.todos.length; i++) {
                if (!(ventana.todos[i] is PanelAvanzado)) {
                    lista.add (ventana.todos[i]);
                }
            }
            lista.sort ((a, b) => strcmp (a.nombre.down (), b.nombre.down ()));
            for (int i = 0; i < lista.length; i++) {
                var it = new MenuItem (lista[i].nombre, null);
                it.set_action_and_target_value ("app.abrir", new Variant.string (lista[i].id));
                var ruta = Path.build_filename (carpeta_apps (), "iconos", lista[i].id + ".png");
                if (FileUtils.test (ruta, FileTest.EXISTS)) {
                    it.set_icon (new FileIcon (File.new_for_path (ruta)));
                }
                s4.append_item (it);
            }
            vista.append_section (null, s4);
            var barra = new Menu ();
            barra.append_submenu ("View", vista);
            set_menubar (barra);
            ventana.show_menubar = false;     // arriba lo pinta la barra global; la ventana no lo repite
        }

        MenuItem item (string rotulo, string accion, string? atajo) {
            var it = new MenuItem (rotulo, accion);
            if (atajo != null) {                       // la barra global pinta el atajo (⌘ es Ctrl con keyd)
                it.set_attribute_value ("accel", new Variant.string (atajo));
            }
            return it;
        }

        public void actualizar_menu (bool hay_atras, bool hay_adelante) {
            var a = lookup_action ("atras") as SimpleAction;
            if (a != null) {
                a.set_enabled (hay_atras);
            }
            var b = lookup_action ("adelante") as SimpleAction;
            if (b != null) {
                b.set_enabled (hay_adelante);
            }
        }

        /** El ítem del menú y los atajos entran por aquí (gdbus, sin arrancar nada). */
        void abrir_accion (string nombre) {
            if (ventana == null) {
                return;
            }
            if (!ventana.get_visible ()) {
                ventana.mostrar_de_nuevo ();
            }
            if (nombre != "") {
                ventana.abrir_por_nombre (nombre);
            }
            ventana.present ();
        }

        public override int command_line (ApplicationCommandLine cl) {
            var args = cl.get_arguments ();
            string? primero = args.length > 1 ? args[1] : null;
            if (primero == "--lista") {
                foreach (var g in armar_paneles ()) {
                    foreach (var p in g.paneles) {
                        cl.print ("%-46s %s\n", p.id, p.nombre);
                    }
                }
                return 0;
            }
            if (ventana == null) {
                ventana = new Ventana (this);
                armar_menu ();
            }
            if (primero == "--residente") {
                Idle.add (() => { precalentar_solaar (); return false; });
                return 0;                  // la sesión lo deja armado y escondido
            }
            if (!ventana.get_visible ()) {
                ventana.mostrar_de_nuevo ();
            }
            if (primero != null) {
                if (!ventana.abrir_por_nombre (primero)) {
                    cl.printerr ("No hay un panel «%s». Mira mac-preferencias --lista.\n", primero);
                }
            }
            ventana.present ();
            return 0;
        }
    }
}

int main (string[] args) {
    // El WM_CLASS sale del nombre del programa: con él el Dock y el menú de la barra agrupan la ventana bajo el lanzador
    // mint-macos-settings.desktop.
    Environment.set_prgname ("mac-settings");
    Environment.set_application_name (Preferencias.TITULO);
    return new Preferencias.Aplicacion ().run (args);
}
