# SebiLink - Pokemon Z

Complemento para **Pokemon Z V2.18 de ericlostie, Windows/MKXP**.
Esta carpeta contiene el codigo de SebiLink y su configuracion de arranque.
Necesitas conseguir el juego original por separado. No incluye ejecutables,
DLL, mapas, scripts originales, PBS, graficos, audio ni partidas.

## Instalacion: copiar y jugar

1. Cierra Pokemon Z. Conserva una copia de tu `mkxp.json` si lo has personalizado.
2. Copia **el contenido de esta carpeta**, no la carpeta contenedora, a la carpeta
   del juego donde esta `Game.exe`. Combina `multiplayer` y acepta sustituir
   `mkxp.json` y los archivos de SebiLink si ya existian.
3. Abre `Game.exe` normalmente. Aparece `SebiLink` en el menu de pausa.
   F12 abre la guia; F7, SebiHeX; F8, el gestor de partidas.

No hace falta instalar Ruby, Node.js ni ejecutar un instalador para las funciones
locales. `mkxp.json` carga `multiplayer/SebiLinkBootstrap.rb`, que modifica en
memoria el menu de pausa y carga SebiLink antes de `Main`. El numero de scripts
se mantiene y `Data/Scripts.rxdata` queda intacto. El arranque es idempotente y
tambien reconoce el loader de instalaciones anteriores.
No se reemplaza `preload.rb` ni se activa su parche para otros motores.
F12 deja de reiniciar el juego.
Si ya has personalizado scripts/menu con otros mods, la compatibilidad no esta garantizada.

## Funciones incluidas

| Area | Modificaciones |
| --- | --- |
| Menu/controles | SebiLink integrado, guia F12, teclas extra configurables, PokemonDB y efectividades |
| Pokemon/combate | Centro Pokemon, PC, tiendas/NPC, cambios de forma/habilidad, entrenamiento, equipos Showdown, ayudas y trucos |
| Guardados | SebiHeX F7, gestor F8, slots rapidos y respaldos automaticos |
| Multijugador | Salas, jugadores en mapa, seguidores/seguimiento, marcadores, intercambios, PvP y espectador integrado |
| IA opcional | Chat, consejo de combate, analisis de equipo/postcombate y preparacion PvP mediante un puente CodeXRay propio |
| Randomizador | Salvajes por encuentro, entrenadores/regentes, iniciales, fosiles, NPC/regalos, habilidades, ataques/MT/tutores, objetos/precios y filtros |

En `SebiLink > Randomizador`, seleccionar una opcion ON/OFF cambia su estado
inmediatamente. Los numeros abren un selector. `Region` permite activar/desactivar
las nueve generaciones. `Formas regionales`, `Pokemon propios de Z` y `Formas
propias de Z` se controlan por separado. Con salvajes activados cada encuentro
hace un sorteo independiente; puede repetirse una especie por azar.
Se ofrece activar/configurar el randomizador antes de elegir el inicial en una
partida nueva. Sus reglas pertenecen a cada partida y se conservan al guardarla.

## Multijugador e IA

Para **crear una sala** instala Node.js y permite la conexion TCP al puerto 54545
en tu firewall. Para conectarte a otro servidor no necesitas Node.js.
Usa Tailscale o una red accesible por todos y configura la direccion desde el menu
Multijugador. El paquete arranca sin conexion multijugador activada ni sala personal.
Los scripts `multiplayer/start-server*.ps1` permiten gestionar el relay propio.

La IA necesita una instalacion propia de CodeXRay y su puente
`scripts/ask-debian-codex.ps1`; no se incluyen cuentas ni el servicio de IA.
En `SebiLinkConfig/sebilink.ini` configura `codex_ai_bridge_script`,
`codex_ai_host` y `codex_ai_user` con tus propios valores. Las plantillas y el
contexto de juego portable se incluyen en `multiplayer/ai-codex/gameplay-ai.md`.
Si existe una skill local `sebi-pokelink`, el hub la prefiere.

## Actualizar, desactivar y datos personales

Para actualizar, cierra el juego y vuelve a copiar el contenido del complemento.
Configuraciones, snapshots, chats, logs y respaldos se generan localmente en
`%USERPROFILE%/Saved Games/Pokemon Z/SebiLinkConfig`; no forman parte del paquete.
Las partidas mantienen su ubicacion original. No subas esos datos al repositorio.

Para desactivar SebiLink en una instalacion original, restaura tu `mkxp.json`
anterior o elimina `multiplayer/SebiLinkBootstrap.rb` de `preloadScript` y vuelve
a poner `enableReset` en `true`. Conserva el resto del juego. Si ya tenias el
loader binario de un SebiLink anterior, restaura tambien su backup previo de
`Data/Scripts.rxdata`; desactivar el preload no elimina ese loader antiguo.
Las partidas con cambios hechos por el editor/trucos conservan esos cambios.

## Desarrollo y procedencia

`MANIFEST.json` enumera los archivos y SHA-256 de esta distribucion.
`tools/randomizer` incluye la comprobacion offline del randomizador; necesita
Ruby y los datos del juego local, que no se distribuyen. El arranque se ha
comprobado sobre scripts originales y modificados con un harness MKXP simulado;
la comprobacion visual dentro del juego requiere ejecutarlo manualmente.
Arquitectura del preload: [codigo de MKXP](https://github.com/Ancurio/mkxp/blob/master/binding-mri/binding-mri.cpp).

Pokemon Z pertenece a su autor; Pokemon y sus elementos pertenecen a sus respectivos
titulares. Este paquete no concede derechos sobre el juego ni incluye una licencia
inventada para terceros. La estructura de publicacion es `SebiLink/SebiLink - Pokemon Z`,
con una carpeta hermana por cada juego futuro.
