# Icono propio para la app de YouTube que arranca Linux (Y2JB)

Para quien usa el [ps5-y2jb-autoloader](https://github.com/itsPLK/ps5-y2jb-autoloader) de itsPLK desde la app de
YouTube y tiene una segunda app de YouTube que arranca Linux directamente, con un icono propio (por ejemplo el mismo
icono con una franja «LINUX»). El icono se cambia solo y vuelve al del autoloader tras el primer uso. Esta
herramienta lo deja fijo.

## Causa

La app guarda su almacenamiento en `/user/download/<TITLEID>/download0.dat` (p. ej. `PPSA01651`): una imagen UFS2
(FreeBSD) que contiene el autoloader en `cache/splash_screen/aHR0cHM6Ly93d3cueW91dHViZS5jb20vdHY=/`, con su propio
`icon0.png`. En cada arranque, `updateIcon()` del autoloader compara `/user/appmeta/<TITLEID>/icon0.png` con ese
icono y, si son distintos, **sobrescribe el tuyo con el suyo**. Las versiones v0.8/v0.9 comparan el fichero entero
byte a byte; la v1.1.0 solo el tamaño y los primeros 64 bytes.

## Qué hace la herramienta

Cambia, dentro de `download0.dat`, **todas las copias exactas** del icono del autoloader por tu PNG, que mide
**exactamente los mismos bytes** (cambio en el sitio: UFS2 no guarda sumas de los datos y los tamaños de los inodos
siguen siendo válidos). Así el autoloader «actualiza» el icono... al tuyo, y se queda. Probado en una consola real
con FW 4.xx.

| Orden | Qué hace |
|---|---|
| `extract` | busca el icono del autoloader en `download0.dat` y lo guarda como `icon0.png` |
| `make` | crea tu `icon0.png` (mismo tamaño y, para v1.1.0, mismos 64 primeros bytes) y el `icon0.dds` (BC7, 512x512) |
| `patch` | escribe una copia de `download0.dat` con el icono cambiado; no toca el original y lo comprueba al final |
| `install` | todo lo anterior por FTP contra la consola, con copia de seguridad y comprobación |
| `undo` | vuelve a subir la copia de seguridad (y los iconos de antes) |

El icono del autoloader se localiza solo (el PNG de 512x512 con más copias en la imagen); no hay nada fijo. Por
defecto la franja es negra con el texto `LINUX`; con `--text OTRO` cambias el texto y con `--image MIIMAGEN.png`
usas tu propia imagen (se escala a 512x512). Si la imagen no cabe en el tamaño exacto, se reducen colores.

## Requisitos

- Python 3 (macOS, Linux o Windows). `extract`, `patch` y `undo` no necesitan nada más.
- Para generar el icono (`make`, e `install` sin `--icon-dir`): Pillow y etcpak. Si faltan, el script imprime el
  comando exacto; por ejemplo:
  `uv run --no-project --with pillow==11.3.0 --with etcpak python y2jb-icon.py make ...`
  o `pip install pillow etcpak`.
- Para `install`/`undo`: el FTP de la consola (ftpsrv, normalmente puerto 2121) cargado, y la consola en la misma red.

Descarga: `curl -LO https://github.com/fitamix/ps5-bazzite-toolbox/releases/latest/download/y2jb-icon.py`
(o desde la carpeta `utils/` del repositorio).

## Paso a paso (caso normal)

1. Carga ftpsrv en la consola y **cierra la app de YouTube** (la que vas a modificar).
2. Mira el plan sin escribir nada: `python3 y2jb-icon.py install --host 192.168.1.x --dry-run`
3. Hazlo de verdad (con Pillow y etcpak disponibles, ver arriba):
   `python3 y2jb-icon.py install --host 192.168.1.x --tid PPSA01651`
   Cambia `--tid` por el Title ID de tu app de YouTube, y `--port` si tu ftpsrv no usa el 2121.
4. Antes de cada escritura pregunta `(y/N)`; `--yes` no pregunta. El orden es: copia de seguridad de
   `download0.dat` y de los iconos actuales en `./y2jb-icon-work/`, generar el icono, parchear, subir
   `download0.dat`, `icon0.png` e `icon0.dds` (a `/user/appmeta/<TID>/`), y volver a bajarlos para comparar hashes.
5. Abre la app de YouTube. El icono se mantiene.

Con un icono hecho a mano: `--icon-dir CARPETA` (con `icon0.png` e, opcionalmente, `icon0.dds`). El PNG debe medir
lo mismo que el del autoloader. Por separado, sin consola:

```
python3 y2jb-icon.py extract download0.dat -o iconos
python3 y2jb-icon.py make --from iconos/icon0.png --text LINUX -o iconos/linux
python3 y2jb-icon.py patch download0.dat download0-nuevo.dat --icon iconos/linux/icon0.png
```

## Deshacer

```
python3 y2jb-icon.py undo --host 192.168.1.x --tid PPSA01651 --backup y2jb-icon-work/download0-PPSA01651-FECHA.dat
```

Sube la copia de seguridad de `download0.dat` y los iconos que `install` guardó a su lado (`--no-icons` para solo el
`.dat`). Con el autoloader original vuelve su icono.

## Riesgos y límites

- **Guarda la copia de seguridad** (`download0-<TID>-<fecha>.dat`): es lo único que permite volver atrás.
- Solo para el `download0.dat` del autoloader de itsPLK (imagen UFS2 con su icono 512x512 RGB). Si no lo reconoce,
  se niega y no escribe nada. Si ya está parcheado, `patch` dice que no hay nada que cambiar.
- Con la app de YouTube abierta, la consola puede pisar los ficheros: ciérrala antes.
- Una subida cortada deja un fichero a medias: repite `install` o usa `undo`.
- Una versión futura del autoloader que compare de otra forma podría volver a sobrescribir el icono.
- Hecho para uso personal; sin garantía (MIT). Usa tu propia consola y tus propios ficheros.

## Créditos

[itsPLK/ps5-y2jb-autoloader](https://github.com/itsPLK/ps5-y2jb-autoloader) (GPL-3). No se redistribuye ningún fichero
suyo: el icono LINUX se genera a partir de **tu** copia de `download0.dat`.

---

## English

For people who run itsPLK's [ps5-y2jb-autoloader](https://github.com/itsPLK/ps5-y2jb-autoloader) from the YouTube app
and have a second YouTube app that boots Linux directly, with a custom icon (e.g. the same icon with a "LINUX"
banner). The icon reverts to the autoloader's after the first launch. This tool makes it stick.

### Cause

The app's storage is `/user/download/<TITLEID>/download0.dat` (e.g. `PPSA01651`): a UFS2 (FreeBSD) image holding the
autoloader in `cache/splash_screen/aHR0cHM6Ly93d3cueW91dHViZS5jb20vdHY=/`, including its own `icon0.png`. On every
launch the autoloader's `updateIcon()` compares `/user/appmeta/<TITLEID>/icon0.png` with that bundled icon and, if
they differ, **overwrites yours with its own**. v0.8/v0.9 compare the whole file byte by byte; v1.1.0 only the size
and the first 64 bytes.

### What it does

It replaces, inside `download0.dat`, **every exact copy** of the bundled icon with your PNG, which has **exactly the
same byte size** (in-place; UFS2 keeps no data checksums and the inode sizes stay valid). The autoloader then
"updates" the icon... to yours. Verified on real FW 4.xx hardware.

- `extract` finds the bundled icon (the 512x512 PNG with the most copies in the image; nothing hardcoded).
- `make` builds your `icon0.png` (same size and, for v1.1.0, same first 64 bytes) and `icon0.dds` (BC7, 512x512).
  Default: black banner with `LINUX`; `--text` changes it, `--image` uses your own picture. Colors are reduced if the
  image doesn't fit the exact size.
- `patch` writes a patched copy of `download0.dat`; never touches the input, verifies the result.
- `install` does everything over FTP (backup, build, patch, upload, re-download and compare hashes); `undo` uploads
  the backup back.

### Requirements

Python 3 (macOS, Linux, Windows). Pillow and etcpak only to generate the icon (`make`, `install` without
`--icon-dir`); if missing the script prints the exact command, e.g.
`uv run --no-project --with pillow==11.3.0 --with etcpak python y2jb-icon.py make ...` or `pip install pillow etcpak`.
`install`/`undo` need ftpsrv running on the console (usually port 2121).

### Steps

1. Load ftpsrv on the console and **close the YouTube app** you are modifying.
2. Preview: `python3 y2jb-icon.py install --host 192.168.1.x --dry-run`
3. Run: `python3 y2jb-icon.py install --host 192.168.1.x --tid PPSA01651` (your app's Title ID; `--port` if not 2121).
   It asks `(y/N)` before each write (`--yes` skips it). Backups go to `./y2jb-icon-work/`.
4. Open the YouTube app: the icon stays.

Manual route without a console: `extract`, `make`, `patch` as shown in the Spanish section.

### Undo

`python3 y2jb-icon.py undo --host 192.168.1.x --tid PPSA01651 --backup y2jb-icon-work/download0-PPSA01651-DATE.dat`
uploads the backup `download0.dat` and the previous icons saved next to it (`--no-icons` for the `.dat` only).

### Risks

Keep the backup. Only for itsPLK's autoloader `download0.dat` (otherwise it refuses and writes nothing). Close the
YouTube app first. An interrupted upload leaves a partial file: run `install` again or `undo`. A future autoloader
that compares differently could overwrite the icon again. Personal use, no warranty (MIT).

### Credits

[itsPLK/ps5-y2jb-autoloader](https://github.com/itsPLK/ps5-y2jb-autoloader) (GPL-3). None of its files are
redistributed: the LINUX icon is generated from **your own** copy of `download0.dat`.
