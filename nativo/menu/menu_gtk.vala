/*
 * El menú que la app exporta como GMenuModel (org.gtk.Menus) con sus acciones (org.gtk.Actions): las apps GTK3 y las que
 * pasan por appmenu-gtk-module. La ventana trae _GTK_UNIQUE_BUS_NAME y _GTK_MENUBAR_OBJECT_PATH (más las rutas de la app y
 * de la ventana). Con el módulo la barra viene envuelta en dos secciones sin etiqueta: se aplanan. Los ids son rutas de
 * índices sobre la lista aplanada («2», «2.0.3»); se resuelven volviendo a recorrer el modelo, y la `version` del servicio
 * protege de que el modelo cambie entre medias.
 */
namespace Menu {
    public class FuenteGtk : Fuente {
        MenuModel modelo;
        HashTable<string, ActionGroup> grupos = new HashTable<string, ActionGroup> (str_hash, str_equal);
        GenericArray<MenuModel> vivos = new GenericArray<MenuModel> ();
        int64 ultimo_cambio = 0;
        bool asentado = false;
        uint aviso = 0;

        public FuenteGtk (DBusConnection con, string bus, string ruta_menu, string? ruta_app, string? ruta_ventana) {
            modelo = DBusMenuModel.get (con, bus, ruta_menu);
            if (ruta_app != null) grupos.insert ("app", DBusActionGroup.get (con, bus, ruta_app));
            if (ruta_ventana != null) grupos.insert ("win", DBusActionGroup.get (con, bus, ruta_ventana));
            // appmenu-gtk-module publica las acciones en la misma ruta del menú, con el prefijo «unity.».
            grupos.insert ("unity", DBusActionGroup.get (con, bus, ruta_menu));
            foreach (var g in grupos.get_values ()) g.list_actions ();
            ultimo_cambio = get_monotonic_time ();
            modelo.items_changed.connect (al_cambiar);
            precargar (modelo, 0);
        }

        public override string nombre_fuente () { return "gtk"; }

        void al_cambiar (int p, int r, int a) {
            ultimo_cambio = get_monotonic_time ();
            if (!asentado) return;
            if (aviso != 0) Source.remove (aviso);
            aviso = Timeout.add (60, () => { aviso = 0; cambio (""); return false; });
        }

        /** Recorre el modelo para que GDBusMenuModel pida (y mantenga) los submodelos. */
        void precargar (MenuModel m, int prof) {
            if (prof > 5) return;
            int n = m.get_n_items ();
            for (int i = 0; i < n; i++) {
                foreach (var enlace in new string[] { "submenu", "section" }) {
                    var sub = m.get_item_link (i, enlace);
                    if (sub != null) {
                        bool nuevo = true;
                        for (int k = 0; k < vivos.length; k++) if (vivos[k] == sub) { nuevo = false; break; }
                        if (nuevo) {
                            vivos.add (sub);
                            sub.items_changed.connect (al_cambiar);
                        }
                        precargar (sub, prof + 1);
                    }
                }
            }
        }

        /** Espera a que paren de llegar ítems (ráfagas por D-Bus), sin pasar de `max_ms`. */
        async void asentarse (int max_ms) {
            int64 limite = get_monotonic_time () + (int64) max_ms * 1000;
            int64 inicio = get_monotonic_time ();
            while (get_monotonic_time () < limite) {
                precargar (modelo, 0);
                int64 ahora = get_monotonic_time ();
                // asentado: sin cambios en los últimos 60 ms (y al menos 40 ms de espera la primera vez)
                if (ahora - ultimo_cambio > 60000 && (asentado || ahora - inicio > 40000)) break;
                yield pausa (20);
            }
            asentado = true;
        }

        string? texto_de (MenuModel m, int i, string clave) {
            var v = m.get_item_attribute_value (i, clave, VariantType.STRING);
            return v != null ? v.get_string () : null;
        }

        /** Los ítems de `m`, entrando en las secciones sin etiqueta. `barra`: solo los menús de arriba, sin separadores. */
        void llenar (MenuModel m, GenericArray<Nodo> salida, int prof, bool barra, string prefijo_id, bool incluir_app) {
            int n = m.get_n_items ();
            bool hubo = false;
            for (int i = 0; i < n; i++) {
                var sec = m.get_item_link (i, "section");
                var sub = m.get_item_link (i, "submenu");
                if (sec != null && sub == null) {
                    if (!barra && hubo && sec.get_n_items () > 0) salida.add (Nodo.separador ());
                    int antes = (int) salida.length;
                    llenar (sec, salida, prof, barra, prefijo_id, incluir_app);
                    if (salida.length > antes) hubo = true;
                    continue;
                }
                var etiqueta = limpiar_etiqueta (texto_de (m, i, "label") ?? "");
                if (sub != null) {
                    var app_v = m.get_item_attribute_value (i, "x-constanza-app-menu", VariantType.BOOLEAN);
                    bool es_app = app_v != null && app_v.get_boolean ();
                    if (barra && (etiqueta == "" || es_app != incluir_app)) continue;
                    var nodo = new Nodo ();
                    nodo.tipo = "submenu";
                    nodo.etiqueta = etiqueta;
                    nodo.es_menu_app = es_app;
                    nodo.submodelo = sub;
                    nodo.id = prefijo_id + (prefijo_id == "" ? "" : ".") + salida.length.to_string ();
                    if (!barra && prof < 4) {
                        nodo.hijos = new GenericArray<Nodo> ();
                        llenar (sub, nodo.hijos, prof + 1, false, nodo.id, incluir_app);
                    }
                    salida.add (nodo);
                    hubo = true;
                    continue;
                }
                if (barra) continue;
                var nodo = accion (m, i, etiqueta);
                nodo.id = prefijo_id + (prefijo_id == "" ? "" : ".") + salida.length.to_string ();
                salida.add (nodo);
                hubo = true;
            }
        }

        Nodo accion (MenuModel m, int i, string etiqueta) {
            var nodo = new Nodo ();
            nodo.etiqueta = etiqueta;
            var accion = texto_de (m, i, "action") ?? "";
            var objetivo = m.get_item_attribute_value (i, "target", null);
            ActionGroup? grupo = null;
            string nombre = "";
            if (accion != "") {
                var p = accion.index_of (".");
                if (p < 0) {
                    nombre = accion;
                } else {
                    grupo = grupos.lookup (accion.substring (0, p));
                    nombre = accion.substring (p + 1);
                }
            }
            nodo.grupo = grupo;
            nodo.accion = nombre;
            nodo.objetivo = objetivo;
            nodo.activo = grupo != null && nombre != "" && grupo.has_action (nombre) && grupo.get_action_enabled (nombre);
            Variant? estado = null;
            if (grupo != null && nombre != "" && grupo.has_action (nombre)) estado = grupo.get_action_state (nombre);
            // Las marcas como en la Mac: una ✓ a la izquierda, sin interruptor; vale para booleanos y para grupos de radio.
            if (estado != null && estado.get_type_string () == "b" && objetivo == null) {
                nodo.marca = "check";
                nodo.marcado = estado.get_boolean ();
                nodo.booleano = true;
            } else if (estado != null && objetivo != null) {
                nodo.marca = "radio";
                nodo.marcado = estado.equal (objetivo);
            }
            var literal = texto_de (m, i, "x-constanza-accel") ?? "";
            nodo.atajo = literal != "" ? literal : Atajos.de_gtk (texto_de (m, i, "accel") ?? "", clase);
            var alt_v = m.get_item_attribute_value (i, "x-constanza-alternate", VariantType.BOOLEAN);
            nodo.alterno = alt_v != null && alt_v.get_boolean ();
            var icono_v = m.get_item_attribute_value (i, "icon", null);
            if (icono_v != null) {
                try {
                    var ic = Icon.deserialize (icono_v);
                    if (ic != null) nodo.icono = ic.to_string () ?? "";
                } catch (GLib.Error e) {
                }
            }
            return nodo;
        }

        public override async GenericArray<Nodo> barra (int espera_ms) throws GLib.Error {
            yield asentarse (espera_ms);
            var res = new GenericArray<Nodo> ();
            llenar (modelo, res, 0, true, "", false);
            // Los menús de arriba llevan activo=true: GTK no los apaga.
            return res;
        }

        public override async GenericArray<Nodo> menu_app () throws GLib.Error {
            yield asentarse (400);
            var res = new GenericArray<Nodo> ();
            var arriba = new GenericArray<Nodo> ();
            llenar (modelo, arriba, 0, true, "app", true);
            for (int i = 0; i < arriba.length; i++) {
                if (arriba[i].submodelo == null) continue;
                llenar (arriba[i].submodelo, res, 0, false, "app", true);
            }
            limpiar_separadores (res);
            return res;
        }

        /** El modelo y el nodo de un id: se recorre de nuevo la lista aplanada por sus índices. */
        Nodo? resolver (string id, out GenericArray<Nodo> hermanos) {
            hermanos = null;
            var partes = id.split (".");
            if (partes.length == 0) return null;
            var nivel = new GenericArray<Nodo> ();
            if (partes[0] == "app") {
                // el menú de la app: «app.N…»; se aplana igual que en menu_app()
                var arriba = new GenericArray<Nodo> ();
                llenar (modelo, arriba, 0, true, "app", true);
                for (int i = 0; i < arriba.length; i++) {
                    if (arriba[i].submodelo != null) llenar (arriba[i].submodelo, nivel, 0, false, "app", true);
                }
                partes = partes[1:partes.length];
            } else {
                llenar (modelo, nivel, 0, true, "", false);
            }
            Nodo? actual = null;
            for (int k = 0; k < partes.length; k++) {
                int idx = int.parse (partes[k]);
                if (partes[0] == "" || idx < 0 || idx >= nivel.length) return null;
                actual = nivel[idx];
                if (k + 1 < partes.length) {
                    if (actual.submodelo == null) return null;
                    nivel = new GenericArray<Nodo> ();
                    llenar (actual.submodelo, nivel, 0, false, "", false);
                    // los índices de los hijos se cuentan con el mismo prefijo vacío
                }
            }
            return actual;
        }

        public override async GenericArray<Nodo> abrir (string id, int espera_ms) throws GLib.Error {
            yield asentarse (espera_ms);
            GenericArray<Nodo> h;
            var nodo = resolver (id, out h);
            if (nodo == null || nodo.submodelo == null) throw new Error.SIN_MENU ("no hay menú «%s»", id);
            var res = new GenericArray<Nodo> ();
            llenar (nodo.submodelo, res, 0, false, id, false);
            limpiar_separadores (res);
            return res;
        }

        public override void cerrar (string id) {
        }

        public override bool activar (string id) throws GLib.Error {
            GenericArray<Nodo> h;
            var nodo = resolver (id, out h);
            if (nodo == null || nodo.grupo == null || nodo.accion == "") return false;
            if (nodo.booleano) {
                var actual = nodo.grupo.get_action_state (nodo.accion);
                nodo.grupo.change_action_state (nodo.accion, new Variant.boolean (actual == null || !actual.get_boolean ()));
            } else if (nodo.marca == "radio") {
                nodo.grupo.change_action_state (nodo.accion, nodo.objetivo);
            } else {
                nodo.grupo.activate_action (nodo.accion, nodo.objetivo);
            }
            return true;
        }
    }
}
