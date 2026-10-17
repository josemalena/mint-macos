# caso: ⌘Tab (cmdtab@macos) cambia de app y ⌘` entre ventanas de la misma  [PENDIENTE: necesita Cinnamon]
# límite: 120
prueba() {
  # cmdtab@macos es una extensión de Cinnamon (JS dentro del shell): en el Xephyr de las pruebas solo hay Muffin.
  # Pasos que hará cuando el marco tenga una sesión de Cinnamon anidada:
  #   1. abrir xed y un segundo xed con otro archivo; 2. ⌘Tab (Super+Tab) y soltar: el frente pasa a la otra app;
  #   3. ⌘` entre las dos ventanas de la misma app; 4. fallar si el frente no cambia.
  saltar "necesita una sesión de Cinnamon anidada (cmdtab@macos corre dentro de Cinnamon)"
}
