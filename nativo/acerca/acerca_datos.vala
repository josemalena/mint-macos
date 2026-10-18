/*
 * Lo que enseña About This Mac / About This PC. Todo lo que se lee al arrancar (modelo, procesador, memoria, gráficos,
 * serie, sistema y logo) sale de /run/mint-macos/equipo.json, que escribe un solo programa (mint-macos-equipo): aquí no
 * se lee /proc, ni lspci ni DMI. Si el archivo no está, solo salen los datos de os-release y ninguna fila de hardware;
 * un campo que no viene (serie, velocidad de la memoria) no muestra fila. Lo que cambia con el sistema corriendo
 * (las pantallas por su EDID y los discos) se lee en vivo.
 */
namespace Acerca {
    public const string RUTA_EQUIPO = "/run/mint-macos/equipo.json";

    /** Las pruebas apuntan a otro equipo.json con MINT_MACOS_EQUIPO. */
    string ruta_equipo () {
        return Environment.get_variable ("MINT_MACOS_EQUIPO") ?? RUTA_EQUIPO;
    }

    public class Equipo : Object {
        public string tipo = "pc";                 // «mac» o «pc»
        public string nombre = "";                 // «Mac mini (Late 2012)», o fabricante y modelo en un PC
        public string sistema = "Linux";
        public string version = "";                // «22.3 (Zena)»
        public string logo = "";
        public string logo_icono = "";
        public string serie = "";
        public string procesador = "";             // «2.5 GHz Dual-Core Intel Core i5»
        public string memoria = "";                // «16 GB 1333 MHz DDR3»
        public string graficos = "";               // «Intel HD Graphics 4000»
        public int64[] ranuras = {};               // bytes de cada ranura de memoria, en el orden de SMBIOS; 0 = vacía

        /** «About This Mac» o «About This PC», según el equipo. */
        public string etiqueta_menu () {
            return tipo == "mac" ? "About This Mac" : "About This PC";
        }

        public static Equipo cargar () {
            var e = new Equipo ();
            try {
                var p = new Json.Parser ();
                p.load_from_file (ruta_equipo ());
                var o = p.get_root ().get_object ();
                e.tipo = o.get_string_member_with_default ("tipo", "pc");
                e.nombre = o.get_string_member_with_default ("nombre", "");
                if (e.nombre == "") {
                    e.nombre = "%s %s".printf (o.get_string_member_with_default ("fabricante", ""),
                                               o.get_string_member_with_default ("identificador", "")).strip ();
                }
                if (o.has_member ("serie") && !o.get_null_member ("serie")) e.serie = o.get_string_member ("serie");
                e.procesador = texto_de (o, "procesador");
                e.memoria = texto_de (o, "memoria");
                if (o.has_member ("memoria") && o.get_member ("memoria").get_node_type () == Json.NodeType.OBJECT) {
                    var m = o.get_object_member ("memoria");
                    if (m.has_member ("ranuras") && m.get_member ("ranuras").get_node_type () == Json.NodeType.ARRAY) {
                        var r = m.get_array_member ("ranuras");
                        int64[] lista = {};
                        for (uint i = 0; i < r.get_length (); i++) {
                            var el = r.get_object_element (i);
                            lista += (el.has_member ("tamano") && !el.get_null_member ("tamano")) ? el.get_int_member ("tamano") : 0;
                        }
                        e.ranuras = lista;
                    }
                }
                if (o.has_member ("graficos") && o.get_member ("graficos").get_node_type () == Json.NodeType.ARRAY) {
                    var g = o.get_array_member ("graficos");
                    if (g.get_length () > 0) e.graficos = g.get_object_element (0).get_string_member_with_default ("texto", "");
                }
                e.logo = o.get_string_member_with_default ("logo", "");
                e.logo_icono = o.get_string_member_with_default ("logo_icono", "");
                if (o.has_member ("sistema")) {
                    var s = o.get_object_member ("sistema");
                    e.sistema = s.get_string_member_with_default ("nombre", "Linux");
                    e.version = s.get_string_member_with_default ("version", "");
                }
                return e;
            } catch (Error err) {
                // sin el servicio: solo os-release
            }
            var os = os_release ();
            e.sistema = os.contains ("NAME") ? os["NAME"] : "Linux";
            e.version = os.contains ("VERSION") ? os["VERSION"] : "";
            e.logo_icono = os.contains ("LOGO") ? os["LOGO"] : "";
            return e;
        }

        static string texto_de (Json.Object o, string clave) {
            if (!o.has_member (clave) || o.get_member (clave).get_node_type () != Json.NodeType.OBJECT) return "";
            return o.get_object_member (clave).get_string_member_with_default ("texto", "");
        }

        /** «Linux Mint» y «Zena» de «22.3 (Zena)»: el nombre del sistema y su nombre de versión, si lo trae. */
        public string version_numero () {
            int i = version.index_of (" (");
            return i > 0 ? version.substring (0, i) : version;
        }

        public string version_nombre () {
            int i = version.index_of (" (");
            if (i < 0 || !version.has_suffix (")")) return "";
            return version.substring (i + 2, version.length - i - 3);
        }
    }

    public string leer (string ruta) {
        try {
            string t;
            FileUtils.get_contents (ruta, out t);
            return t.strip ();
        } catch (Error e) {
            return "";
        }
    }

    HashTable<string, string> os_release () {
        var h = new HashTable<string, string> (str_hash, str_equal);
        foreach (var linea in leer ("/etc/os-release").split ("\n")) {
            int i = linea.index_of_char ('=');
            if (i > 0) h[linea.substring (0, i)] = linea.substring (i + 1).replace ("\"", "");
        }
        return h;
    }

    string ejecutar (string[] cmd) {
        try {
            var p = new Subprocess.newv (cmd, SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_SILENCE);
            string salida;
            p.communicate_utf8 (null, null, out salida, null);
            return salida ?? "";
        } catch (Error e) {
            return "";
        }
    }

    // ── Overview ────────────────────────────────────────────────────────

    /** Dónde está el sistema: la etiqueta del volumen raíz, o el nombre del sistema. */
    public string disco_de_arranque (string respaldo) {
        var montajes = montajes_de_discos ();
        var dev = montajes.lookup ("/");
        var etiqueta = dev != null ? etiqueta_de (dev) : "";
        return etiqueta != "" ? etiqueta : respaldo;
    }

    // ── Displays ────────────────────────────────────────────────────────

    public class Pantalla : Object {
        public string nombre = "";     // «LEN T2454pA Display»
        public double pulgadas = 0;        // con un decimal, del EDID
        public int ancho = 0;
        public int alto = 0;
    }

    /** Las pantallas conectadas, con el nombre y el tamaño que dice su EDID (la Mac lo lee igual). */
    public Pantalla[] pantallas () {
        Pantalla[] salida = {};
        var display = Gdk.Display.get_default ();
        if (display == null) return salida;
        for (int i = 0; i < display.get_n_monitors (); i++) {
            var m = display.get_monitor (i);
            var g = m.get_geometry ();
            var p = new Pantalla ();
            p.ancho = g.width * m.get_scale_factor ();
            p.alto = g.height * m.get_scale_factor ();
            var salida_x = m.get_model () ?? "";
            var edid = edid_de (salida_x);
            double diag = 0;
            if (edid.length >= 128) {
                p.nombre = nombre_edid (edid);
                diag = Math.sqrt ((double) (edid[21] * edid[21] + edid[22] * edid[22])) / 2.54;
            }
            if (diag <= 0 && m.get_width_mm () > 0) {
                diag = Math.sqrt ((double) (m.get_width_mm () * m.get_width_mm () + m.get_height_mm () * m.get_height_mm ())) / 25.4;
            }
            p.pulgadas = Math.round (diag * 10) / 10.0;
            if (p.nombre == "") p.nombre = salida_x != "" ? salida_x : "Display";
            salida += p;
        }
        return salida;
    }

    /** El EDID de la salida «HDMI-3» (en sysfs es «card1-HDMI-A-3»). */
    uint8[] edid_de (string salida_x) {
        if (salida_x == "") return {};
        try {
            var dir = Dir.open ("/sys/class/drm");
            string? n;
            while ((n = dir.read_name ()) != null) {
                int i = n.index_of_char ('-');
                if (i < 0) continue;
                var conector = n.substring (i + 1).replace ("-A-", "-");
                if (conector != salida_x) continue;
                uint8[] datos;
                FileUtils.get_data ("/sys/class/drm/%s/edid".printf (n), out datos);
                if (datos.length < 128) continue;
                return datos;
            }
        } catch (Error e) {
        }
        return {};
    }

    /** «LEN T2454pA Display»: las 3 letras del fabricante (bytes 8-9) y el nombre del descriptor 0xFC. */
    string nombre_edid (uint8[] b) {
        int fab = (b[8] << 8) | b[9];
        var id = "%c%c%c".printf ((char) (((fab >> 10) & 31) + 64), (char) (((fab >> 5) & 31) + 64), (char) ((fab & 31) + 64));
        string modelo = "";
        for (int o = 54; o <= 108; o += 18) {
            if (b[o] == 0 && b[o + 1] == 0 && b[o + 3] == 0xFC) {
                var sb = new StringBuilder ();
                for (int k = 5; k < 18 && b[o + k] != 0x0A; k++) sb.append_c ((char) b[o + k]);
                modelo = sb.str.strip ();
            }
        }
        // muchos monitores ya traen el fabricante en el nombre («LEN T2454pA»)
        if (modelo == "") return "%s Display".printf (id);
        return modelo.has_prefix (id) ? "%s Display".printf (modelo) : "%s %s Display".printf (id, modelo);
    }

    int64 tamano_de_dispositivo (string dispositivo) {
        return int64.parse (ejecutar ({ "lsblk", "-bdno", "SIZE", dispositivo }).strip ());
    }

    /** «24-inch» o «17.1-inch»: un decimal solo si hace falta, como la Mac. */
    public string pulgadas_texto (double p) {
        var t = "%.1f".printf (p).replace (",", ".");
        if (t.has_suffix (".0")) t = t.substring (0, t.length - 2);
        return "%s-inch".printf (t);
    }

    // ── Storage ─────────────────────────────────────────────────────────

    public class Volumen : Object {
        public string nombre = "";
        public string dispositivo = "";
        public string montaje = "";
        public int64[] categoria_bytes = {};     // uno por categoría de «categorias ()»
        public int pendientes = 0;               // du que faltan por terminar: >0 = «Calculating…»
        public int64 tamano = 0;
        public int64 libre = 0;
        public string descripcion = "";     // «500 GB\nSolid State\nSATA Drive»
        public bool externo = false;        // por USB o ieee1394 y no removible
        public bool removible = false;      // un pendrive, una tarjeta (RM=1)
    }

    /** El nombre que fstab le da a un montaje (x-gvfs-name=MacMini), para los volúmenes sin etiqueta. */
    HashTable<string, string>? nombres_fstab = null;
    HashTable<string, string>? uuids_fstab = null;

    /**
     * Los APFS de fstab (fsapfs, montados por FUSE con fsapfsmount): en /proc/self/mounts salen como /dev/fuse. Se resuelven
     * por su disco físico: el UUID de fstab → /dev/disk/by-uuid/<uuid> → /dev/sdb2. Así el disco sale como interno o externo
     * según el bus del disco, igual que Fynder.
     */
    void sumar_apfs_de_fstab (HashTable<string, string> h, string[] montados_fuse) {
        foreach (var l in leer ("/etc/fstab").split ("\n")) {
            var t = l.strip ();
            if (t.has_prefix ("#") || !t.contains ("fsapfs")) continue;
            string[] c = {};
            foreach (var x in t.split_set (" \t")) if (x != "") c += x;
            if (c.length < 4 || c[2] != "fsapfs" || !c[0].has_prefix ("UUID=")) continue;
            var mp = c[1];
            bool montado = false;
            foreach (var m in montados_fuse) if (m == mp) montado = true;
            if (!montado) continue;
            var dev = Posix.realpath ("/dev/disk/by-uuid/" + c[0].substring (5));
            if (dev == null) continue;
            h[mp] = dev;
            uuids_fstab[mp] = c[0].substring (5);
            foreach (var o in c[3].split (",")) if (o.has_prefix ("x-gvfs-name=")) nombres_fstab[mp] = o.substring (12);
        }
    }

    /** {"version":1,"uuid","total","libre",…} de /run/mint-macos/apfs/<uuid>.json. */
    bool medida_apfs (string uuid, out int64 total, out int64 libre) {
        total = 0;
        libre = 0;
        try {
            var p = new Json.Parser ();
            p.load_from_file ("%s/%s.json".printf (Environment.get_variable ("MINT_MACOS_APFS") ?? "/run/mint-macos/apfs", uuid));
            var o = p.get_root ().get_object ();
            if (!o.has_member ("total") || !o.has_member ("libre")) return false;
            total = o.get_int_member ("total");
            libre = o.get_int_member ("libre");
            return total > 0 && libre >= 0 && libre <= total;
        } catch (Error e) {
            return false;
        }
    }

    /** punto de montaje → dispositivo, de los discos reales (nada de loop, tmpfs ni /boot/efi). */
    HashTable<string, string> montajes_de_discos () {
        var h = new HashTable<string, string> (str_hash, str_equal);
        nombres_fstab = new HashTable<string, string> (str_hash, str_equal);
        uuids_fstab = new HashTable<string, string> (str_hash, str_equal);
        string[] fuse = {};
        foreach (var l in leer ("/proc/self/mounts").split ("\n")) {
            var c = l.split (" ");
            if (c.length >= 3 && c[0] == "/dev/fuse") fuse += c[1].replace ("\\040", " ");
            // solo discos de verdad: nada de loop, de FUSE (las imágenes montadas) ni de tmpfs
            if (c.length < 3 || !Regex.match_simple ("^/dev/(sd[a-z]+|nvme[0-9]+n[0-9]+p|mmcblk[0-9]+p|vd[a-z]+|dm-)[0-9]*$", c[0])) continue;
            var mp = c[1].replace ("\\040", " ");
            if (mp.has_prefix ("/boot") || mp.has_prefix ("/var/snap") || mp.has_prefix ("/snap")) continue;
            h[mp] = c[0];
        }
        sumar_apfs_de_fstab (h, fuse);
        return h;
    }

    string etiqueta_de (string dispositivo) {
        try {
            var dir = Dir.open ("/dev/disk/by-label");
            string? n;
            while ((n = dir.read_name ()) != null) {
                var destino = FileUtils.read_link ("/dev/disk/by-label/" + n);
                if (Path.get_basename (destino) == Path.get_basename (dispositivo)) {
                    return Uri.unescape_string (n.replace ("\\x20", " ")) ?? n;
                }
            }
        } catch (Error e) {
        }
        return "";
    }

    string describir_disco (string dispositivo, out bool externo, out bool removible) {
        externo = false;
        removible = false;
        var padre = ejecutar ({ "lsblk", "-no", "PKNAME", dispositivo }).strip ();
        var base_ = padre != "" ? "/dev/" + padre : dispositivo;
        var campos = ejecutar ({ "lsblk", "-dnb", "-o", "SIZE,ROTA,TRAN,RM", base_ }).strip ().split (" ");
        string[] c = {};
        foreach (var x in campos) if (x != "") c += x;
        if (c.length < 2) return "";
        var bytes = int64.parse (c[0]);
        var tam = bytes >= 900000000000 ? "%.0f TB".printf (bytes / 1e12 < 1.5 ? 1.0 : bytes / 1e12) : "%d GB".printf ((int) Math.round (bytes / 1e9));
        if (bytes >= 900000000000 && bytes < 1500000000000) tam = "1 TB";
        var tran = c.length > 2 ? c[2].up () : "";
        // La misma regla que Fynder (udisks2): removible si RM=1; externo si va por USB o ieee1394; interno si no.
        removible = c.length > 3 && c[c.length - 1] == "1";
        externo = !removible && (tran == "USB" || tran == "IEEE1394");
        if (removible || externo) return "External %s\n%s Disk".printf (tam, tran != "" ? tran : "USB");
        return "%s\n%s\n%s".printf (tam, c[1] == "0" ? "Solid State" : "Hard Disk", tran != "" ? tran + " Drive" : "Drive");
    }

    public Volumen[] volumenes (string nombre_sistema) {
        Volumen[] salida = {};
        var vistos = new HashTable<string, string> (str_hash, str_equal);
        var montajes = montajes_de_discos ();
        string[] llaves = {};
        montajes.foreach ((k, d) => { llaves += k.dup (); });
        // la raíz primero, el resto por nombre
        for (int i = 1; i < llaves.length; i++) {
            var x = llaves[i];
            int j = i - 1;
            while (j >= 0 && (llaves[j] != "/" && (x == "/" || strcmp (llaves[j], x) > 0))) {
                llaves[j + 1] = llaves[j];
                j--;
            }
            llaves[j + 1] = x;
        }
        foreach (var mp in llaves) {
            var dev = montajes[mp];
            if (vistos.contains (dev)) continue;
            vistos[dev] = "1";
            var v = new Volumen ();
            v.dispositivo = dev;
            v.montaje = mp;
            var et = etiqueta_de (dev);
            if (et != "") v.nombre = et;
            else if (nombres_fstab != null && nombres_fstab.contains (mp)) v.nombre = nombres_fstab[mp];
            else if (mp == "/") v.nombre = nombre_sistema;
            else v.nombre = Path.get_basename (mp);
            try {
                var info = File.new_for_path (mp).query_filesystem_info ("filesystem::size,filesystem::free", null);
                v.tamano = (int64) info.get_attribute_uint64 ("filesystem::size");
                v.libre = (int64) info.get_attribute_uint64 ("filesystem::free");
                if (v.tamano == 0) {         // los APFS por FUSE no dan statfs: solo se sabe lo que mide la partición
                    v.tamano = tamano_de_dispositivo (dev);
                    v.libre = -1;
                    // …salvo que el lector de discos de Infra haya medido el contenedor (/run/mint-macos/apfs/<uuid>.json, en
                    // bytes). El libre es del contenedor entero, como «available» en la Mac. Sin el archivo no hay barra.
                    int64 total_c = 0, libre_c = 0;
                    if (uuids_fstab != null && uuids_fstab.contains (mp) && medida_apfs (uuids_fstab[mp], out total_c, out libre_c)) {
                        v.tamano = total_c;
                        v.libre = libre_c;
                    }
                }
            } catch (Error e) {
                continue;
            }
            bool ext, rem;
            v.descripcion = describir_disco (dev, out ext, out rem);
            v.externo = ext;
            v.removible = rem;
            salida += v;
        }
        return salida;
    }

    // ── Categorías de Storage ───────────────────────────────────────────

    public class Categoria : Object {
        public string nombre;
        public string[] rutas;
        public double r;
        public double g;
        public double b;
        public Categoria (string nombre, string[] rutas, double r, double g, double b) {
            this.nombre = nombre;
            this.rutas = rutas;
            this.r = r; this.g = g; this.b = b;
        }
    }

    /** Las categorías de la barra, con los colores de la captura de High Sierra (Documentos, Fotos, Apps…). Other es el resto. */
    public Categoria[] categorias () {
        string[] docs = {};
        foreach (var t in new UserDirectory[] { UserDirectory.DOCUMENTS, UserDirectory.DESKTOP }) {
            var r = Environment.get_user_special_dir (t);
            if (r != null) docs += r;
        }
        string[] fotos = {};
        var pic = Environment.get_user_special_dir (UserDirectory.PICTURES);
        if (pic != null) fotos += pic;
        string[] audio = {};
        var mus = Environment.get_user_special_dir (UserDirectory.MUSIC);
        if (mus != null) audio += mus;
        string[] pelis = {};
        var vid = Environment.get_user_special_dir (UserDirectory.VIDEOS);
        if (vid != null) pelis += vid;
        string[] apps = { "/usr", "/opt", "/var/lib/flatpak", "/snap", "/var/lib/snapd" };
        return {
            new Categoria ("Documents", docs, 0.824, 0.447, 0.867),
            new Categoria ("Photos", fotos, 0.286, 0.859, 0.290),
            new Categoria ("Apps", apps, 0.0, 0.678, 0.957),
            new Categoria ("Audio", audio, 1.0, 0.157, 0.412),
            new Categoria ("Movies", pelis, 0.596, 0.8, 0.98)
        };
    }

    /** El volumen que contiene la ruta (el de punto de montaje más largo que la precede). */
    Volumen? volumen_de (string ruta, Volumen[] vols) {
        var real = Posix.realpath (ruta);
        if (real == null) return null;
        Volumen? mejor = null;
        foreach (var v in vols) {
            bool contiene = v.montaje == "/" || real == v.montaje || real.has_prefix (v.montaje + "/");
            if (contiene && (mejor == null || v.montaje.length > mejor.montaje.length)) mejor = v;
        }
        return mejor;
    }

    public delegate void AlCalcular ();

    /**
     * Calcula en segundo plano cuánto ocupa cada categoría en cada volumen (du -sbx, hasta 90 s por ruta) y avisa a
     * medida que llegan. Mientras un volumen tenga `pendientes` > 0 está «calculando».
     */
    public void calcular_categorias (Volumen[] vols, Categoria[] cats, owned AlCalcular al_avanzar) {
        foreach (var v in vols) {
            v.categoria_bytes = new int64[cats.length];
        }
        for (int i = 0; i < cats.length; i++) {
            var idx = i;
            foreach (var ruta in cats[i].rutas) {
                if (!FileUtils.test (ruta, FileTest.EXISTS)) continue;
                // si la carpeta de usuario es el propio HOME (así la deja el sistema de José) no es una categoría
                var real_ruta = Posix.realpath (ruta);
                var real_home = Posix.realpath (Environment.get_home_dir ());
                if (real_ruta != null && real_ruta == real_home) continue;
                var v = volumen_de (ruta, vols);
                if (v == null) continue;
                v.pendientes++;
                try {
                    var p = new Subprocess.newv ({ "timeout", "90", "du", "-sbx", ruta },
                                                 SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_SILENCE);
                    p.communicate_utf8_async.begin (null, null, (o, res) => {
                        try {
                            string salida;
                            p.communicate_utf8_async.end (res, out salida, null);
                            var t = (salida ?? "").split ("\t");
                            if (t.length > 0) v.categoria_bytes[idx] += int64.parse (t[0]);
                        } catch (Error e) {
                        }
                        v.pendientes--;
                        al_avanzar ();
                    });
                } catch (Error e) {
                    v.pendientes--;
                }
            }
        }
    }

    /** «92.58 GB» / «1 TB» / «190 MB», como las cifras de la Mac (base 10). */
    public string tamano_legible (int64 b) {
        if (b >= 1000000000000) return "%s TB".printf (cifra (b / 1e12));
        if (b >= 1000000000) return "%s GB".printf (cifra (b / 1e9));
        return "%d MB".printf ((int) Math.round (b / 1e6));
    }

    string cifra (double d) {
        var s = "%.2f".printf (d);
        if (s.contains (".")) s = s.chomp ().replace (",", ".");
        while (s.has_suffix ("0")) s = s.substring (0, s.length - 1);
        if (s.has_suffix (".")) s = s.substring (0, s.length - 1);
        return s;
    }
}

namespace Acerca {
    /** «8 GB» por ranura («» si está vacía). */
    public string[] ranuras_texto (int64[] r) {
        string[] s = {};
        foreach (var b in r) s += b > 0 ? "%d GB".printf ((int) Math.round (b / 1073741824.0)) : "";
        return s;
    }

    /** Lo leído del equipo, en texto: lo usan las pruebas (mac-acerca --texto). */
    public string resumen () {
        var e = Equipo.cargar ();
        var sb = new StringBuilder ();
        sb.append ("menu: %s\n".printf (e.etiqueta_menu ()));
        sb.append ("sistema: %s | versión %s | nombre %s\n".printf (e.sistema, e.version_numero (), e.version_nombre ()));
        sb.append ("equipo: %s\n".printf (e.nombre));
        sb.append ("ranuras: %s\n".printf (string.joinv (",", ranuras_texto (e.ranuras))));
        sb.append ("procesador: %s\nmemoria: %s\ndisco de arranque: %s\ngráficos: %s\nserie: %s\n".printf (
            e.procesador, e.memoria, disco_de_arranque (e.sistema), e.graficos, e.serie));
        foreach (var p in pantallas ()) sb.append ("pantalla: %s | %s | %d x %d\n".printf (p.nombre, pulgadas_texto (p.pulgadas), p.ancho, p.alto));
        foreach (var v in volumenes (e.sistema)) {
            sb.append ("volumen: %s | %s de %s | %s\n".printf (v.nombre, v.libre < 0 ? "?" : tamano_legible (v.libre), tamano_legible (v.tamano), v.descripcion.replace ("\n", " / ")));
        }
        return sb.str;
    }
}
