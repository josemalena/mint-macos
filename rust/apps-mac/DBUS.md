# org.mintmacos.AppsMac1

Las .app de Mac sin .desktop (decisión de José, 27-10-2026): el Launchpad, el
Muelle y Fynder le preguntan por el nombre, la clase de ventana y los íconos de
una app que no está abierta.

- **Servicio:** `mint-macos-apps-mac` (rust/apps-mac), sin root.
- **Activación:** la arranca D-Bus. Vive mientras siga en el bus alguien que lo
  llamó; si no queda nadie, se va al minuto sin llamadas.
- **Bus y ruta:** bus de sesión, nombre `org.mintmacos.AppsMac1`, ruta `/org/mintmacos/AppsMac1`.
- **Contrato:** [org.mintmacos.AppsMac1.xml](org.mintmacos.AppsMac1.xml) trae los
  métodos, las señales y las claves de cada app.

| Método o señal | Qué hace |
|---|---|
| `Resolver(s clave) → a{sv}` | Busca por ruta, clase `darling-…` o bundle id, y por último por nombre si es único. `{}` si no la encuentra |
| `ResolverVarias(as claves) → aa{sv}` | Lo mismo para varias claves, en el mismo orden |
| `Listar() → aa{sv}` | Las de /Applications y ~/Applications con sus subcarpetas, por nombre |
| `IconosListos(s id, a{us} iconos)` | Ya están los PNG que una llamada devolvió vacíos |
| `AppsCambiaron()` | Algo entró o salió de las carpetas (inotify) |

Los PNG quedan en `~/.cache/mint-macos/apps-mac/<id>-<px>.png`, con un
`<id>.sello` que los invalida si cambia el Info.plist o el .icns.

El archivo de activación (`~/.local/share/dbus-1/services/org.mintmacos.AppsMac1.service`):

```
[D-BUS Service]
Name=org.mintmacos.AppsMac1
Exec=/home/jmalena/.local/bin/mint-macos-apps-mac
```

Prueba a mano en un bus aparte:

```
dbus-run-session -- sh -c 'mint-macos-apps-mac & sleep 1;
  gdbus call --session -d org.mintmacos.AppsMac1 -o /org/mintmacos/AppsMac1 \
    -m org.mintmacos.AppsMac1.Resolver darling-com.apple.textedit'
```
