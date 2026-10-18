/*
 * Las gráficas: áreas y líneas sobre las últimas muestras, de la más vieja (izquierda) a la más nueva (derecha). Una sola
 * clase para el CPU LOAD apilado de Catalina, las de MEMORY PRESSURE / IO / PACKETS y las de la pestaña Resources.
 */
namespace Actividad {
    public class Serie : Object {
        public string clave = "";
        public double r = 0;
        public double g = 0;
        public double b = 0;
        public double[] datos = {};

        public Serie (string clave, double r, double g, double b) {
            this.clave = clave;
            this.r = r;
            this.g = g;
            this.b = b;
        }
    }

    public class Area : Gtk.DrawingArea {
        public GenericArray<Serie> series = new GenericArray<Serie> ();
        /** 0 = automático (el mayor valor visible, con `piso` como mínimo del eje). */
        public double maximo = 0;
        public double piso = 1;
        public bool apilado = false;
        public bool rejilla = true;
        public int muestras = 60;
        public bool relleno = true;
        public bool borde = true;

        public Area (int ancho, int alto) {
            set_size_request (ancho, alto);
            draw.connect (dibujar);
        }

        public Serie agregar (string clave, double r, double g, double b) {
            var s = new Serie (clave, r, g, b);
            series.add (s);
            return s;
        }

        public void poner (string clave, double[] datos) {
            for (int i = 0; i < series.length; i++) {
                if (series[i].clave == clave) series[i].datos = datos;
            }
            queue_draw ();
        }

        double techo () {
            if (maximo > 0) return maximo;
            double m = piso;
            int n = muestras;
            if (apilado) {
                for (int k = 0; k < n; k++) {
                    double suma = 0;
                    for (int i = 0; i < series.length; i++) suma += dato (series[i], k, n);
                    if (suma > m) m = suma;
                }
            } else {
                for (int i = 0; i < series.length; i++)
                    for (int k = 0; k < n; k++) if (dato (series[i], k, n) > m) m = dato (series[i], k, n);
            }
            return m * 1.1;
        }

        /** La muestra k de n visibles (las últimas n; si hay menos, las de la izquierda no existen). */
        double dato (Serie s, int k, int n) {
            int idx = s.datos.length - n + k;
            return (idx >= 0 && idx < s.datos.length) ? s.datos[idx] : 0;
        }

        bool existe (Serie s, int k, int n) {
            int idx = s.datos.length - n + k;
            return idx >= 0 && idx < s.datos.length;
        }

        bool dibujar (Cairo.Context cr) {
            double w = get_allocated_width ();
            double h = get_allocated_height ();
            cr.set_source_rgb (1, 1, 1);
            cr.rectangle (0, 0, w, h);
            cr.fill ();
            if (rejilla) {
                cr.set_source_rgba (0, 0, 0, 0.10);
                cr.set_line_width (1);
                for (int i = 1; i < 4; i++) {
                    cr.move_to (0, Math.floor (h * i / 4) + 0.5);
                    cr.line_to (w, Math.floor (h * i / 4) + 0.5);
                }
                cr.stroke ();
            }
            int n = muestras;
            double tope = techo ();
            double paso = w / (n - 1);
            var base_ = new double[n];
            for (int i = 0; i < series.length; i++) {
                var s = series[i];
                bool alguno = false;
                for (int k = 0; k < n; k++) if (existe (s, k, n)) { alguno = true; break; }
                if (!alguno) continue;
                // el trazo: arriba de lo apilado hasta ahora
                if (relleno) {
                    cr.set_source_rgba (s.r, s.g, s.b, 0.30);
                    bool abierto = false;
                    double xi = 0;
                    for (int k = 0; k < n; k++) {
                        if (!existe (s, k, n)) continue;
                        double x = k * paso;
                        double y = h - (base_[k] * (apilado ? 1 : 0) + dato (s, k, n)) / tope * h;
                        if (!abierto) { cr.move_to (x, h - (apilado ? base_[k] / tope * h : 0)); cr.line_to (x, y); abierto = true; xi = x; }
                        else cr.line_to (x, y);
                    }
                    if (abierto) {
                        for (int k = n - 1; k >= 0; k--) {
                            if (!existe (s, k, n) || k * paso < xi) continue;
                            cr.line_to (k * paso, h - (apilado ? base_[k] / tope * h : 0));
                        }
                        cr.close_path ();
                        cr.fill ();
                    }
                }
                cr.set_source_rgb (s.r, s.g, s.b);
                cr.set_line_width (1.2);
                bool primero = true;
                for (int k = 0; k < n; k++) {
                    if (!existe (s, k, n)) continue;
                    double y = h - ((apilado ? base_[k] : 0) + dato (s, k, n)) / tope * h;
                    if (primero) { cr.move_to (k * paso, y); primero = false; } else cr.line_to (k * paso, y);
                }
                cr.stroke ();
                if (apilado) for (int k = 0; k < n; k++) base_[k] += dato (s, k, n);
            }
            if (borde) {
                cr.set_source_rgba (0, 0, 0, 0.35);
                cr.set_line_width (1);
                cr.rectangle (0.5, 0.5, w - 1, h - 1);
                cr.stroke ();
            }
            return true;
        }
    }
}
