# ps5-bazzite-toolbox

Caja de herramientas para **Linux en la PS5** con la imagen
[VivaLaVent/ps5-bazzite-deck](https://github.com/VivaLaVent/ps5-bazzite-deck) (Bazzite Deck: Steam en modo juego
y escritorio KDE). Es **un solo fichero** que se ejecuta en la consola y sirve para:

- **Diagnosticar** problemas sin cambiar nada, y dejar un informe para pedir ayuda.
- **Recuperar la pantalla o la sesión gráfica** cuando se queda en negro.
- **Poner a punto un sistema recién instalado**: idioma, VRAM, ventilador, NAS, EmuDeck/ES-DE… bloque a bloque,
  explicando cada cambio y preguntando antes. Incluye montar un NAS para las ROMs, BIOS e imágenes de
  EmuDeck/ES-DE.
- **Añadir y quitar juegos de Windows** en PortProton y Steam en un paso, con ajustes por defecto pensados para
  que funcionen el máximo de juegos sin tocar nada.
- **Actualizar la imagen** desde GitHub con comprobación de SHA-256.

Todo está en español. Probado en una PS5 (FW 4.50) con las versiones v1.4 – v1.8 de la imagen, arrancando desde un
disco USB. No es un proyecto oficial de la imagen ni de sus autores.

## Uso rápido

En la PS5 (terminal o SSH):

```sh
curl -LO https://raw.githubusercontent.com/fitamix/ps5-bazzite-toolbox/main/ps5-toolbox.sh
bash ps5-toolbox.sh
```

Sin opciones muestra un menú. Se ejecuta con tu usuario (no como root): pide `sudo` cuando lo necesita.

```
 Diagnóstico (solo mira, no cambia nada)
   1) Revisión completa de este arranque (y guarda el informe)
   2) Revisar el arranque anterior (tras un cuelgue o un apagado forzado)
   3) Vigilar el kernel en directo
   4) Vigilar en directo: CPU, GPU, VRAM, RAM, swap, temperatura y qué gasta más
 Pantalla y sesión gráfica
   5) Ver en qué modo arranca la consola y qué sesión hay ahora
   6) Pantalla en negro: recuperar la imagen (cambia de consola y vuelve; no cierra nada)
   7) Pantalla en negro que no se arregla con el 6: reiniciar la sesión (cierra Steam y lo abierto)
   8) Pasar al escritorio KDE ahora y arrancar siempre en él
   9) Pasar al modo juego ahora y arrancar siempre en él
 PortProton y Steam
  10) Añadir un juego de Windows: probarlo con PortProton, accesos directos, Steam y colección
  11) Quitar un juego: de Steam, de PortProton y del disco (pregunta cada paso)
  12) Sincronizar la colección «PortProton» de Steam
 Utilidades
  13) Ver lo que ocupa cada carpeta
 Ajustes de la consola (cambian el sistema; cada uno explica y pregunta)
  14) Ver qué ajustes están aplicados
  15) Aplicar los ajustes pendientes, uno a uno
  16) Revisar o cambiar ajustes concretos
 Sistema
  17) Actualizar la imagen desde GitHub
```

Lo mismo sin menú:

```sh
bash ps5-toolbox.sh --check [--boot -1]       # diagnóstico de este arranque (o del anterior) + informe
bash ps5-toolbox.sh --watch                   # kernel en directo
bash ps5-toolbox.sh --mem                     # CPU, GPU y memoria en directo
bash ps5-toolbox.sh --screen                  # pantalla en negro: recuperar la imagen
bash ps5-toolbox.sh --session status|restart|desktop|gamemode
bash ps5-toolbox.sh --add-game "/ruta/Juego.exe"
bash ps5-toolbox.sh --remove-game ["/ruta/Juego.exe" | "Nombre"]
bash ps5-toolbox.sh --pp-collection [--dry-run|--yes]
bash ps5-toolbox.sh --space [carpeta]
bash ps5-toolbox.sh --setup                   # ajustes, bloque a bloque
bash ps5-toolbox.sh --setup --status          # solo el estado de cada bloque
bash ps5-toolbox.sh --setup --all             # la respuesta recomendada en todo, sin preguntar
bash ps5-toolbox.sh --setup --only vram,nas   # solo esos bloques (vuelve a preguntar)
bash ps5-toolbox.sh --update [v1.8.4]         # actualizar la imagen
```

## Diagnóstico

Solo lee. Deja el informe en `~/ps5-diag-FECHA.txt` (sin contraseñas) y repasa lo que ha dado problemas en esta
consola:

- **Disco USB:** atascos (`timing out command`), resets, errores de E/S y espacio libre.
- **Gráfica:** reinicios de la GPU, errores de memoria, VRAM disponible.
- **Sistema:** cuelgues del kernel, procesos bloqueados, falta de memoria, programas que se cierran de golpe, si el
  arranque anterior terminó mal.
- **Temperatura y ventilador**, **red** (router, DNS, Wi-Fi, Bluetooth, NAS), **sesión gráfica** y el estado de cada
  bloque de ajustes.

**Vigilar en directo** (opción 4): cada 2 s muestra la carga de CPU (media y el hilo más cargado) y de GPU, VRAM, GTT (RAM que la gráfica toma prestada), RAM y swap, todo
como usado/total, la temperatura de CPU y GPU y los programas que más VRAM usan. La swap de Bazzite es zram (RAM comprimida):
`2.5/4.3 GB (0.8)` son 2,5 GB en la swap que ocupan 0,8 GB de RAM. Al parar (Ctrl+C) resume los picos y dice si
falta VRAM, RAM o las dos, si se llenó la swap y si el límite es la GPU o un hilo de la CPU. Cada medida queda en `~/ps5-mem-FECHA.csv`.

## Pantalla y sesión gráfica

- **Recuperar la imagen** (6): pasar a otra consola virtual y volver hace que la gráfica vuelva a configurar la
  salida HDMI. No cierra nada.
- **Reiniciar la sesión** (7): `systemctl restart sddm` deja vivo el compositor anterior y la pantalla sigue en
  negro. El toolbox cierra primero las sesiones y el compositor, y luego arranca SDDM.
- **Escritorio / modo juego** (8, 9): cambia en qué sesión entra la consola al arrancar y la reinicia ya.

## Ajustes de la consola

Cada bloque explica **qué cambia, por qué y cómo deshacerlo**, y pregunta con una respuesta recomendada. Lo que
depende de cada consola (disco, idioma, NAS…) lo detecta o lo pregunta. Las respuestas quedan en
`~/.config/ps5-bazzite-postinstall.conf`; al repetirlo solo ofrece lo pendiente.

| Bloque | Qué hace | Por qué |
|---|---|---|
| `locale` | Idioma, teclado, zona horaria y NTP | La imagen viene en inglés, teclado US y UTC |
| `cmdline` | `/efi/cmdline.txt`: idioma en el arranque y `usb-storage.quirks` para el disco USB de arranque | Algunos discos USB con UAS dan resets y errores de E/S |
| `wifi` | Apaga o vuelve a encender el Wi-Fi según la versión de la imagen | El driver del IW620 se colgaba con el Wi-Fi activo antes de la v1.5.0 |
| `updates` | Bloquea las actualizaciones automáticas de kernel, Mesa, firmware y gamescope | Esos paquetes llevan parches de la PS5: actualizarlos rompe la imagen |
| `vram` | VRAM reservada para la gráfica (`/efi/vram.txt`, de 512 MB a 8 GB) | Con 512 MB, los juegos DX12/UE5 se caen con *Not enough memory* |
| `zram` | Swap zram del tamaño de toda la RAM (Bazzite pone la mitad), con un fichero aparte en `/etc/systemd/zram-generator.conf.d/` | Juegos grandes la llenan y, sin swap libre, el sistema los cierra |
| `fans` | Control del ventilador y temperatura objetivo (60–85 °C) | El objetivo de fábrica (80 °C) es silencioso pero caliente |
| `warmreboot` | Reinicio en caliente (sin pasar por el cargador) | Comodidad; experimental |
| `hdmi` | Recupera la imagen tras un reinicio en caliente | A veces el HDMI sale en negro |
| `bt` | Recarga `btusb` si el Bluetooth arranca sin adaptador | El IW620 a veces no responde a su primer reinicio |
| `disk` | Desactiva la consulta SMART de KDE | Dejaba algunos discos USB 60 s sin responder |
| `brave` | Brave sin la Cartera de KDE | Con inicio automático, Brave pide su contraseña cada vez |
| `nas` | Monta un NAS por SMB y enlaza las ROMs de EmuDeck | ROMs compartidas con otros equipos (p. ej. una Steam Deck) |
| `bios`, `media` | BIOS e imágenes de ES-DE desde el NAS | Una sola copia para todos los equipos |
| `esde` | Arregla el `es_systems.xml` que deja EmuDeck (rutas de Windows, Citra) | Sin esto 3DS falla con *citra_libretro.dll* |
| `portproton` | Ajustes globales de PortProton: FSYNC/ESYNC y trazado de rayos para todos los juegos, salvo los que su `.ppdb` cambie | PortProton los trae apagados; el Proton de Steam lleva la sincronización rápida, y hay juegos que exigen trazado de rayos |
| `atajos` | Botón derecho de Dolphin (añadir y quitar juego, espacio por carpeta), comando `espacio`, acceso «Colección PortProton» | Tenerlo todo a mano tras instalar |

## PortProton y Steam

**Añadir un juego de Windows** (opción 10, `--add-game`, o en Dolphin botón derecho sobre el `.exe` →
«Añadir a PortProton y Steam» tras el bloque `atajos`). Pregunta en cada paso:

1. Abre el juego con PortProton para probarlo; PortProton guarda sus ajustes en `<exe>.ppdb`.
   - **Idioma:** si el juego lleva un emulador de Steam (`steam_emu.ini`, `steam_settings/…`, `SteamConfig.ini`,
     `cream_api.ini`) con otro idioma que el del sistema, ofrece cambiarlo: muchos juegos solo muestran el idioma que
     les dice "Steam" y no tienen selector propio. Si trae una carpeta de paquetes de idioma, ofrece copiar el tuyo.
2. Crea el acceso directo como lo hace PortProton: en su lista de juegos y en el escritorio.
3. Lo añade a Steam como juego no-Steam (con Steam cerrado: si no, Steam borra la entrada al cerrarse). Hace copia
   de `shortcuts.vdf` y lo reescribe idéntico salvo la entrada nueva.
4. Lo mete en la colección «PortProton» de Steam.

**Quitar un juego** (opción 11, `--remove-game`, o botón derecho sobre el `.exe` → «Quitar de PortProton y Steam»).
Sin argumento lista los juegos de PortProton. Pregunta por separado: quitarlo de Steam (con copia de `shortcuts.vdf`
y sus carátulas), borrar sus accesos directos y su script, y borrar su carpeta del disco, que muestra con su tamaño y
pide escribir su nombre para confirmar. Las partidas guardadas en el prefijo de PortProton se conservan.

**Ajustes para todos los juegos** (bloque `portproton`):

- **Sincronización rápida (FSYNC/ESYNC):** PortProton la trae apagada; el Proton de Steam la lleva encendida. Menos
  tirones en juegos que cargan la CPU.
- **Trazado de rayos:** el driver de la PS5 en Linux (RADV) lo soporta, pero PortProton lo desactiva en AMD y los
  juegos que lo exigen no arrancan. Si un juego lo enciende solo y va lento, bájalo en sus opciones gráficas o
  desactívalo solo para él con `export PW_USE_RAY_TRACING="0"` en su `.ppdb`.

PortProton lee sus ajustes globales (`data/user.conf`) después de los de cada juego, así que el bloque solo pone el
valor cuando el `.ppdb` del juego no dice nada.

## Actualizar la imagen

Lista las versiones publicadas (estables, preliminares y «rápidas» que solo cambian el kernel), muestra sus
novedades, comprueba el espacio, descarga, verifica el SHA-256 y ejecuta el `update.sh` del autor. Después recuerda
**apagar** y arrancar con el cargador, no reiniciar.

## Cosas que se hacen a mano

- Cambiar la contraseña (`passwd`): la de serie es `ps5` y SSH está abierto en la red.
- Steam: zona horaria e idioma propios, rango RGB **Full** en el modo juego y en el escritorio.
- EmuDeck: instalador **SteamOS**, dispositivo **Steam Machine**, ubicación **Internal**.
- DualSense: emparejarlo por Bluetooth en un perfil propio (PS + Cuadrado).
- Para un informe de fallo al autor de la imagen: su `ps5-report`.

## Licencia

[MIT](LICENSE).
