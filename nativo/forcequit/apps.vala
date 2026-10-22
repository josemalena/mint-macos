/*
 * Las aplicaciones en marcha para Force Quit: las ventanas normales agrupadas por su clase (WM_CLASS),
 * con el nombre y el ícono de su .desktop. Igual que forcekill.py (que usaba wmctrl), con libwnck.
 */
namespace MacForceQuit {
    public class App : Object {
        public string clase;
        public string nombre;
        public Gdk.Pixbuf? icono = null;
        public Array<int> pids = new Array<int> ();
        /** Entre sus procesos está el escritorio de Fynder (nemo-desktop): Relaunch también lo vuelve a levantar. */
        public bool con_escritorio = false;
        /** Alguna de sus ventanas no contesta: Muffin la marcó (--seleccionar) o su proceso está detenido. */
        public bool no_responde = false;
        /** Fynder es el Finder de aquí: en Catalina su botón dice «Relaunch» y no «Force Quit». */
        public bool es_fynder { get { return clase == "fynder"; } }

        public void agregar_pid (int pid) {
            for (int i = 0; i < pids.length; i++) {
                if (pids.index (i) == pid) {
                    return;
                }
            }
            pids.append_val (pid);
        }
    }

    string embellecer (string s) {
        string t = s.strip ().replace ("_", " ").replace ("-", " ");
        if (t == t.down () && t.length > 0) {
            t = t.substring (0, 1).up () + t.substring (1);
        }
        return t;
    }

    Gdk.Pixbuf? cargar_icono (Icon? gicon, string? nombre) {
        var tema = Gtk.IconTheme.get_default ();
        try {
            if (gicon != null) {
                var info = tema.lookup_by_gicon (gicon, 16, Gtk.IconLookupFlags.FORCE_SIZE);
                if (info != null) {
                    return info.load_icon ();
                }
            }
            if (nombre != null && tema.has_icon (nombre)) {
                return tema.load_icon (nombre, 16, Gtk.IconLookupFlags.FORCE_SIZE);
            }
        } catch (Error e) {
        }
        return null;
    }

    /** Pids que Muffin dio por colgados (el ayudante de Cinnamon los manda con --seleccionar). */
    HashTable<int, bool>? colgados = null;

    public void marcar_colgado (int pid) {
        if (colgados == null) {
            colgados = new HashTable<int, bool> (direct_hash, direct_equal);
        }
        colgados.insert (pid, true);
    }

    /** El proceso está detenido (kill -STOP) o en espera de disco: no va a contestar nada. */
    bool detenido (int pid) {
        string contenido;
        try {
            FileUtils.get_contents ("/proc/%d/stat".printf (pid), out contenido);
        } catch (FileError e) {
            return false;
        }
        int cierre = contenido.last_index_of (")");
        if (cierre < 0 || cierre + 2 >= contenido.length) {
            return false;
        }
        char estado = contenido[cierre + 2];
        return estado == 'T' || estado == 't';
    }

    /** Las aplicaciones con ventana, por orden alfabético y con Fynder al final (como el Finder en la Mac). */
    public List<App> recoger () {
        var pantalla = Wnck.Screen.get_default ();
        pantalla.force_update ();
        int yo = (int) Posix.getpid ();

        var por_clase = new HashTable<string, App> (str_hash, str_equal);
        var infos = AppInfo.get_all ();
        int[] pids_escritorio = {};
        foreach (var w in pantalla.get_windows ()) {
            var tipo = w.get_window_type ();
            if (tipo == Wnck.WindowType.DESKTOP && w.get_pid () > 0
                && (w.get_class_group_name () ?? "").down () == "nemo-desktop") {
                pids_escritorio += w.get_pid ();
                continue;
            }
            if (tipo != Wnck.WindowType.NORMAL && tipo != Wnck.WindowType.DIALOG) {
                continue;
            }
            int pid = w.get_pid ();
            if (w.is_skip_tasklist () || pid <= 0 || pid == yo) {
                continue;
            }
            string clase = (w.get_class_group_name () ?? w.get_application ().get_name ()).down ();
            if (clase == "cinnamon" || clase == "mac-forcequit") {
                continue;
            }
            var app = por_clase[clase];
            if (app == null) {
                app = new App () { clase = clase };
                por_clase[clase] = app;
                DesktopAppInfo? d = buscar (infos, clase);
                if (d != null) {
                    app.nombre = d.get_display_name () ?? d.get_name ();
                    app.icono = cargar_icono (d.get_icon (), null);
                } else {
                    app.nombre = embellecer (w.get_class_group_name () ?? clase);
                    app.icono = cargar_icono (null, "application-x-executable");
                }
                if (app.icono == null) {
                    var mini = w.get_mini_icon ();
                    app.icono = mini != null ? mini.scale_simple (16, 16, Gdk.InterpType.BILINEAR) : null;
                }
            }
            app.agregar_pid (pid);
            if ((colgados != null && colgados.contains (pid)) || detenido (pid)) {
                app.no_responde = true;
            }
        }

        // El escritorio de Fynder es otro proceso (nemo-desktop): Relaunch lo reinicia con el resto de Fynder.
        // El relanzado lo hace la sesión; aquí solo se mata, por PID.
        if (pids_escritorio.length > 0) {
            var fynder = por_clase["fynder"];
            if (fynder == null) {
                fynder = new App () { clase = "fynder", nombre = "Fynder" };
                fynder.icono = cargar_icono (null, "system-file-manager");
                por_clase["fynder"] = fynder;
            }
            fynder.con_escritorio = true;
            foreach (int p in pids_escritorio) {
                fynder.agregar_pid (p);
            }
        }

        var lista = new List<App> ();
        foreach (var a in por_clase.get_values ()) {
            lista.append (a);
        }
        lista.sort ((a, b) => {
            if (a.es_fynder != b.es_fynder) {
                return a.es_fynder ? 1 : -1;
            }
            return strcmp (a.nombre.down (), b.nombre.down ());
        });
        return lista;
    }

    DesktopAppInfo? buscar (List<AppInfo> infos, string clase) {
        foreach (var i in infos) {
            var d = i as DesktopAppInfo;
            if (d != null && (d.get_startup_wm_class () ?? "").down () == clase) {
                return d;
            }
        }
        foreach (var i in infos) {
            var d = i as DesktopAppInfo;
            if (d != null && (d.get_id () ?? "").down ().contains (clase)) {
                return d;
            }
        }
        return null;
    }
}
