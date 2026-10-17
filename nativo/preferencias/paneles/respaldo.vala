/*
 * Time Machine: el panel de Catalina (Screen Shot 2026-10-14 at 1.24.52 PM) sobre Timeshift (port de settings/respaldo.py).
 *
 * Lee /etc/timeshift/timeshift.json (legible sin root): «Back Up Automatically» refleja si hay alguna programación encendida, el
 * disco sale de backup_device_uuid, y el texto de lo que se guarda usa los conteos reales (cada hora, cada día, cada semana y cada
 * mes). Select Backup Disk… y Options… abren Timeshift (que pide la clave de administrador por su cuenta). Cambiar la
 * programación desde aquí no se puede sin root: los controles van en gris. Sin equivalente: Show Time Machine in menu bar.
 * La captura de la hoja Options… (1.24.59 PM) y de Select Disk (1.25.04 PM) no se imitan: Timeshift trae las suyas.
 */
namespace Preferencias {

    public class PanelTimeMachine : Panel {
        // MINT_RESPALDO_PRUEBA: no abre Timeshift.
        bool prueba = Environment.get_variable ("MINT_RESPALDO_PRUEBA") != null;

        public PanelTimeMachine () {
            id = "com.apple.prefs.backup";
            nombre = "Time Machine";
            palabras = "time machine, backup, back up, timeshift, snapshot, restore";
        }

        static HashTable<string, string> config () {
            foreach (var ruta in new string[] { "/etc/timeshift/timeshift.json", "/etc/timeshift/default.json" }) {
                if (FileUtils.test (ruta, FileTest.EXISTS)) {
                    var d = json_plano (ruta);
                    if (d.size () > 0) {
                        return d;
                    }
                }
            }
            return new HashTable<string, string> (str_hash, str_equal);
        }

        static string? disco (string? uuid) {
            if (uuid == null || uuid == "") {
                return null;
            }
            try {
                var p = new Subprocess (SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_SILENCE, "lsblk", "-no",
                                        "LABEL,NAME,MOUNTPOINT", "/dev/disk/by-uuid/" + uuid);
                string? salida;
                p.communicate_utf8 (null, null, out salida, null);
                var partes = (salida ?? "").strip ().split_set (" \t\n");
                foreach (var t in partes) {
                    if (t != "") {
                        return t;
                    }
                }
                return uuid;
            } catch (Error e) {
                return uuid;
            }
        }

        static Gtk.Widget gris_con (Gtk.Widget w, string motivo) {
            w.set_sensitive (false);
            w.set_tooltip_text (motivo);
            return w;
        }

        void abrir_timeshift () {
            if (prueba) {
                return;
            }
            try {
                Process.spawn_async (null, { "timeshift-launcher" }, null,
                                     SpawnFlags.SEARCH_PATH | SpawnFlags.STDOUT_TO_DEV_NULL | SpawnFlags.STDERR_TO_DEV_NULL,
                                     () => { Posix.setsid (); }, null);
            } catch (Error e) {
            }
        }

        public override Gtk.Widget? construir () {
            var cfg = config ();
            var caja = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            caja.get_style_context ().add_class ("mp-propio");
            caja.margin_top = 18;
            caja.margin_bottom = 14;
            var izq = new Gtk.Box (Gtk.Orientation.VERTICAL, 10);
            izq.set_size_request (240, -1);
            var icono = imagen_icono_panel (id, 112);
            icono.margin_top = 10;
            icono.margin_bottom = 10;
            izq.pack_start (icono, false, false, 0);
            var t = new Gtk.Label ("Time Machine");
            t.get_style_context ().add_class ("mp-titulo-negrita");
            izq.pack_start (t, false, false, 0);
            bool activo = false;
            foreach (var k in new string[] { "monthly", "weekly", "daily", "hourly", "boot" }) {
                if ((cfg["schedule_" + k] ?? "false") == "true") {
                    activo = true;
                }
            }
            var auto = new Gtk.CheckButton.with_label ("Back Up Automatically");
            auto.active = activo;
            auto.halign = Gtk.Align.CENTER;
            izq.pack_start (gris_con (auto, "Timeshift sets this itself; open it to change the schedule."), false, false, 0);
            caja.pack_start (izq, false, false, 0);
            caja.pack_start (new Gtk.Separator (Gtk.Orientation.VERTICAL), false, false, 0);

            var der = new Gtk.Box (Gtk.Orientation.VERTICAL, 10);
            der.margin_start = 30;
            der.margin_end = 20;
            var nombre_disco = disco (cfg["backup_device_uuid"]);
            var titulo = new Gtk.Label (nombre_disco ?? "No backup disk selected");
            titulo.xalign = 0.5f;
            titulo.get_style_context ().add_class ("mp-titulo-negrita");
            titulo.margin_top = 10;
            titulo.margin_bottom = 10;
            der.pack_start (titulo, false, false, 0);
            var seleccionar = new Gtk.Button.with_label ("Select Backup Disk…");
            seleccionar.halign = Gtk.Align.CENTER;
            seleccionar.clicked.connect (() => abrir_timeshift ());
            der.pack_start (seleccionar, false, false, 0);
            var lineas = new StringBuilder ("Timeshift keeps:");
            bool alguna = false;
            string[] claves = { "hourly", "daily", "weekly", "monthly" };
            foreach (var clave in claves) {
                if ((cfg["schedule_" + clave] ?? "false") == "true") {
                    var cuenta = cfg["count_" + clave] ?? "?";
                    lineas.append ("\n• %s snapshots, up to %s".printf (clave.substring (0, 1).up () + clave.substring (1), cuenta));
                    alguna = true;
                }
            }
            if (!alguna) {
                lineas.append ("\n• No schedule is turned on");
            }
            var l = new Gtk.Label (lineas.str);
            l.xalign = 0;
            l.margin_top = 20;
            der.pack_start (l, false, false, 0);
            der.pack_start (new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0), true, true, 0);
            var pie = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            var menu = new Gtk.CheckButton.with_label ("Show Time Machine in menu bar");
            pie.pack_start (gris_con (menu, "There is no Time Machine menu on this computer."), false, false, 0);
            var opciones = new Gtk.Button.with_label ("Options…");
            opciones.clicked.connect (() => abrir_timeshift ());
            pie.pack_end (opciones, false, false, 0);
            der.pack_start (pie, false, false, 0);
            caja.pack_start (der, true, true, 0);
            caja.set_size_request (-1, 230);
            caja.show_all ();
            return caja;
        }
    }
}
