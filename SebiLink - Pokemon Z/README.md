# SebiLink - Pokemon Z

**Version SebiLink: 1.7.2.**

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
| Historial | Encuentros, capturas, derrotas, muertes/debilitamientos, objetos y compras con fecha, ruta e IDs persistentes |
| Multijugador | Salas, jugadores en mapa, seguidores/seguimiento, marcadores, intercambios, PvP y espectador integrado |
| IA opcional | Chat, consejo de combate, analisis de equipo/postcombate y preparacion PvP mediante un puente CodeXRay propio |
| Randomizador | Salvajes por encuentro, entrenadores/regentes, iniciales, fosiles, NPC/regalos, habilidades, ataques/MT/tutores, objetos/precios y filtros |

En `SebiLink > Randomizador`, seleccionar una opcion ON/OFF cambia su estado
inmediatamente. Los numeros abren un selector. `Region` permite activar/desactivar
las nueve generaciones. `Formas regionales`, `Pokemon propios de Z` y `Formas
propias de Z` se controlan por separado. Con salvajes activados cada encuentro
hace un sorteo independiente; puede repetirse una especie por azar.
Se ofrece activar/configurar el randomizador antes de elegir el inicial en una
partida nueva. Todas sus opciones se guardan al cambiarlas en
`SebiLinkConfig/sebilink.ini`, junto al resto de ajustes de SebiLink. Son opciones
del jugador, compartidas por sus partidas; cargar otra partida mantiene las reglas
del INI. Al cargar por primera vez una partida antigua, importa las opciones que
todavia no existan en el INI. Los Pokemon, iniciales elegidos y resultados de MT
ya generados siguen siendo datos de la partida.

## Historial de actividad

Se registra automaticamente la actividad nueva en
`Saved Games/Pokemon Z/SebiLinkConfig/Historial/historial.sebilog`, dentro del perfil del jugador.
Todos sus archivos se agrupan dentro de `Historial/`: registros cifrados, claves,
backups antiguos, diagnosticos, cola `history-pending/`, codigo `history-viewer/`
y `Ver historial SebiLink.bat`. Los archivos sueltos de versiones anteriores
se mueven automaticamente conservando sus bytes. Si estan en uso o hay archivos
distintos con el mismo nombre, se detiene la migracion sin sobrescribirlos.
El INI de opciones sigue en `SebiLinkConfig/sebilink.ini`.
El archivo esta cifrado con AES-256-CBC y autenticado con HMAC-SHA256. Cada
historial tiene claves aleatorias independientes, cifradas para el administrador
con RSA-3072/OAEP y guardadas dentro del propio archivo. Cada evento usa un IV
nuevo y autentica la secuencia y el evento anterior.
Editar el archivo a mano produce un error de integridad; no se aceptan datos alterados.

Todos los jugadores que instalen este paquete empiezan a registrar sin elegir
una contrasena. `multiplayer/activity-public-key.txt` contiene solo la clave
publica del administrador (XML RSA); puede publicarse en GitHub y mantenerse en
futuras versiones. No regenerarla en cada release. Ninguna contrasena ni clave
privada forma parte del paquete o del INI. `historial.key` es la clave/checkpoint
local protegido con DPAPI para poder seguir escribiendo automaticamente.

El jugador puede entregar **solo `historial.sebilog`** al administrador. Desde
`SebiLink > Ver registros`, `F12 > Sistema > Ver registros` o el ejecutable
`Ver historial SebiLink.bat`, creado junto al historial dentro de `Historial/`,
se abre el visor. No hace falta iniciar el juego. El administrador usa su
`historial-admin.sebikey` y su misma contrasena
para leer los historiales de todos, sin pedir ninguna contrasena a los jugadores.
Si su clave no esta en la carpeta habitual, el visor permite seleccionarla.
Muestra el contenido verificado en una ventana de solo lectura; no escribe
una exportacion descifrada en disco. La clave privada se protege con AES/HMAC
y PBKDF2-SHA256 (250.000 iteraciones y sal aleatoria).

El visor tiene tabla ordenable por columnas, busqueda en todos los datos y
filtros combinables por ID, evento, ruta y fechas. Seleccionar una fila muestra
todos los campos, Pokemon enviados/recibidos, movimientos, habilidades,
valores anteriores/nuevos y atributos adicionales en un arbol de detalle y
en los datos originales. `Abrir historial` permite consultar archivos recibidos
de otros jugadores; `Recargar` vuelve a leerlo y pide otra vez la contrasena.
Las fechas de la tabla usan la hora local del Windows que abre el visor; la
fecha y zona originales permanecen completas en el detalle.
La columna `Fecha y hora` incluye segundos. Los registros antiguos con el
nombre de zona horaria de MKXP se muestran usando su fecha y hora locales
guardadas; los nuevos usan un desfase numerico. Los accesos desde el juego,
F12 y el BAT abren el mismo visor con sus filtros y detalle completos.

El acceso directo y `history-viewer/` contienen solo codigo publico del visor,
sin contrasenas ni material de claves privadas. Se crean/actualizan al iniciar
el escritor de historial y al abrir Ver registros. No necesitan permisos de
administrador. La clave privada cifrada se conserva por separado: sin ese
archivo y la contrasena correcta no se abre un historial universal.

**Administrador: conserva una copia privada de `historial-admin.sebikey`.**
La contrasena permite abrir esa clave; si se pierde el archivo, la contrasena
sola no recupera los historiales. Nunca incluirlo en GitHub ni enviarlo junto al mod.
Cada evento conserva fecha/hora local con zona horaria, ruta/coordenadas,
entrenador y archivo de partida. Si el helper no puede escribir, muestra un error
al abrir el historial y mantiene eventos pendientes solo en memoria hasta poder
cifrarlos. Cerrar el juego antes de resolver ese error puede perder los pendientes.

Cada Pokemon tiene un ID propio: dos capturas de la misma especie son distintas;
encuentro, captura y muerte comparten el mismo ID. Se conserva con el guardado
normal del Pokemon. Los eventos incluyen sus movimientos/PP, habilidad, nivel,
forma, IVs/EVs, stats, naturaleza, objeto, shiny, datos de origen y atributos
adicionales del juego. La fecha de captura queda asociada al Pokemon.

Eventos: `wild_encounter`, `pokemon_captured`, `wild_defeated`, `wild_result`,
`pokemon_death`, `pokemon_fainted`, `item_obtained` e `item_purchased`.
Tambien se registran `setting_changed`, `settings_snapshot`, `pokemon_healed`,
`pokemon_traded`, `item_used`, `sebilink_option_selected` y las acciones
iniciadas/finalizadas de SebiLink, F12, SebiHeX y carga de partidas.
Los cambios del INI incluyen campo, valor anterior/nuevo y fecha/hora: por
ejemplo, probabilidad shiny `1%` a `10%`, activar/desactivar randomizador,
regiones, controles y preferencias de ventanas. No se generan cambios falsos
al guardar el mismo valor. La observacion del archivo tambien registra cambios
externos visibles mientras el juego esta abierto, sin sustituir los registros
exactos de las interfaces.
Las ventanas nativas guardan los cambios en una cola temporal cifrada con DPAPI,
`Historial/history-pending/*.audit`; el juego los incorpora al mismo historial universal
y solo entonces elimina la cola. Se conserva la hora real del cambio y se
adjunta por separado el contexto del juego observado al incorporarlo. No se
escriben colas de eventos en texto plano. El visor sigue siendo de solo lectura;
no incluye ninguna opcion para editar registros antiguos, incluso con contrasena.
Un usuario con control de su Windows puede borrar archivos o modificar el juego
y sus claves locales: el cifrado local no garantiza un sistema antitrampas.

Curaciones: Pokemon/ID completos, PS, estado y PP anteriores/posteriores,
ruta/coordenadas y origen (juego, Centro Pokemon SebiLink u objeto). Incluye
recuperaciones parciales y el intento de curar cuando ya estaba completamente
curado; los huevos no producen curaciones falsas. Intercambios normales,
multijugador, prodigiosos y de huevo: datos completos del Pokemon entregado
y recibido, IDs distintos, interlocutor, origen y fecha. Las acciones tambien
conservan cambios reales en Pokemon del PC, inventario, dinero y resultado.
El resultado de cada salvaje indica `captured`, `defeated`, `escaped` o
`not_captured`. Capturas descartadas se registran con `retained=false`.
La muerte permanente se distingue del debilitamiento normal; PvP/entrenamiento
sin muerte permanente se registra como debilitamiento. Tambien detecta PS a cero
fuera de combate en Pokemon del equipo.

Objetos: ID/nombre, cantidad realmente recibida y origen (`ground`, `gift`,
`game`, `shop`). Compras: cantidad, precio total/unitario y `via=game` o
`via=sebilink`, con la tienda original seleccionada cuando se abre desde SebiLink.
Compras canceladas o revertidas por mochila llena no se registran como compras;
las Honor Balls extra se registran como regalos de la tienda.

El historial se anade en el momento del evento y no retrocede al cargar un save
anterior. No reconstruye capturas antiguas ni modifica partidas para crear registros.
IDs nuevos quedan persistidos cuando guardas normalmente. El archivo es local,
puede incluir datos personales y no forma parte del paquete ni de GitHub.

Un historial anterior `historial.jsonl` se cifra y comprueba antes de quitar la
copia en claro. Los archivos con cifrado personal de versiones anteriores se
conservan; para migrarlos se requiere la contrasena anterior, no se sobrescriben.
No se reemplaza silenciosamente una clave existente. Respaldar juntos `.sebilog` y `.key` conserva
el checkpoint que tambien detecta la eliminacion de registros finales. Una copia
sin checkpoint puede verificar la cadena conservada, pero no demostrar que faltan
eventos finales. Alguien con control de la cuenta de Windows puede extraer claves,
borrar/restaurar archivos o modificar el juego: esta es proteccion local frente a
lectura/edicion directa, no una prueba inviolable contra trampas.

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

### Actualizaciones desde GitHub

El origen publico es [Sebilebi/SebiLink](https://github.com/Sebilebi/SebiLink).
Cada inicio busca la version de Pokemon Z en la tabla del README de la raiz.
Si es mas nueva, pregunta «Actualizar ahora?» con Si/No. No la instala al rechazar.
La busqueda inicial ocurre en segundo plano; sin Internet el juego sigue funcionando.
«Buscar actualizaciones» esta en SebiLink y en F12 > Todas / Sistema. Una busqueda
manual informa si ya tienes la version mas reciente o si falla la conexion.
La cabecera de F12 muestra la version instalada del complemento.

Al aceptar en una partida cargada, primero se guarda en su slot actual. Si falla
el guardado, se cancela. Se pausa el juego mientras se descargan y verifican
exclusivamente los archivos del manifiesto de esta carpeta, desde un unico commit.
No se clona el repositorio completo y no hace falta Git. Despues se cierra el juego,
se sustituyen los archivos del complemento y se abre Game.exe automaticamente.
No se inicia una partida automaticamente tras reiniciar: elige continuar.
No se permite actualizar en combate, eventos o transiciones.

El instalador conserva la configuracion MKXP personalizada, anade su preload,
y guarda una copia de los archivos sustituidos en SebiLinkConfig/updates/runtime.
Si falla la instalacion, restaura la version anterior. No toca scripts originales,
assets, partidas, conversaciones ni configuracion personal. El relay local se
cierra al reiniciar y tendras que volver a abrir/unirte a tu sala.

Para publicar una version nueva, aumenta la version del complemento en
multiplayer/updates/update-source.json, en este README y en la tabla del README
de la raiz (por ejemplo 1.0.0 a 1.1.0). Regenera MANIFEST.json con la herramienta
de release del workspace; debe tener esa version y los SHA-256 actualizados.
Sube la carpeta completa y el README de la raiz juntos en el mismo commit.
Una version publicada mas baja nunca provoca una bajada de version automatica.
Las copias antiguas sin actualizador necesitan copiar este paquete una primera vez.

### Instalacion manual y desactivacion

Para actualizar, cierra el juego y vuelve a copiar el contenido del complemento.
Configuraciones, snapshots, chats, logs y respaldos se generan localmente en
`%USERPROFILE%/Saved Games/Pokemon Z/SebiLinkConfig`; no forman parte del paquete.
Las partidas mantienen su ubicacion original. Toda la configuracion del jugador
(multijugador, controles, trucos, PvP, IA, slots, preferencias de ventanas y
randomizador) se guarda en un unico `SebiLinkConfig/sebilink.ini`. El antiguo
`multiplayer.ini` solo se importa una vez y ya no se escribe. Desde 1.1.1, el INI incluye desde el arranque las 128 preferencias, aunque no hayas abierto sus menus: 36 randomizer_*, 16 control_0..15 originales, tres extra_control_*, nueve slots y todas sus opciones. Se migran los ajustes de partidas antiguas sin reemplazar elecciones existentes del INI. No hace falta guardar
la partida para conservar un cambio de opciones. No subas esos datos al repositorio.

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
