# Randomizador SebiLink de Pokemon Z

Implementacion: `multiplayer/SebiRandomizer.rb`, cargada al final del script principal.
Menu: `SebiLink > Randomizador`, tambien F12/Todas/Trucos. Nueva partida: se ofrece
antes de la introduccion. Hay que guardar la partida para conservar su configuracion.
Todas las opciones ON/OFF cambian con un clic; los ajustes numericos mantienen
su selector. Region usa el mismo funcionamiento de activar/desactivar al seleccionar.

## Verificar sin abrir el juego

Con Ruby disponible, desde la carpeta del juego:

```powershell
ruby 'tools/randomizer/verify-randomizer.rb'
ruby -c 'multiplayer/SebiRandomizer.rb'
ruby -c 'multiplayer/SebiVisualMultiplayer.rb'
```

La prueba usa codigo y datos reales del juego en memoria; no ejecuta el bloque
de arranque/compilacion de Essentials ni escribe saves, datos compilados o mapas.
Los avisos de constantes duplicadas SECRETSWORD/SASSYMINT pertenecen a los enums
originales. No iniciar Game.exe desde estas herramientas.

## Regenerar el catalogo

Descargar el CSV fuente de [PokeAPI](https://raw.githubusercontent.com/PokeAPI/pokeapi/master/data/v2/csv/pokemon_species.csv)
y pasarlo al constructor:

```powershell
ruby 'tools/randomizer/build-catalog.rb' 'ruta/pokemon_species.csv'
```

El SHA256 del CSV queda en el encabezado del catalogo. La union usa InternalName,
con aliases explicitos Nidoran; formas/variantes estan auditadas contra el script
MultipleForms actual. Al cambiar PBS o las formas del juego, revisar tambien la
tabla de formas en el constructor. El juego funciona offline con el catalogo local.

`inspect-events.rb 2 66 290 307` lee eventos concretos sin cargar RGSS.

## Prueba manual

1. Reiniciar Pokemon Z manualmente. En una partida existente, abrir SebiLink >
   Randomizador (y el mismo acceso desde F12), activar y guardar.
2. Dejar solo Kanto. Repetir encuentros en una ruta y pescando; solo deben aparecer
   especies de Kanto, con suerte distinta en cada encuentro (pueden repetirse).
3. Probar formas regionales y propias de Z por separado, y las exclusiones de
   legendarios/miticos; desactivar Alola debe impedir Raichu Alola.
4. Comprobar opciones de entrenador/regente, regalos, fosiles, tutor, MT,
   movimientos, habilidades, stock/precios y objetos. Desactivar una categoria
   conserva la regla original de esa categoria. Los NPC conservan la peticion.
5. Guardar/reabrir y alternar partidas: cada una debe recuperar sus propios ajustes.
   Desactivar todo restaura futuras lecturas/generaciones; no deshace especies,
   objetos o ataques que ya fueron entregados/aprendidos.
6. En una nueva partida de prueba, aceptar la configuracion inicial y verificar
   que preview y entrega de cada inicial coinciden; con iniciales OFF debe
   mantenerse la seleccion regional original.

No usar una partida existente para "Nuevo juego" ni sobrescribirla para esta prueba.
La copia original se mantiene como referencia. En la distribucion publica consulta
el README de la raiz; en el workspace privado, `docs/pokemon-z-sebilink-documentacion.md`.
