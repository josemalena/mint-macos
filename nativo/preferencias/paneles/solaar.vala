/*
 * Solaar: los dispositivos Logitech de José (el receptor, el mouse y el teclado) con su batería y los ajustes que Solaar expone
 * para cada uno. Es un panel de terceros, como macFUSE en Catalina (última fila de System Preferences, 12.07.52 AM). El motor
 * es Solaar sin ventana ni ícono (tema/solaar-barra.sh): `solaar show` da los dispositivos y la batería, y
 * `solaar config <dispositivo>` los ajustes (el título, lo que hace y sus valores posibles, en inglés, salen de Solaar mismo);
 * `solaar config <dispositivo> <ajuste> <valor>` los cambia. Solo se dibujan los que son interruptor o lista de valores: lo demás
 * (qué hace cada tecla, cambiar de host, que desconectaría el teclado) queda en la ventana de Solaar, tras «Advanced…».
 * logid corre también pero con /etc/logid.cfg todo comentado: no toca ningún ajuste, así que no hay dos programas peleando.
 */
namespace Preferencias {

    class AjusteSolaar : Object {
        public string clave = "";
        public string titulo = "";
        public string descripcion = "";
        public string valor = "";
        public string[] opciones = {};        // vacío = interruptor
    }

    class DispositivoSolaar : Object {
        public string nombre = "";
        public string bateria = "";           // «100%, discharging.»
        public AjusteSolaar[] ajustes = {};
    }

    string ejecutar_solaar (string[] cmd) {
        try {
            var p = new Subprocess.newv (cmd, SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_SILENCE);
            string s;
            p.communicate_utf8 (null, null, out s, null);
            return s ?? "";
        } catch (Error e) {
            return "";
        }
    }

    /** Los ajustes de `solaar config <dispositivo>`: bloques «# Título / # descripción / # possible values / clave = valor». */
    AjusteSolaar[] leer_ajustes (string dispositivo) {
        AjusteSolaar[] salida = {};
        string titulo = "", descripcion = "", posibles = "";
        foreach (var l in ejecutar_solaar ({ "solaar", "config", dispositivo }).split ("\n")) {
            if (l.has_prefix ("#")) {
                var t = l.substring (1).strip ();
                if (t.has_prefix ("possible values:")) posibles = t;
                else if (titulo == "") titulo = t;
                else if (descripcion == "") descripcion = t;
                continue;
            }
            int i = l.index_of (" = ");
            if (i > 0 && titulo != "") {
                var a = new AjusteSolaar ();
                a.clave = l.substring (0, i).strip ();
                a.valor = l.substring (i + 3).strip ();
                a.titulo = titulo;
                a.descripcion = descripcion;
                bool simple = !a.valor.has_prefix ("{") && a.clave != "change-host";
                if (simple && posibles.contains ("on/true")) {
                    salida += a;
                } else if (simple && posibles.contains ("one of [")) {
                    int a1 = posibles.index_of ("[") + 1, a2 = posibles.index_of ("]");
                    foreach (var o in posibles.substring (a1, a2 - a1).split (",")) {
                        if (o.strip () != "") a.opciones += o.strip ();
                    }
                    salida += a;
                }
            }
            if (l.strip () == "") {
                titulo = ""; descripcion = ""; posibles = "";
            }
        }
        return salida;
    }

    /** Los dispositivos de `solaar show` con su batería. */
    DispositivoSolaar[] leer_dispositivos () {
        DispositivoSolaar[] salida = {};
        DispositivoSolaar? actual = null;
        try {
            var cab = new Regex ("^  \\d+: (.+)$");
            foreach (var l in ejecutar_solaar ({ "solaar", "show" }).split ("\n")) {
                MatchInfo m;
                if (cab.match (l, 0, out m)) {
                    actual = new DispositivoSolaar ();
                    actual.nombre = m.fetch (1);
                    salida += actual;
                } else if (actual != null && l.has_prefix ("     Battery:") && actual.bateria == "") {
                    actual.bateria = l.substring (l.index_of (":") + 1).strip ();
                }
            }
        } catch (RegexError e) {
        }
        foreach (var d in salida) d.ajustes = leer_ajustes (d.nombre);
        return salida;
    }

    // Lo último que se leyó de Solaar: `solaar show` tarda varios segundos, así que se lee al arrancar el residente y se
    // reutiliza un par de minutos; el panel se abre al instante y se actualiza solo si el dato ya es viejo.
    DispositivoSolaar[]? cache_solaar = null;
    int64 cache_solaar_en = 0;

    /** Se llama al arrancar el residente: deja leído lo de Solaar para cuando se abra el panel. */
    public void precalentar_solaar () {
        if (Environment.find_program_in_path ("solaar") == null) return;
        new Thread<bool> ("solaar-precalentar", () => {
            var devs = leer_dispositivos ();
            Idle.add (() => { cache_solaar = devs; cache_solaar_en = get_monotonic_time (); return false; });
            return true;
        });
    }

    public class PanelSolaar : Panel {
        Gtk.Box lista;
        Gtk.Spinner giro;

        public PanelSolaar () {
            id = "mint.solaar";
            nombre = "Solaar";
            palabras = "solaar, logitech, mouse, keyboard, battery, dpi, receiver, unifying, bolt";
            icono_tema = "solaar";
            grupo = "terceros";
        }

        public override Gtk.Widget? construir () {
            var caja = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 24);
            caja.get_style_context ().add_class ("mp-propio");
            margenes (caja, 20, 20, 20, 20);
            var izq = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            izq.set_size_request (190, -1);
            var icono = new Gtk.Image.from_icon_name ("solaar", Gtk.IconSize.DIALOG);
            icono.pixel_size = 96;
            icono.margin_top = 12;
            izq.pack_start (icono, false, false, 0);
            var t = new Gtk.Label ("Solaar");
            t.get_style_context ().add_class ("mp-titulo-negrita");
            izq.pack_start (t, false, false, 0);
            var d = new Gtk.Label ("Logitech devices");
            d.set_line_wrap (true);
            izq.pack_start (d, false, false, 0);
            caja.pack_start (izq, false, false, 0);

            var der = new Gtk.Box (Gtk.Orientation.VERTICAL, 10);
            lista = new Gtk.Box (Gtk.Orientation.VERTICAL, 14);
            giro = new Gtk.Spinner ();
            giro.start ();
            var cargando = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            cargando.pack_start (giro, false, false, 0);
            cargando.pack_start (new Gtk.Label ("Loading…"), false, false, 0);
            lista.pack_start (cargando, false, false, 0);
            var pant = new Gtk.ScrolledWindow (null, null);
            pant.set_policy (Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
            pant.set_size_request (-1, 300);
            pant.add (lista);
            der.pack_start (pant, true, true, 0);
            var pie = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            var av = new Gtk.Button.with_label ("Advanced…");
            av.clicked.connect (() => {
                try {
                    Process.spawn_async (null, { "solaar" }, null, SpawnFlags.SEARCH_PATH, null, null);
                } catch (Error e) {
                    warning ("solaar: %s", e.message);
                }
            });
            pie.pack_end (av, false, false, 0);
            der.pack_start (pie, false, false, 0);
            caja.pack_start (der, true, true, 0);
            caja.show_all ();
            cargar.begin ();
            return caja;
        }

        /** `solaar show` y `solaar config` tardan unos segundos: en un hilo, y la página se llena al terminar. */
        async void cargar () {
            DispositivoSolaar[] devs = {};
            bool fresco = cache_solaar != null && (get_monotonic_time () - cache_solaar_en) < 120 * 1000000;
            if (fresco) {
                devs = cache_solaar;
            } else {
                new Thread<bool> ("solaar", () => {
                    devs = leer_dispositivos ();
                    Idle.add (cargar.callback);
                    return true;
                });
                yield;
                cache_solaar = devs;
                cache_solaar_en = get_monotonic_time ();
            }
            giro.stop ();
            foreach (var h in lista.get_children ()) lista.remove (h);
            if (devs.length == 0) {
                lista.pack_start (new Gtk.Label ("No Logitech devices found."), false, false, 0);
            }
            foreach (var dev in devs) lista.pack_start (seccion (dev), false, false, 0);
            lista.show_all ();
        }

        Gtk.Widget seccion (DispositivoSolaar dev) {
            var s = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
            var cab = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            var n = new Gtk.Label (dev.nombre);
            n.xalign = 0;
            n.get_style_context ().add_class ("mp-titulo-negrita");
            cab.pack_start (n, true, true, 0);
            if (dev.bateria != "") {
                var b = new Gtk.Label ("Battery: %s".printf (dev.bateria.replace (", discharging.", "").replace (".", "")));
                cab.pack_end (b, false, false, 0);
            }
            s.pack_start (cab, false, false, 0);
            foreach (var a in dev.ajustes) {
                var fila = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 10);
                fila.margin_start = 12;
                var nombre_dev = dev.nombre;
                var clave = a.clave;
                if (a.opciones.length == 0) {
                    var c = new Gtk.CheckButton.with_label (a.titulo);
                    c.active = a.valor.down () == "true";
                    c.set_tooltip_text (a.descripcion);
                    c.toggled.connect (() => {
                        string[] cmd = { "solaar", "config", nombre_dev, clave, c.active ? "true" : "false" };
                        lanzar_solaar (cmd);
                    });
                    fila.pack_start (c, false, false, 0);
                } else {
                    var l = new Gtk.Label ("%s:".printf (a.titulo));
                    l.xalign = 0;
                    l.set_tooltip_text (a.descripcion);
                    fila.pack_start (l, true, true, 0);
                    var cb = new Gtk.ComboBoxText ();
                    foreach (var o in a.opciones) cb.append_text (o);
                    for (int i = 0; i < a.opciones.length; i++) if (a.opciones[i] == a.valor) cb.set_active (i);
                    cb.changed.connect (() => {
                        var v = cb.get_active_text ();
                        if (v != null) lanzar_solaar ({ "solaar", "config", nombre_dev, clave, v });
                    });
                    fila.pack_end (cb, false, false, 0);
                }
                s.pack_start (fila, false, false, 0);
            }
            return s;
        }

        static void lanzar_solaar (string[] cmd) {
            try {
                Process.spawn_async (null, cmd, null, SpawnFlags.SEARCH_PATH | SpawnFlags.STDOUT_TO_DEV_NULL | SpawnFlags.STDERR_TO_DEV_NULL, null, null);
            } catch (Error e) {
                warning ("solaar: %s", e.message);
            }
        }
    }
}
