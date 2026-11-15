#!/usr/bin/env python3
"""Custom icon for a YouTube app that boots Linux (itsPLK's ps5-y2jb-autoloader), one that survives every launch.

Why: the autoloader's download0.dat (/user/download/<TITLEID>/, a UFS2 image) carries its own icon0.png. On every
launch its updateIcon() compares /user/appmeta/<TITLEID>/icon0.png with that bundled icon and, if they differ,
overwrites yours with its own (v0.8/v0.9: whole file byte by byte; v1.1.0: only the size and the first 64 bytes).
So a custom icon (say, the same one with a "LINUX" banner) disappears after the first launch.

What it does: replaces, inside download0.dat, every exact copy of the bundled icon with your PNG, which has EXACTLY
the same byte size (in-place byte replacement: UFS2 keeps no checksums of file data and the sizes in the inodes stay
valid). The autoloader then "updates" the console's icon... to yours. `make` builds that PNG (same size and, for
v1.1.0, the same first 64 bytes) and the icon0.dds (BC7) that the console shows. `install` does everything over FTP.

Needs Python 3. Pillow + etcpak only to generate the icon (`make`, and `install` without --icon-dir):
  uv run --no-project --with pillow==11.3.0 --with etcpak python y2jb-icon.py make ...   (or: pip install pillow etcpak)

Usage:
  python3 y2jb-icon.py extract download0.dat [-o DIR]              the bundled icon -> DIR/icon0.png
  python3 y2jb-icon.py make --from icon0.png [--text LINUX | --image MY.png] [--dds-template o.dds] -o DIR
  python3 y2jb-icon.py patch download0.dat OUT.dat --icon NEW.png [--original ORIG.png]
  python3 y2jb-icon.py install --host 192.168.1.x [--port 2121] [--tid PPSA01651] [--icon-dir DIR] [--dry-run]
  python3 y2jb-icon.py undo --host 192.168.1.x --backup download0-...dat [--tid PPSA01651]
Nothing on the console is written without asking (unless --yes). Close the YouTube app first.
License: MIT. Not affiliated with itsPLK; none of the autoloader's files are redistributed.
"""
import argparse
import ftplib
import hashlib
import mmap
import os
import posixpath
import re
import shlex
import shutil
import struct
import sys
import time
import zlib

VERSION = "1.0.0"
PNG_SIG = b"\x89PNG\r\n\x1a\n"
ICON_SIZE = 512
UFS2_MAGIC = b"\x19\x01\x54\x19"          # at 64 KiB (superblock) + 0x55c
UFS2_MAGIC_OFF = 65536 + 0x55C


def die(msg):
    sys.exit("ERROR: " + msg)


def sha(b):
    return hashlib.sha256(b).hexdigest()


def sha_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for blk in iter(lambda: f.read(1 << 20), b""):
            h.update(blk)
    return h.hexdigest()


def ask(question, yes):
    """y/N confirmation; --yes answers for you. No answer (no terminal) means no."""
    if yes:
        return True
    try:
        return input(f"{question} (y/N) ").strip().lower() in ("y", "yes", "s", "si", "sí")
    except EOFError:
        return False


# ----------------------------------------------------------------------------------------------- image / PNG scan

def is_ufs2(path):
    with open(path, "rb") as f:
        f.seek(UFS2_MAGIC_OFF)
        return f.read(4) == UFS2_MAGIC


def open_map(path):
    f = open(path, "rb")
    try:
        return f, mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ)
    except ValueError:                       # empty file
        f.close()
        die(f"{path} está vacío / is empty")


def find_all(mm, needle):
    """Offsets of every (non-overlapping) exact copy of needle."""
    out, i = [], 0
    while (i := mm.find(needle, i)) >= 0:
        out.append(i)
        i += len(needle)
    return out


def png_at(mm, pos):
    """Walk the PNG chunks starting at pos; return (end, width, height) or None if it isn't a complete PNG."""
    size, p, first = len(mm), pos + 8, True
    while p + 12 <= size:
        n, = struct.unpack(">I", mm[p:p + 4])
        t = mm[p + 4:p + 8]
        if n > (16 << 20) or p + 12 + n > size:
            return None
        if first:
            if t != b"IHDR" or n != 13:
                return None
            w, h = struct.unpack(">II", mm[p + 8:p + 16])
            first = False
        p += 12 + n
        if t == b"IEND":
            return p, w, h
    return None


def detect_icons(path):
    """All 512x512 PNGs in the image, grouped by content: list of dicts sorted by number of copies (desc)."""
    f, mm = open_map(path)
    try:
        groups = {}
        for pos in find_all(mm, PNG_SIG):
            r = png_at(mm, pos)
            if r and r[1] == ICON_SIZE and r[2] == ICON_SIZE:
                data = bytes(mm[pos:r[0]])
                g = groups.setdefault(sha(data), {"sha": sha(data), "data": data, "offsets": []})
                g["offsets"].append(pos)
        return sorted(groups.values(), key=lambda g: (-len(g["offsets"]), g["offsets"][0]))
    finally:
        mm.close()
        f.close()


def is_rgb8(data):
    """Opaque 8-bit RGB PNG (what an icon0.png is; the Payload Manager's icon.png in the same image is RGBA)."""
    return data[24:26] == b"\x08\x02"


def pick_icon(path, pick=None, hint=None):
    """The autoloader's bundled icon: the 512x512 PNG with most copies (ties: the opaque RGB one, as icon0.png is;
    the console's current icon0.png, if given as hint, also wins a tie). Still ambiguous -> error with the list."""
    if not is_ufs2(path):
        die(f"{path} no parece una imagen UFS2 (download0.dat de Y2JB) / doesn't look like a UFS2 image")
    cands = detect_icons(path)
    if not cands:
        die("no encuentro ningún PNG de 512x512 en la imagen: ¿no es el autoloader de itsPLK? / no 512x512 PNG found")
    if pick:
        m = [g for g in cands if g["sha"].startswith(pick.lower())]
        if len(m) != 1:
            die(f"--pick {pick}: {len(m)} coincidencias / matches")
        return m[0]
    top = [g for g in cands if len(g["offsets"]) == len(cands[0]["offsets"])]
    if len(top) > 1 and hint:
        top = [g for g in top if g["sha"] == hint] or top
    if len(top) > 1:
        top = [g for g in top if is_rgb8(g["data"])] or top
    cands = top + [g for g in cands if g not in top]
    if len(top) > 1:
        lines = "\n".join(f"  {g['sha'][:12]}  {len(g['data'])} B  {len(g['offsets'])} copia(s), 1ª en {g['offsets'][0]:#x}"
                          for g in cands)
        die("hay varios iconos candidatos con las mismas copias; elige uno con --pick HASH (extract) o "
            f"--original FICHERO (patch) / ambiguous:\n{lines}")
    return cands[0]


# --------------------------------------------------------------------------------------------------------- extract

def cmd_extract(a):
    g = pick_icon(a.dat, a.pick)
    others = len(detect_icons(a.dat)) - 1
    os.makedirs(a.output, exist_ok=True)
    out = os.path.join(a.output, "icon0.png")
    with open(out, "wb") as f:
        f.write(g["data"])
    print(f"Icono del autoloader: {len(g['data'])} bytes, sha256 {g['sha'][:12]}…, {len(g['offsets'])} copia(s) en "
          + ", ".join(f"{o:#x}" for o in g["offsets"]))
    if others:
        print(f"(otros {others} PNG de 512x512 distintos ignorados / other 512x512 PNGs ignored)")
    print(f"Guardado {out}")


# ------------------------------------------------------------------------------------------------------ patch

def patch_image(src, dst, old, new):
    """Copy src to dst replacing every exact copy of old with new (same size). Returns the offsets. Verifies."""
    if len(old) != len(new):
        die(f"los iconos no miden lo mismo ({len(old)} y {len(new)} bytes): así no se puede cambiar en la imagen "
            "/ sizes differ")
    if not is_ufs2(src):
        die(f"{src} no parece una imagen UFS2 / not a UFS2 image")
    if os.path.abspath(src) == os.path.abspath(dst):
        die("la salida no puede ser la entrada: no modifico el original / output must differ from input")
    f, mm = open_map(src)
    try:
        hits = find_all(mm, old)
        already = len(find_all(mm, new)) if old != new else 0
    finally:
        mm.close()
        f.close()
    print(f"Icono original ({sha(old)[:12]}…): {len(hits)} copia(s); icono nuevo ({sha(new)[:12]}…) ya presente: {already}")
    if old == new:
        die("el icono nuevo es idéntico al original: nada que cambiar (¿ya parcheado?) / identical, nothing to do")
    if not hits:
        die("no hay nada que cambiar (ya parcheado)" if already else
            "no encuentro el icono original en la imagen: ¿otra versión del autoloader? / original icon not found")
    shutil.copyfile(src, dst)
    try:
        with open(dst, "r+b") as o:
            for p in hits:
                o.seek(p)
                o.write(new)
                print(f"  cambiado en el byte {p:#x}")
        f, mm = open_map(dst)
        try:
            left, now = len(find_all(mm, old)), len(find_all(mm, new))
        finally:
            mm.close()
            f.close()
        if left or now != already + len(hits) or os.path.getsize(dst) != os.path.getsize(src):
            raise RuntimeError("la comprobación final no cuadra / final check failed")
    except Exception as e:
        if os.path.exists(dst):
            os.remove(dst)
        die(f"{e}; no guardo nada / nothing saved")
    print(f"Guardado {dst} ({os.path.getsize(dst)} bytes, igual que la entrada). Comprobado: 0 copias viejas, {now} nuevas.")
    return hits


def cmd_patch(a):
    if a.original:
        old = open(a.original, "rb").read()
    else:
        old = pick_icon(a.dat)["data"]
    new = open(a.icon, "rb").read()
    patch_image(a.dat, a.out, old, new)


# --------------------------------------------------------------------------------------------------- make (icons)

def need_modules():
    """Import Pillow and etcpak lazily; if missing, say exactly how to run again with them."""
    try:
        from PIL import Image, ImageDraw, ImageFont
        import etcpak
        return Image, ImageDraw, ImageFont, etcpak
    except ImportError as e:
        cmd = "python y2jb-icon.py " + " ".join(shlex.quote(x) for x in sys.argv[1:])
        die(f"falta un módulo para generar el icono ({e.name}). Vuelve a lanzarlo así / missing module, run it again as:\n"
            f"  uv run --no-project --with pillow==11.3.0 --with etcpak {cmd}\n"
            "o instala con / or install with:  pip install pillow etcpak")


def png_chunks(data):
    pos, ch = 8, []
    while pos < len(data):
        n, = struct.unpack(">I", data[pos:pos + 4])
        ch.append((data[pos + 4:pos + 8], pos, n))
        pos += 12 + n
    return ch


def fit_png(template, im):
    """PNG of im with exactly len(template) bytes and the template's header (so its first 64 bytes match), a single
    IDAT: deflate at level 9, then the rest as stored blocks sized to hit the exact length. None if it doesn't fit."""
    ch = png_chunks(template)
    idats = [c for c in ch if c[0] == b"IDAT"]
    if template[:8] != PNG_SIG or len(idats) != 1:
        die("el icono de plantilla debe tener un único IDAT / template PNG must have a single IDAT chunk")
    w, h, depth, ctype = struct.unpack(">IIBB", template[16:26])
    if (depth, ctype) != (8, 2):
        die("la plantilla debe ser RGB de 8 bits / template must be 8-bit RGB")
    if im.size != (w, h):
        die(f"la imagen mide {im.size}, debe ser {(w, h)}")
    _, ipos, idat_len = idats[0]
    zhdr = template[ipos + 8:ipos + 10]
    raw_rgb = im.convert("RGB").tobytes()
    raw = b"".join(b"\x00" + raw_rgb[y * w * 3:(y + 1) * w * 3] for y in range(h))

    def build(split):
        c = zlib.compressobj(9, zlib.DEFLATED, -15, 9)
        body = c.compress(raw[:split]) + c.flush(zlib.Z_FULL_FLUSH)       # byte-aligned, not final
        rest = raw[split:]
        while True:
            blk, rest = rest[:65535], rest[65535:]
            final = 0 if rest else 1
            body += bytes([final]) + struct.pack("<HH", len(blk), 0xFFFF ^ len(blk)) + blk
            if final:
                break
        return zhdr + body + struct.pack(">I", zlib.adler32(raw))

    if len(build(len(raw) - 1)) > idat_len:
        return None
    lo, hi = 0, len(raw)
    while lo < hi:                           # smallest split whose result fits (size falls as split grows)
        mid = (lo + hi) // 2
        if len(build(mid)) > idat_len:
            lo = mid + 1
        else:
            hi = mid
    data = None
    for d in sorted(range(-60, 6000), key=abs):
        s = lo + d
        if 0 <= s < len(raw):
            b = build(s)
            if len(b) == idat_len:
                data = b
                break
    if data is None:
        return None
    png = (template[:ipos] + struct.pack(">I", idat_len) + b"IDAT" + data
           + struct.pack(">I", zlib.crc32(b"IDAT" + data)) + template[ipos + 12 + idat_len:])
    assert zlib.decompress(data) == raw and len(png) == len(template) and png[:64] == template[:64]
    return png


def banner(Image, ImageDraw, ImageFont, im, text):
    """Black band with white text (and a thin yellow edge) over the bottom 24% of the icon."""
    im = im.convert("RGB")
    W, H = im.size
    d = ImageDraw.Draw(im)
    band_h = int(H * 0.24)
    y0 = H - band_h
    d.rectangle([0, y0, W, H], fill=(0, 0, 0))
    d.rectangle([0, y0, W, y0 + 8], fill=(255, 196, 0))
    size = int(band_h * 0.62)
    font = None
    for p in ("/System/Library/Fonts/Supplemental/Arial Black.ttf", "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
              "/Library/Fonts/Arial Bold.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
              "/usr/share/fonts/dejavu/DejaVuSans-Bold.ttf", "C:\\Windows\\Fonts\\arialbd.ttf",
              "DejaVuSans-Bold.ttf", "arialbd.ttf", "Arial Bold.ttf"):
        try:
            font = ImageFont.truetype(p, size)
            break
        except OSError:
            pass
    if font is None:
        try:
            font = ImageFont.load_default(size)
        except TypeError:
            font = ImageFont.load_default()
    # shrink the text if it is wider than the icon
    while True:
        bb = d.textbbox((0, 0), text, font=font)
        if bb[2] - bb[0] <= W - 40 or not hasattr(font, "size") or font.size <= 12:
            break
        font = font.font_variant(size=font.size - 4)
    tw, th = bb[2] - bb[0], bb[3] - bb[1]
    d.text(((W - tw) / 2 - bb[0], y0 + 8 + (band_h - 8 - th) / 2 - bb[1]), text, font=font, fill=(255, 255, 255))
    return im


def dds_header():
    """148 bytes: 'DDS ' + header + DX10 header, BC7_UNORM (DXGI 98), 512x512, 1 mip (same as the console's icon0.dds)."""
    px = struct.pack("<II4s5I", 32, 4, b"DX10", 0, 0, 0, 0, 0)
    hdr = struct.pack("<7I44s", 124, 0x000A1007, ICON_SIZE, ICON_SIZE, ICON_SIZE * ICON_SIZE, 0, 1, b"\0" * 44)
    return b"DDS " + hdr + px + struct.pack("<5I", 0x1000, 0, 0, 0, 0) + struct.pack("<5I", 98, 3, 0, 1, 0)


def make_icons(bundled, text="LINUX", image=None, dds_template=None):
    """Return (png_bytes, dds_bytes): custom icon with the bundled one's exact size, plus its BC7 .dds."""
    Image, ImageDraw, ImageFont, etcpak = need_modules()
    import io
    base = Image.open(io.BytesIO(bundled)).convert("RGB")
    if image:
        im = Image.open(image).convert("RGB")
        if im.size != base.size:
            print(f"  la imagen mide {im.size}: la escalo a {base.size} / resizing")
            im = im.resize(base.size, Image.LANCZOS)
    else:
        im = banner(Image, ImageDraw, ImageFont, base, text)
    png = None
    for colors in (None, 256, 128, 64, 32, 16):
        cand = im if colors is None else im.quantize(colors=colors, method=Image.Quantize.MEDIANCUT).convert("RGB")
        png = fit_png(bundled, cand)
        if png:
            if colors:
                print(f"  la imagen no cabía: reducida a {colors} colores / reduced to {colors} colors")
            im = cand
            break
    if not png:
        die(f"no consigo que la imagen ocupe exactamente {len(bundled)} bytes ni reduciendo colores: "
            "usa una imagen más simple / can't fit the image in the exact size, use a simpler one")
    w, h = im.size
    if (w, h) != (ICON_SIZE, ICON_SIZE):
        die("solo se admiten iconos de 512x512")
    hdr = dds_header()
    if dds_template:
        t = open(dds_template, "rb").read()[:148]
        if len(t) != 148 or t[:4] != b"DDS ":
            die(f"{dds_template} no es un .dds con cabecera DX10 de 148 bytes / not a 148-byte DX10 .dds header")
        hdr = t
    data = etcpak.compress_bc7(im.convert("RGBA").tobytes(), w, h)
    if len(data) != w * h:
        die("tamaño BC7 inesperado / unexpected BC7 size")
    return png, hdr + data


def cmd_make(a):
    bundled = open(a.src, "rb").read()
    print(f"Icono base: {len(bundled)} bytes. Generando… / building…")
    png, dds = make_icons(bundled, a.text, a.image, a.dds_template)
    os.makedirs(a.output, exist_ok=True)
    for name, data in (("icon0.png", png), ("icon0.dds", dds)):
        with open(os.path.join(a.output, name), "wb") as f:
            f.write(data)
    print(f"icon0.png: {len(png)} bytes (igual que el original: {len(png) == len(bundled)}; "
          f"primeros 64 bytes iguales: {png[:64] == bundled[:64]})")
    print(f"icon0.dds: {len(dds)} bytes (BC7)")
    print(f"Guardados en {a.output}")


# ------------------------------------------------------------------------------------------------------- FTP

def ftp_connect(host, port):
    ftp = ftplib.FTP()
    ftp.connect(host, port, timeout=60)
    ftp.login()
    ftp.set_pasv(True)
    ftp.voidcmd("TYPE I")
    return ftp


def ftp_get(ftp, remote, local, quiet=False):
    """Download; returns False if the file doesn't exist on the console."""
    total, done, last = 0, [0], [-1]
    try:
        total = ftp.size(remote) or 0
    except ftplib.all_errors:
        pass
    try:
        with open(local, "wb") as f:
            def cb(blk):
                f.write(blk)
                done[0] += len(blk)
                if total and not quiet and done[0] * 10 // total != last[0]:
                    last[0] = done[0] * 10 // total
                    print(f"    {last[0] * 10}%", end="\r", flush=True)
            ftp.retrbinary("RETR " + remote, cb, 1 << 20)
    except ftplib.error_perm:
        if os.path.exists(local):
            os.remove(local)
        return False
    return True


def ftp_put(ftp, local, remote):
    with open(local, "rb") as f:
        ftp.storbinary("STOR " + remote, f, 1 << 20)


def check_remote(ftp, remote, local, tmp):
    """Re-download remote and compare its hash with local's."""
    if not ftp_get(ftp, remote, tmp, quiet=True):
        return False
    ok = sha_file(tmp) == sha_file(local)
    os.remove(tmp)
    return ok


def paths(tid):
    return (f"/user/download/{tid}/download0.dat", f"/user/appmeta/{tid}/icon0.png", f"/user/appmeta/{tid}/icon0.dds")


def check_tid(tid):
    if not re.fullmatch(r"[A-Z]{4}\d{5}", tid):
        die(f"--tid {tid!r} no parece un Title ID (ej. PPSA01651)")


CLOSE_APP = "Cierra la app de YouTube en la consola antes de seguir (si no, puede pisar los ficheros). / Close the YouTube app first."


def cmd_install(a):
    check_tid(a.tid)
    dat_r, png_r, dds_r = paths(a.tid)
    stamp = time.strftime("%Y%m%d-%H%M%S")
    work = a.workdir
    bak = os.path.join(work, f"download0-{a.tid}-{stamp}.dat")
    plan = [
        f"1. Copia de seguridad de {dat_r} (y de los iconos actuales) en {work}/",
        "2. " + (f"Usar los iconos de {a.icon_dir}" if a.icon_dir else
                 f"Sacar el icono del autoloader y generar icon0.png/icon0.dds (texto {a.text!r})" if not a.image else
                 f"Sacar el icono del autoloader y generar icon0.png/icon0.dds desde {a.image}"),
        "3. Parchear download0.dat (cada copia del icono original -> el nuevo, mismo tamaño)",
        f"4. Subir download0.dat a {dat_r}, y los iconos a /user/appmeta/{a.tid}/",
        "5. Volver a bajar y comparar hashes",
    ]
    print(f"Consola {a.host}:{a.port}, app {a.tid}\n" + "\n".join(plan) + "\n" + CLOSE_APP)
    if a.dry_run:
        print("\n--dry-run: no se ha conectado ni escrito nada.")
        return
    if a.icon_dir and not os.path.isfile(os.path.join(a.icon_dir, "icon0.png")):
        die(f"no hay {os.path.join(a.icon_dir, 'icon0.png')}")
    os.makedirs(work, exist_ok=True)
    try:
        ftp = ftp_connect(a.host, a.port)
    except OSError as e:
        die(f"no puedo conectar con {a.host}:{a.port} ({e}). ¿Está ftpsrv cargado en la consola? / is ftpsrv running?")
    try:
        print(f"\n[1/5] Bajando {dat_r} (puede tardar un rato)…")
        if not ftp_get(ftp, dat_r, bak):
            die(f"{dat_r} no existe en la consola: ¿es el Title ID correcto?")
        print(f"      copia de seguridad: {bak}  (sha256 {sha_file(bak)[:12]}…)")
        old_png = os.path.join(work, f"icon0-{a.tid}-{stamp}.png")
        old_dds = os.path.join(work, f"icon0-{a.tid}-{stamp}.dds")
        has_png, has_dds = ftp_get(ftp, png_r, old_png, True), ftp_get(ftp, dds_r, old_dds, True)
        print("      iconos actuales guardados" if has_png or has_dds else "      (no había iconos en appmeta)")

        print("[2/5] Icono…")
        bundled = pick_icon(bak, hint=sha_file(old_png) if has_png else None)
        print(f"      icono del autoloader: {len(bundled['data'])} B, {len(bundled['offsets'])} copia(s)")
        if a.icon_dir:
            new_png = open(os.path.join(a.icon_dir, "icon0.png"), "rb").read()
            dp = os.path.join(a.icon_dir, "icon0.dds")
            new_dds = open(dp, "rb").read() if os.path.isfile(dp) else None
        else:
            tmpl = old_dds if has_dds else None
            new_png, new_dds = make_icons(bundled["data"], a.text, a.image, tmpl)
            gen = os.path.join(work, f"icons-{a.tid}-{stamp}")
            os.makedirs(gen)
            open(os.path.join(gen, "icon0.png"), "wb").write(new_png)
            open(os.path.join(gen, "icon0.dds"), "wb").write(new_dds)
            print(f"      generados en {gen}")

        print("[3/5] Parcheando…")
        patched = os.path.join(work, f"download0-{a.tid}-{stamp}.patched.dat")
        new_path = os.path.join(work, f"icon0-{a.tid}-{stamp}.new.png")
        open(new_path, "wb").write(new_png)
        patch_image(bak, patched, bundled["data"], new_png)

        print(f"[4/5] Subiendo. {CLOSE_APP}")
        uploads = [(patched, dat_r)]
        uploads.append((new_path, png_r))
        if new_dds:
            dd = os.path.join(work, f"icon0-{a.tid}-{stamp}.new.dds")
            open(dd, "wb").write(new_dds)
            uploads.append((dd, dds_r))
        done = []
        for local, remote in uploads:
            if not ask(f"¿Subir {os.path.basename(local)} -> {remote}?", a.yes):
                print("Cancelado." + (" Lo ya subido se puede deshacer con `undo`." if done else " No se ha escrito nada."))
                sys.exit(1)
            ftp_put(ftp, local, remote)
            done.append((local, remote))
            print(f"      subido {remote}")

        print("[5/5] Comprobando (bajando de nuevo)…")
        bad = [r for l, r in done if not check_remote(ftp, r, l, os.path.join(work, "verify.tmp"))]
        if bad:
            die(f"NO coinciden: {', '.join(bad)}. Restaura con: python3 y2jb-icon.py undo --host {a.host} --backup {bak}")
        print("Todo coincide.")
    except ftplib.all_errors as e:
        die(f"error de FTP: {e}")
    finally:
        try:
            ftp.close()
        except Exception:
            pass
    print(f"\nListo. Abre la app de YouTube. Para deshacer:\n  python3 y2jb-icon.py undo --host {a.host} --port {a.port} "
          f"--tid {a.tid} --backup {shlex.quote(bak)}")


def cmd_undo(a):
    check_tid(a.tid)
    if not os.path.isfile(a.backup):
        die(f"no existe {a.backup}")
    dat_r, png_r, dds_r = paths(a.tid)
    ups = [(a.backup, dat_r)]
    d, n = os.path.split(a.backup)
    base = os.path.join(d, re.sub(r"\.dat$", "", re.sub(r"^download0-", "icon0-", n)))
    png = a.png_backup or (base + ".png" if not a.no_icons else None)
    dds = a.dds_backup or (base + ".dds" if not a.no_icons else None)
    for p, r in ((png, png_r), (dds, dds_r)):
        if p and os.path.isfile(p):
            ups.append((p, r))
    print(f"Consola {a.host}:{a.port}. Se restaurará:\n" + "\n".join(f"  {l} -> {r}" for l, r in ups) + "\n" + CLOSE_APP)
    if a.dry_run:
        print("--dry-run: no se ha escrito nada.")
        return
    if not is_ufs2(a.backup):
        die("la copia de seguridad no parece una imagen UFS2 / backup isn't a UFS2 image")
    try:
        ftp = ftp_connect(a.host, a.port)
    except OSError as e:
        die(f"no puedo conectar con {a.host}:{a.port} ({e})")
    try:
        for local, remote in ups:
            if not ask(f"¿Subir {os.path.basename(local)} -> {remote}?", a.yes):
                print("Cancelado.")
                sys.exit(1)
            ftp_put(ftp, local, remote)
            ok = check_remote(ftp, remote, local, a.backup + ".verify.tmp")
            print(f"  {remote}: {'restaurado y comprobado' if ok else 'ERROR: no coincide'}")
            if not ok:
                sys.exit(1)
    except ftplib.all_errors as e:
        die(f"error de FTP: {e}")
    finally:
        ftp.close()
    print("Listo.")


# ------------------------------------------------------------------------------------------------------- main

def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0], formatter_class=argparse.RawTextHelpFormatter)
    ap.add_argument("--version", action="version", version="y2jb-icon " + VERSION)
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("extract", help="saca el icono del autoloader de download0.dat")
    p.add_argument("dat")
    p.add_argument("-o", "--output", default=".", help="carpeta de salida (por defecto .)")
    p.add_argument("--pick", help="prefijo del sha256 si hay varios candidatos")
    p.set_defaults(fn=cmd_extract)

    p = sub.add_parser("make", help="genera icon0.png (mismo tamaño) e icon0.dds (necesita pillow + etcpak)")
    p.add_argument("--from", dest="src", required=True, metavar="ICON0.png", help="el icono del autoloader (de `extract`)")
    g = p.add_mutually_exclusive_group()
    g.add_argument("--text", default="LINUX", help="texto de la franja inferior (por defecto LINUX)")
    g.add_argument("--image", help="usa tu propia imagen en vez de la franja")
    p.add_argument("--dds-template", help="icon0.dds original, para copiar su cabecera (opcional)")
    p.add_argument("-o", "--output", required=True, help="carpeta de salida")
    p.set_defaults(fn=cmd_make)

    p = sub.add_parser("patch", help="cambia el icono dentro de download0.dat (no toca el original)")
    p.add_argument("dat")
    p.add_argument("out")
    p.add_argument("--icon", required=True, help="PNG nuevo, del mismo tamaño en bytes")
    p.add_argument("--original", help="PNG a sustituir (por defecto se detecta)")
    p.set_defaults(fn=cmd_patch)

    p = sub.add_parser("install", help="todo por FTP contra ftpsrv de la consola")
    p.add_argument("--host", required=True, help="IP de la consola, ej. 192.168.1.x")
    p.add_argument("--port", type=int, default=2121)
    p.add_argument("--tid", default="PPSA01651", help="Title ID de la app de YouTube (por defecto PPSA01651)")
    p.add_argument("--icon-dir", help="carpeta con icon0.png (e icon0.dds) ya hechos, en vez de generarlos")
    g = p.add_mutually_exclusive_group()
    g.add_argument("--text", default="LINUX")
    g.add_argument("--image")
    p.add_argument("--workdir", default="y2jb-icon-work", help="dónde guardar copias y ficheros intermedios")
    p.add_argument("--yes", action="store_true", help="no preguntar antes de escribir")
    p.add_argument("--dry-run", action="store_true", help="enseña el plan sin conectar ni escribir")
    p.set_defaults(fn=cmd_install)

    p = sub.add_parser("undo", help="vuelve a subir la copia de seguridad (y los iconos de antes)")
    p.add_argument("--host", required=True)
    p.add_argument("--port", type=int, default=2121)
    p.add_argument("--tid", default="PPSA01651")
    p.add_argument("--backup", required=True, help="download0-<TID>-<fecha>.dat guardado por install")
    p.add_argument("--png-backup", help="icon0.png de antes (por defecto el que guardó install junto a la copia)")
    p.add_argument("--dds-backup", help="icon0.dds de antes (idem)")
    p.add_argument("--no-icons", action="store_true", help="restaurar solo download0.dat")
    p.add_argument("--yes", action="store_true")
    p.add_argument("--dry-run", action="store_true")
    p.set_defaults(fn=cmd_undo)

    a = ap.parse_args()
    try:
        a.fn(a)
    except KeyboardInterrupt:
        die("interrumpido / interrupted")


if __name__ == "__main__":
    main()
