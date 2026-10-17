/*
 * El agente de polkit: hereda PolkitAgent.Listener (en Python no se podía: PyGObject no completa el callback
 * asíncrono del método virtual). La autenticación es de PolkitAgent.Session y su ayudante setuid; aquí solo se
 * le pasa lo que se teclea en el campo, sin guardarlo.
 */
namespace MacPolkit {
    public const string BOTON_AJENO = "OK";
    const string ANOTACION_BOTON = "org.mintmacos.boton";
    const string ANOTACION_ICONO = "org.mintmacos.icono";
    public bool VERBOSO = false;

    public void log (string m) {
        if (VERBOSO) {
            stderr.printf ("[mint-macos-polkit] %s\n", m);
        }
    }

    /** (texto del botón, id del panel para el ícono): de la .policy de la acción, o («OK», null). */
    void anotaciones (string action_id, out string boton, out string? icono) {
        boton = BOTON_AJENO;
        icono = null;
        try {
            var autoridad = Polkit.Authority.get_sync (null);
            foreach (var d in autoridad.enumerate_actions_sync (null)) {
                if (d.get_action_id () == action_id) {
                    boton = d.get_annotation (ANOTACION_BOTON) ?? BOTON_AJENO;
                    icono = d.get_annotation (ANOTACION_ICONO);
                    break;
                }
            }
        } catch (Error e) {
            log ("sin anotaciones: " + e.message);
        }
    }

    delegate void Fin (bool ok);

    public class Agente : PolkitAgent.Listener {
        public override async bool initiate_authentication (string action_id, string message, string icon_name,
                Polkit.Details details, string cookie, List<Polkit.Identity> identities,
                Cancellable? cancellable) throws Error {
            log ("petición " + action_id);
            var autorizados = usuarios_autorizados (identities);
            if (autorizados.size () == 0) {
                throw new IOError.FAILED ("No hay usuarios autorizados para esta acción.");
            }
            string boton;
            string? icono;
            anotaciones (action_id, out boton, out icono);

            var dialogo = new Dialogo (message, boton, icono, autorizados, variante_de (action_id));
            PolkitAgent.Session? sesion = null;
            bool terminado = false;
            bool gano = false;
            SourceFunc continuar = initiate_authentication.callback;

            Fin terminar = (ok) => {
                if (terminado) {
                    return;
                }
                terminado = true;
                gano = ok;
                if (sesion != null) {
                    sesion.cancel ();
                    sesion = null;
                }
                dialogo.borrar_clave ();
                dialogo.destroy ();
                Idle.add (() => { continuar (); return false; });
            };

            dialogo.cancelado.connect (() => { terminar (false); });
            if (cancellable != null) {
                cancellable.cancelled.connect (() => { terminar (false); });
            }
            dialogo.aceptado.connect ((login) => {
                PolkitAgent.Session s;
                try {
                    s = new PolkitAgent.Session (new Polkit.UnixUser.for_name (login), cookie);
                } catch (Error e) {
                    dialogo.sacudir ();
                    return;
                }
                sesion = s;
                s.request.connect ((_s, _pregunta, _eco) => { s.response (dialogo.clave.text); });
                s.show_error.connect ((_t) => { });
                s.show_info.connect ((_t) => { });
                s.completed.connect ((_s, gana) => {
                    sesion = null;
                    if (gana) {
                        terminar (true);
                    } else if (!terminado) {
                        dialogo.sacudir ();
                    }
                });
                s.initiate ();
            });

            yield;
            if (!gano) {
                throw new IOError.CANCELLED ("Autenticación cancelada.");
            }
            return true;
        }
    }
}
