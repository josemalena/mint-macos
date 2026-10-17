/*
 * Un panel de System Preferences. Los que ya están en Vala traen su página (construir); los demás son PanelPython: se
 * abren con el System Preferences de Python (settings/preferencias.py) en su propia ventana, mientras se portan.
 */
namespace Preferencias {

    public abstract class Panel : Object {
        public string id { get; protected set; default = ""; }
        public string nombre { get; protected set; default = ""; }
        public string palabras { get; protected set; default = ""; }
        public string icono_tema { get; protected set; default = "preferences-system"; }
        public string grupo { get; set; default = ""; }
        public Gtk.Widget? celda = null;                 // el botón de la cuadrícula (el velo de la búsqueda lo mide)
        public Ventana? ventana = null;                  // la pone la ventana al abrirlo

        /** La página del panel; null si el panel se abre fuera de esta ventana (PanelPython, Advanced). */
        public abstract Gtk.Widget? construir ();

        /** Lo que hace el panel cuando no tiene página propia (abrir otro programa). */
        public virtual void lanzar () {
        }

        public virtual bool coincide (string texto) {
            var t = texto.down ().strip ();
            if (t == "") {
                return false;
            }
            return t in nombre.down () || t in palabras.down () || t in id.down ();
        }
    }

    /** Un panel que todavía se sirve con el System Preferences de Python. */
    public class PanelPython : Panel {
        string requiere;

        public PanelPython (DatosPanel d) {
            id = d.id;
            nombre = d.nombre;
            palabras = d.palabras;
            icono_tema = d.icono_tema;
            grupo = d.grupo;
            requiere = d.requiere;
        }

        public bool disponible () {
            return requiere == "" || Environment.find_program_in_path (requiere) != null;
        }

        public override Gtk.Widget? construir () {
            return null;
        }

        public override void lanzar () {
            abrir_en_python (id);
        }
    }

    /** «Advanced»: el cinnamon-settings de Mint entero, para lo que Catalina no tiene. */
    public class PanelAvanzado : Panel {
        public PanelAvanzado () {
            id = "mint.advanced";
            nombre = "Advanced";
            palabras = "advanced, mint, cinnamon, all settings";
            icono_tema = "cs-general";
            grupo = "advanced";
        }

        public override Gtk.Widget? construir () {
            return null;
        }

        public override void lanzar () {
            try {
                Process.spawn_async (null, { "cinnamon-settings" }, null, SpawnFlags.SEARCH_PATH, null, null);
            } catch (Error e) {
                warning ("cinnamon-settings: %s", e.message);
            }
        }
    }

    /**
     * Abre un panel en el System Preferences de Python, en su propia ventana y sin residente (al cerrarla el proceso
     * termina). Tiene otro id de aplicación para no chocar con este.
     */
    public void abrir_en_python (string ident) {
        var guion = Path.build_filename (carpeta_python (), "preferencias.py");
        if (!FileUtils.test (guion, FileTest.EXISTS)) {
            warning ("falta %s: no se puede abrir el panel %s", guion, ident);
            return;
        }
        try {
            string[] env = Environ.get ();
            env = Environ.set_variable (env, "MP_APP_ID", APP_ID + "Py");
            env = Environ.set_variable (env, "MP_SIN_RESIDENTE", "1");
            Process.spawn_async (null, { "python3", guion, ident }, env, SpawnFlags.SEARCH_PATH, null, null);
        } catch (Error e) {
            warning ("python3: %s", e.message);
        }
    }
}
