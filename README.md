# SebiLink

Modificaciones por juego. Cada carpeta contiene solo su complemento, sin el juego original.

## Versiones actuales

<!-- SEBILINK_VERSIONS_BEGIN -->
| Juego | Version SebiLink | Carpeta |
| --- | --- | --- |
| Pokemon Z V2.18 | 1.0.0 | SebiLink - Pokemon Z |
<!-- SEBILINK_VERSIONS_END -->

La version corresponde al complemento SebiLink, independientemente de la version
del juego original. El actualizador lee esta tabla para cada juego; de momento
solo esta implementado para Pokemon Z. Conserva los marcadores de la tabla.

Pokemon Z busca nuevas versiones al arrancar y desde «Buscar actualizaciones»
en el menu SebiLink o F12. Siempre pide confirmacion. Al aceptar guarda la partida
cargada, descarga solo su carpeta, verifica el manifiesto, actualiza y reinicia.
La version instalada aparece en la cabecera de F12.

```text
SebiLink/
  SebiLink - Pokemon Z/
    README.md
    mkxp.json
    multiplayer/
    tools/randomizer/
```

Para Pokemon Z, entra en `SebiLink - Pokemon Z` y sigue su README.
