/*
 * El estado de las pantallas por el DisplayConfig de Cinnamon (org.cinnamon.Muffin.DisplayConfig, el mismo que usa cinnamon-settings):
 * GetCurrentState y ApplyMonitorsConfig. Sin Gtk: lo usa el panel Displays (paneles/pantallas.vala) y se puede probar aparte.
 */
namespace Preferencias {

    public class ModoPantalla {
        public string ident = "";
        public int ancho = 0;
        public int alto = 0;
        public double hertz = 0;
        public bool actual = false;
        public bool entrelazado = false;
    }

    public class MonitorFisico {
        public string conector = "";
        public List<ModoPantalla> modos = new List<ModoPantalla> ();

        /** El modo que está en uso, o el primero. */
        public ModoPantalla? modo_actual () {
            foreach (var m in modos) {
                if (m.actual) {
                    return m;
                }
            }
            return modos.length () > 0 ? modos.first ().data : null;
        }
    }

    public class MonitorLogico {
        public int x = 0;
        public int y = 0;
        public double escala = 1;
        public uint giro = 0;
        public bool primario = false;
        public string[] conectores = {};
    }

    public class EstadoPantallas {
        public uint serie = 0;
        public List<MonitorFisico> monitores = new List<MonitorFisico> ();
        public List<MonitorLogico> logicos = new List<MonitorLogico> ();

        /** El monitor y su lógico: el principal si hay varios. */
        public void monitor_actual (out MonitorFisico? monitor, out MonitorLogico? logico) {
            foreach (var lg in logicos) {
                if (lg.primario && lg.conectores.length > 0) {
                    foreach (var m in monitores) {
                        if (m.conector == lg.conectores[0]) {
                            monitor = m;
                            logico = lg;
                            return;
                        }
                    }
                }
            }
            monitor = monitores.length () > 0 ? monitores.first ().data : null;
            logico = logicos.length () > 0 ? logicos.first ().data : null;
            if (monitor == null || logico == null) {
                monitor = null;
                logico = null;
            }
        }

        /**
         * Los monitores lógicos listos para ApplyMonitorsConfig: cada uno con el modo que tiene ahora; al del `conector` se le cambia
         * el giro y/o el modo.
         */
        public Variant configuracion (string? conector = null, int giro = -1, string? modo = null) {
            var actual = new HashTable<string, string> (str_hash, str_equal);
            foreach (var m in monitores) {
                var ma = m.modo_actual ();
                if (ma != null) {
                    actual[m.conector] = ma.ident;
                }
            }
            var b = new VariantBuilder (new VariantType ("a(iiduba(ssa{sv}))"));
            foreach (var lg in logicos) {
                uint rot = lg.giro;
                if (lg.conectores.length > 0 && lg.conectores[0] == conector && giro >= 0) {
                    rot = (uint) giro;
                }
                var sb = new VariantBuilder (new VariantType ("a(ssa{sv})"));
                foreach (var c in lg.conectores) {
                    var id_modo = (c == conector && modo != null && modo != "") ? modo : (actual[c] ?? "");
                    sb.add ("(ss@a{sv})", c, id_modo, new Variant.array (new VariantType ("{sv}"), {}));
                }
                b.add ("(iiduba(ssa{sv}))", lg.x, lg.y, lg.escala, rot, lg.primario, sb);
            }
            return b.end ();
        }
    }

    const string DC_NOMBRE = "org.cinnamon.Muffin.DisplayConfig";
    const string DC_RUTA = "/org/cinnamon/Muffin/DisplayConfig";

    DBusProxy? proxy_pantallas () {
        try {
            return new DBusProxy.for_bus_sync (BusType.SESSION, DBusProxyFlags.NONE, null, DC_NOMBRE, DC_RUTA, DC_NOMBRE);
        } catch (Error e) {
            return null;
        }
    }

    /** GetCurrentState, o null si Cinnamon no contesta. */
    public EstadoPantallas? estado_actual () {
        var p = proxy_pantallas ();
        if (p == null) {
            return null;
        }
        Variant r;
        try {
            r = p.call_sync ("GetCurrentState", null, DBusCallFlags.NONE, 5000, null);
        } catch (Error e) {
            return null;
        }
        var estado = new EstadoPantallas ();
        estado.serie = r.get_child_value (0).get_uint32 ();
        var monitores = r.get_child_value (1);
        for (size_t i = 0; i < monitores.n_children (); i++) {
            var mv = monitores.get_child_value (i);
            var m = new MonitorFisico ();
            m.conector = mv.get_child_value (0).get_child_value (0).get_string ();
            var modos = mv.get_child_value (1);
            for (size_t j = 0; j < modos.n_children (); j++) {
                var mo = modos.get_child_value (j);
                var modo = new ModoPantalla ();
                modo.ident = mo.get_child_value (0).get_string ();
                modo.ancho = mo.get_child_value (1).get_int32 ();
                modo.alto = mo.get_child_value (2).get_int32 ();
                modo.hertz = mo.get_child_value (3).get_double ();
                var props = mo.get_child_value (6);
                var actual = props.lookup_value ("is-current", null);
                modo.actual = actual != null && actual.get_boolean ();
                var entrelazado = props.lookup_value ("is-interlaced", null);
                modo.entrelazado = entrelazado != null && entrelazado.get_boolean ();
                m.modos.append (modo);
            }
            estado.monitores.append (m);
        }
        var logicos = r.get_child_value (2);
        for (size_t i = 0; i < logicos.n_children (); i++) {
            var lv = logicos.get_child_value (i);
            var lg = new MonitorLogico ();
            lg.x = lv.get_child_value (0).get_int32 ();
            lg.y = lv.get_child_value (1).get_int32 ();
            lg.escala = lv.get_child_value (2).get_double ();
            lg.giro = lv.get_child_value (3).get_uint32 ();
            lg.primario = lv.get_child_value (4).get_boolean ();
            var mons = lv.get_child_value (5);
            string[] conectores = {};
            for (size_t j = 0; j < mons.n_children (); j++) {
                conectores += mons.get_child_value (j).get_child_value (0).get_string ();
            }
            lg.conectores = conectores;
            estado.logicos.append (lg);
        }
        return estado;
    }

    /** ApplyMonitorsConfig: método 1 = temporal, 2 = persistente. */
    public void aplicar_pantallas (uint serie, Variant config, uint metodo) throws Error {
        var p = proxy_pantallas ();
        if (p == null) {
            throw new IOError.FAILED ("Cinnamon no contesta");
        }
        var arg = new Variant ("(uu@a(iiduba(ssa{sv}))@a{sv})", serie, metodo, config, new Variant.array (new VariantType ("{sv}"), {}));
        p.call_sync ("ApplyMonitorsConfig", arg, DBusCallFlags.NONE, 10000, null);
    }
}
