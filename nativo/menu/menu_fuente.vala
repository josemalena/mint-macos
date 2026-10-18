/*
 * Una fuente de menú: lo que sabe leer de una ventana (GMenuModel de GTK o dbusmenu). El servicio no sabe de cuál viene.
 * Los ids son estables mientras la `version` no cambie; la fuente avisa por `cambio` cuando el árbol se rehízo.
 */
namespace Menu {
    [DBus (name = "org.mintmacos.Menu1.Error")]
    public errordomain Error {
        SIN_MENU,
        VENCIDO
    }

    public abstract class Fuente : Object {
        public string clase = "";               // WM_CLASS en minúsculas, para las excepciones de atajos

        /** Algo cambió. `id` es el menú de arriba que cambió, o "" si cambió la barra. */
        public signal void cambio (string id);

        /** Los menús de arriba, ya sin los del menú de la app. Espera a que el modelo se asiente. */
        public abstract async GenericArray<Nodo> barra (int espera_ms) throws GLib.Error;
        /** Los ítems de un menú de arriba (o de un submenú, por id), con `hijos`. */
        public abstract async GenericArray<Nodo> abrir (string id, int espera_ms) throws GLib.Error;
        public abstract void cerrar (string id);
        public abstract bool activar (string id) throws GLib.Error;
        public abstract async GenericArray<Nodo> menu_app () throws GLib.Error;
        public abstract string nombre_fuente ();
        /** Todos los ítems con su ruta («Edit ▸ Find ▸ Find…»), para Buscar. */
        public virtual async GenericArray<Nodo> todo (int espera_ms) throws GLib.Error {
            var res = new GenericArray<Nodo> ();
            var b = yield barra (espera_ms);
            for (int i = 0; i < b.length; i++) {
                try {
                    var hijos = yield abrir (b[i].id, espera_ms);
                    recorrer (hijos, b[i].etiqueta, res);
                } catch (GLib.Error e) {
                    // un menú que la app ya no tiene (Firefox da «ID no existe» si lo rehace a mitad): se sigue con los demás
                }
            }
            return res;
        }

        public static void recorrer (GenericArray<Nodo> lista, string prefijo, GenericArray<Nodo> salida) {
            for (int i = 0; i < lista.length; i++) {
                var n = lista[i];
                if (n.tipo == "separador") continue;
                var ruta = prefijo + " ▸ " + n.etiqueta;
                if (n.tipo == "submenu" && n.hijos != null) {
                    recorrer (n.hijos, ruta, salida);
                } else {
                    n.ruta = ruta;
                    salida.add (n);
                }
            }
        }
    }

    /** Espera `ms` sin bloquear el main loop. */
    public async void pausa (uint ms) {
        Timeout.add (ms, () => { pausa.callback (); return false; });
        yield;
    }
}
