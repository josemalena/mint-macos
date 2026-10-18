/*
 * La cara de Vala de org.mintmacos.Monitor1: suscribirse mientras la ventana esté abierta, pedir procesos, paneles y series
 * cuando llega `Muestreado`. Una columna sin dato no viene y aquí queda en -1 (la ventana la dibuja vacía).
 */
namespace Actividad {
    public class Fila : Object {
        public int pid = 0;
        public int ppid = 0;
        public string nombre = "";
        public string icono = "";
        public string usuario = "";
        public string tipo = "";
        public string origen = "";
        public double cpu = -1;
        public double tiempo_cpu = -1;       // ms
        public double hilos = -1;
        public double despertares = -1;
        public double memoria = -1;
        public double comprimida = -1;
        public double escrito = -1;
        public double leido = -1;

        static double numero (Variant d, string k) {
            var v = d.lookup_value (k, null);
            if (v == null) return -1;
            switch (v.get_type_string ()) {
            case "d": return v.get_double ();
            case "t": return (double) v.get_uint64 ();
            case "u": return (double) v.get_uint32 ();
            case "i": return (double) v.get_int32 ();
            case "x": return (double) v.get_int64 ();
            }
            return -1;
        }

        static string texto (Variant d, string k) {
            var v = d.lookup_value (k, VariantType.STRING);
            return v != null ? v.get_string () : "";
        }

        public static Fila desde (Variant d) {
            var f = new Fila ();
            f.pid = (int) numero (d, "pid");
            f.ppid = (int) numero (d, "ppid");
            f.nombre = texto (d, "nombre");
            f.icono = texto (d, "icono");
            f.usuario = texto (d, "usuario");
            f.tipo = texto (d, "tipo");
            f.origen = texto (d, "origen");
            f.cpu = numero (d, "cpu");
            f.tiempo_cpu = numero (d, "tiempo_cpu");
            f.hilos = numero (d, "hilos");
            f.despertares = numero (d, "despertares");
            f.memoria = numero (d, "memoria");
            f.comprimida = numero (d, "comprimida");
            f.escrito = numero (d, "escrito");
            f.leido = numero (d, "leido");
            return f;
        }
    }

    public class Resumen : Object {
        HashTable<string, double?> v = new HashTable<string, double?> (str_hash, str_equal);

        public static Resumen desde (Variant d) {
            var r = new Resumen ();
            var it = d.iterator ();
            string k;
            Variant val;
            while (it.next ("{sv}", out k, out val)) {
                switch (val.get_type_string ()) {
                case "d": r.v.insert (k, val.get_double ()); break;
                case "t": r.v.insert (k, (double) val.get_uint64 ()); break;
                case "u": r.v.insert (k, (double) val.get_uint32 ()); break;
                case "x": r.v.insert (k, (double) val.get_int64 ()); break;
                case "i": r.v.insert (k, (double) val.get_int32 ()); break;
                }
            }
            return r;
        }

        public bool tiene (string k) { return v.contains (k); }
        public double dato (string k) { return v.contains (k) ? v.lookup (k) : 0; }
    }

    public class Motor : Object {
        const string NOMBRE = "org.mintmacos.Monitor1";
        const string RUTA = "/org/mintmacos/Monitor1";
        static Motor? _inst = null;
        public static Motor instancia {
            get {
                if (_inst == null) _inst = new Motor ();
                return _inst;
            }
        }

        DBusConnection? con = null;
        public signal void muestreado ();
        public signal void proceso_termino (int pid);

        public bool conectar (out string error) {
            error = "";
            if (con != null) return true;
            try {
                con = Bus.get_sync (BusType.SESSION);
                con.signal_subscribe (NOMBRE, NOMBRE, "Muestreado", RUTA, null, DBusSignalFlags.NONE, () => { muestreado (); });
                con.signal_subscribe (NOMBRE, NOMBRE, "ProcesoTermino", RUTA, null, DBusSignalFlags.NONE,
                    (c, s, r, i, n, p) => { proceso_termino (p.get_child_value (0).get_int32 ()); });
            } catch (GLib.Error e) {
                error = e.message;
                return false;
            }
            return true;
        }

        async Variant llamar (string metodo, Variant? args = null) throws GLib.Error {
            string e = "";
            if (con == null && !conectar (out e)) throw new IOError.FAILED ("%s", e);
            return yield con.call (NOMBRE, RUTA, NOMBRE, metodo, args, null, DBusCallFlags.NONE, 10000, null);
        }

        public async void suscribir (uint ms) throws GLib.Error {
            yield llamar ("Suscribir", new Variant.tuple ({ new Variant.uint32 (ms) }));
        }

        public async void soltar () throws GLib.Error {
            yield llamar ("Soltar");
        }

        /** Las columnas pedidas (vacío = todas): pedir solo las de la pestaña le ahorra a los dos lados armar y leer lo que no se ve. */
        public async GenericArray<Fila> procesos (string[] columnas) throws GLib.Error {
            var r = yield llamar ("Procesos", new Variant.tuple ({ new Variant.strv (columnas) }));
            var arr = r.get_child_value (0);
            var lista = new GenericArray<Fila> ();
            for (size_t i = 0; i < arr.n_children (); i++) lista.add (Fila.desde (arr.get_child_value (i)));
            return lista;
        }

        public async Resumen resumen () throws GLib.Error {
            var r = yield llamar ("Resumen");
            return Resumen.desde (r.get_child_value (0));
        }

        /** Hasta `segundos` de una serie, del más viejo al más nuevo. */
        public async double[] historial (string serie, uint segundos) throws GLib.Error {
            var r = yield llamar ("Historial", new Variant.tuple ({ new Variant.string (serie), new Variant.uint32 (segundos) }));
            var arr = r.get_child_value (0);
            double[] vals = {};
            for (size_t i = 0; i < arr.n_children (); i++) vals += arr.get_child_value (i).get_child_value (1).get_double ();
            return vals;
        }

        public async bool salir (int pid, bool forzar) throws GLib.Error {
            var r = yield llamar (forzar ? "ForzarSalida" : "Salir", new Variant.tuple ({ new Variant.int32 (pid) }));
            return r.get_child_value (0).get_boolean ();
        }
    }
}
