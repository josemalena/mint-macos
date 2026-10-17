/*
 * Los usuarios que polkit autoriza para una acción y cómo se resuelve lo que se escribe en User Name
 * (igual que polkit/agente.py: el usuario o el nombre completo del GECOS, sin importar mayúsculas).
 */
namespace MacPolkit {
    public class Usuario : Object {
        public int uid;
        public string nombre;
        public Usuario (int uid, string nombre) {
            this.uid = uid;
            this.nombre = nombre;
        }
    }

    /** {login: Usuario} de las identidades que polkit propone (usuarios y miembros de grupos). */
    public HashTable<string, Usuario> usuarios_autorizados (List<Polkit.Identity> identidades) {
        var uids = new HashTable<string, bool> (str_hash, str_equal);
        foreach (var ident in identidades) {
            if (ident is Polkit.UnixUser) {
                uids[((Polkit.UnixUser) ident).get_uid ().to_string ()] = true;
            } else if (ident is Polkit.UnixGroup) {
                unowned Posix.Group? g = Posix.getgrgid ((Posix.gid_t) ((Polkit.UnixGroup) ident).get_gid ());
                if (g == null) {
                    continue;
                }
                foreach (unowned string login in g.gr_mem) {
                    unowned Posix.Passwd? p = Posix.getpwnam (login);
                    if (p != null) {
                        uids[((int) p.pw_uid).to_string ()] = true;
                    }
                }
                // los que lo tienen de grupo primario
                Posix.setpwent ();
                unowned Posix.Passwd? p;
                while ((p = Posix.getpwent ()) != null) {
                    if (p.pw_gid == g.gr_gid) {
                        uids[((int) p.pw_uid).to_string ()] = true;
                    }
                }
                Posix.endpwent ();
            }
        }
        var salida = new HashTable<string, Usuario> (str_hash, str_equal);
        foreach (var clave in uids.get_keys ()) {
            int uid = int.parse (clave);
            unowned Posix.Passwd? p = Posix.getpwuid ((Posix.uid_t) uid);
            if (p == null) {
                continue;
            }
            string nombre = p.pw_gecos.split (",")[0].strip ();
            salida[p.pw_name] = new Usuario (uid, nombre == "" ? p.pw_name : nombre);
        }
        return salida;
    }

    /** El login que corresponde a lo escrito; null si no es nadie de los autorizados. */
    public string? resolver_usuario (string texto, HashTable<string, Usuario> autorizados) {
        string t = string.joinv (" ", split_sin_vacios (texto));
        if (t == "") {
            return null;
        }
        if (autorizados.contains (t)) {
            return t;
        }
        string buscado = t.casefold ();
        string? hallado = null;
        autorizados.foreach ((login, u) => {
            if (hallado == null && u.nombre.casefold () == buscado) {
                hallado = login;
            }
        });
        return hallado;
    }

    string[] split_sin_vacios (string s) {
        string[] partes = {};
        foreach (var x in s.split_set (" \t\n")) {
            if (x != "") {
                partes += x;
            }
        }
        return partes;
    }

    /** Lo que se escribe de entrada: el nombre completo de quien está en la sesión (o su usuario). */
    public string nombre_por_defecto (HashTable<string, Usuario> autorizados, bool como_login) {
        unowned Posix.Passwd? p = Posix.getpwuid (Posix.getuid ());
        if (p != null && autorizados.contains (p.pw_name)) {
            return como_login ? p.pw_name : autorizados[p.pw_name].nombre;
        }
        string? mejor = null;
        autorizados.foreach ((l, u) => {
            if (mejor == null || u.nombre < mejor) {
                mejor = u.nombre;
            }
        });
        return mejor ?? "";
    }
}
