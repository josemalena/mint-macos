/*
 * org.mintmacos.Hoy1: lo que el Notification Center enseña en su vista Today, listo para dibujar. Hoy, el clima de Open-Meteo
 * (open-meteo.com: gratis y sin clave; recibe las coordenadas de la ciudad configurada, nada más). El calendario espera una
 * fuente (el de iCloud/Thunderbird de Apple ID): sin fuente no se muestra.
 *
 * La ciudad sale de ~/.config/mint-macos/hoy.json: {"ciudad": "Santo Domingo", "lat": 18.4861, "lon": -69.9312}; sin el archivo,
 * Santo Domingo (la de José). La respuesta se guarda 30 min; pedirla con el caché viejo devuelve lo que hay y refresca aparte.
 */
namespace Hoy {
    public delegate void Aviso ();

    [DBus (name = "org.mintmacos.Hoy1")]
    public class Servicio : Object {
        const int64 CADUCA_US = 30 * 60 * 1000000;
        const string CIUDAD = "Santo Domingo";
        const double LAT = 18.4861;
        const double LON = -69.9312;

        string ciudad = CIUDAD;
        double lat = LAT;
        double lon = LON;
        // el último clima leído
        bool hay = false;
        double temperatura = 0;
        double minima = 0;
        double maxima = 0;
        uint codigo = 0;
        bool es_dia = true;
        int64 leido_us = 0;
        bool pidiendo = false;

        public signal void cambio ();

        public Servicio () {
            leer_config ();
        }

        void leer_config () {
            try {
                var p = new Json.Parser ();
                p.load_from_file (Path.build_filename (Environment.get_user_config_dir (), "mint-macos", "hoy.json"));
                var o = p.get_root ().get_object ();
                if (o.has_member ("ciudad")) ciudad = o.get_string_member ("ciudad");
                if (o.has_member ("lat")) lat = o.get_double_member ("lat");
                if (o.has_member ("lon")) lon = o.get_double_member ("lon");
            } catch (GLib.Error e) {
                // sin archivo: Santo Domingo
            }
        }

        /** El clima de la ciudad; vacío si todavía no se pudo leer (sin red). Con el caché viejo, devuelve lo que hay y refresca. */
        public HashTable<string, Variant> clima () throws GLib.Error {
            var t = new HashTable<string, Variant> (str_hash, str_equal);
            if (get_monotonic_time () - leido_us > CADUCA_US) refrescar_ya.begin ();
            if (!hay) return t;
            t.insert ("ciudad", new Variant.string (ciudad));
            t.insert ("temperatura", new Variant.double (temperatura));
            t.insert ("minima", new Variant.double (minima));
            t.insert ("maxima", new Variant.double (maxima));
            t.insert ("codigo", new Variant.uint32 (codigo));
            t.insert ("es_dia", new Variant.boolean (es_dia));
            t.insert ("descripcion", new Variant.string (descripcion (codigo)));
            t.insert ("icono", new Variant.string (icono (codigo, es_dia)));
            t.insert ("fuente", new Variant.string ("open-meteo.com"));
            return t;
        }

        public void refrescar () throws GLib.Error {
            refrescar_ya.begin ();
        }

        async void refrescar_ya () {
            if (pidiendo) return;
            pidiendo = true;
            try {
                var url = "https://api.open-meteo.com/v1/forecast?latitude=%s&longitude=%s&current=temperature_2m,weather_code,is_day&daily=temperature_2m_max,temperature_2m_min&timezone=auto&forecast_days=1"
                    .printf (lat.to_string ().replace (",", "."), lon.to_string ().replace (",", "."));
                uint8[] datos;
                yield File.new_for_uri (url).load_contents_async (null, out datos, null);
                var p = new Json.Parser ();
                p.load_from_data ((string) datos);
                var raiz = p.get_root ().get_object ();
                var actual = raiz.get_object_member ("current");
                var diario = raiz.get_object_member ("daily");
                temperatura = actual.get_double_member ("temperature_2m");
                codigo = (uint) actual.get_int_member ("weather_code");
                es_dia = actual.get_int_member ("is_day") == 1;
                maxima = diario.get_array_member ("temperature_2m_max").get_double_element (0);
                minima = diario.get_array_member ("temperature_2m_min").get_double_element (0);
                hay = true;
                leido_us = get_monotonic_time ();
                cambio ();
            } catch (GLib.Error e) {
                // sin red o respuesta rara: se queda con lo que había y se vuelve a intentar en la próxima pregunta
                leido_us = get_monotonic_time () - CADUCA_US + 60 * 1000000;     // reintenta en un minuto
            }
            pidiendo = false;
        }

        /** Los códigos WMO de Open-Meteo (su documentación): descripciones en inglés, sin adornos. */
        static string descripcion (uint c) {
            switch (c) {
            case 0: return "Clear";
            case 1: return "Mostly Clear";
            case 2: return "Partly Cloudy";
            case 3: return "Overcast";
            case 45: case 48: return "Fog";
            case 51: case 53: case 55: case 56: case 57: return "Drizzle";
            case 61: case 63: case 65: case 66: case 67: return "Rain";
            case 71: case 73: case 75: case 77: return "Snow";
            case 80: case 81: case 82: return "Showers";
            case 85: case 86: return "Snow Showers";
            case 95: case 96: case 99: return "Thunderstorms";
            }
            return "";
        }

        static string icono (uint c, bool dia) {
            switch (c) {
            case 0: case 1: return dia ? "weather-clear-symbolic" : "weather-clear-night-symbolic";
            case 2: return dia ? "weather-few-clouds-symbolic" : "weather-few-clouds-night-symbolic";
            case 3: return "weather-overcast-symbolic";
            case 45: case 48: return "weather-fog-symbolic";
            case 51: case 53: case 55: case 56: case 57: return "weather-showers-scattered-symbolic";
            case 61: case 63: case 65: case 66: case 67: case 80: case 81: case 82: return "weather-showers-symbolic";
            case 71: case 73: case 75: case 77: case 85: case 86: return "weather-snow-symbolic";
            case 95: case 96: case 99: return "weather-storm-symbolic";
            }
            return "weather-overcast-symbolic";
        }
    }

    public class Anfitrion : Object {
        static Servicio? servicio = null;

        public static void iniciar (owned Aviso? si_falla = null) {
            if (servicio != null) return;
            servicio = new Servicio ();
            Bus.own_name (BusType.SESSION, "org.mintmacos.Hoy1", BusNameOwnerFlags.NONE,
                (con) => {
                    try {
                        con.register_object ("/org/mintmacos/Hoy1", servicio);
                    } catch (IOError e) {
                        warning ("org.mintmacos.Hoy1: %s", e.message);
                    }
                },
                null,
                () => {
                    warning ("org.mintmacos.Hoy1 ya existe");
                    if (si_falla != null) si_falla ();
                });
        }
    }
}
