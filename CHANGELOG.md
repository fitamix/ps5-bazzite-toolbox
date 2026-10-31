# Cambios

Formato: [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/). Numeración: `MAYOR.MENOR.ARREGLO`
(ver «Versiones de la caja de herramientas» en el [README](README.md)).

## [Sin publicar]

## [1.0.0] - 2026-10-31

Primera versión publicada.

### Diagnóstico
- Revisión completa de un arranque (este o el anterior) con informe sin contraseñas: disco USB, GPU, cuelgues,
  Wi-Fi, OOM, cierres, temperatura, NAS y sesión gráfica.
- Vigilancia del kernel en directo y monitor de CPU, GPU, VRAM, GTT, RAM, swap y temperaturas.

### Pantalla y sesión
- Recuperar la imagen cuando la pantalla se queda en negro, reiniciar la sesión y elegir escritorio o modo juego.

### Ajustes (bloques)
- `locale cmdline wifi updates vram zram fans warmreboot hdmi bt disk brave nas bios media esde portproton atajos`,
  cada uno explicando qué cambia, por qué y cómo deshacerlo, y preguntando antes.

### PortProton y Steam
- Añadir y quitar juegos de Windows (PortProton, accesos directos, Steam y colección «PortProton»), idioma del
  emulador de Steam y paquetes de idioma.

### Sistema
- Actualizar la imagen VivaLaVent/ps5-bazzite-deck desde GitHub con comprobación de SHA-256.
- Versión propia (`--version`), aviso de versión nueva en el menú y autoactualización (opción 18, `--self-update`).

[Sin publicar]: https://github.com/fitamix/ps5-bazzite-toolbox/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/fitamix/ps5-bazzite-toolbox/releases/tag/v1.0.0
