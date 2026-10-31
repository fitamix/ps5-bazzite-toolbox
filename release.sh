#!/bin/bash
# Publish a new version of ps5-bazzite-toolbox.sh on GitHub (for the maintainer; runs on the computer with the repo).
#
#   ./release.sh 1.1.0
#
# Before running it:
#   1. Set TOOLBOX_VERSION=1.1.0 at the top of ps5-bazzite-toolbox.sh.
#   2. In CHANGELOG.md, rename "## [Sin publicar]" to "## [1.1.0] - YYYY-MM-DD", add a new empty
#      "## [Sin publicar]" above it and update the links at the bottom.
#   3. Commit everything.
# It then checks all that, tags v1.1.0, pushes, and creates the GitHub release with ps5-bazzite-toolbox.sh, its .sha256
# (what the toolbox's self-update downloads) and the CHANGELOG section as notes. Asks before anything public.
# Undo (right after): gh release delete v1.1.0 --cleanup-tag   (the commits stay pushed)
set -euo pipefail

VER=${1:?Uso: ./release.sh X.Y.Z}
VER=${VER#v} TAG=v${1#v}
cd "$(dirname "$0")"
die() { echo "ERROR: $*" >&2; exit 1; }
ask() { local a; read -rp "$1 [s/N] " a; [[ $a == [sS]* ]]; }

[[ $VER =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "la versión tiene que ser X.Y.Z (p. ej. 1.1.0)"
command -v gh >/dev/null && gh auth status >/dev/null 2>&1 || die "hace falta gh con sesión iniciada (gh auth login)"

echo "==> Comprobaciones"
[ "$(git branch --show-current)" = main ] || die "no estás en la rama main"
[ -z "$(git status --porcelain)" ] || die "hay cambios sin commit (git status)"
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && die "la etiqueta $TAG ya existe"
cur=$(sed -n 's/^TOOLBOX_VERSION=\([0-9.]*\).*/\1/p' ps5-bazzite-toolbox.sh)
[ "$cur" = "$VER" ] || die "ps5-bazzite-toolbox.sh dice TOOLBOX_VERSION=$cur, no $VER"
last=$(git tag -l 'v*' --sort=-v:refname | head -1)
[ -z "$last" ] || [ "$(printf '%s\n%s\n' "${last#v}" "$VER" | sort -V | tail -1)" = "$VER" ] ||
    die "$TAG no es mayor que la última publicada ($last)"
bash -n ps5-bazzite-toolbox.sh || die "ps5-bazzite-toolbox.sh tiene errores de sintaxis"
if command -v shellcheck >/dev/null; then shellcheck -S warning ps5-bazzite-toolbox.sh || ask "shellcheck avisa. ¿Seguir igualmente?" || exit 1
else echo "    (shellcheck no está instalado: me lo salto)"; fi

# Notes = the CHANGELOG section of this version, without its heading
notes=$(awk -v v="$VER" '$0 ~ "^## \\[" v "\\]" { on = 1; next } on && /^## \[/ { exit } on && /^\[/ { exit } on' CHANGELOG.md)
[ -n "$(tr -d '[:space:]' <<<"$notes")" ] || die "CHANGELOG.md no tiene una sección «## [$VER] - fecha» con contenido"

# Personal data that must not go public (the toolbox is meant to be generic)
leaks=$(grep -nE '192\.168\.[0-9]+\.[0-9]+|10\.[0-9]+\.[0-9]+\.[0-9]+|[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+\.[A-Za-z.]{2,}' \
    ps5-bazzite-toolbox.sh README.md CHANGELOG.md | grep -v 'noreply' || true)
if [ -n "$leaks" ]; then
    echo "    Posibles datos personales (IPs, correos):"; sed 's/^/      /' <<<"$leaks"
    ask "¿Son ejemplos genéricos y quieres seguir?" || exit 1
fi

git fetch -q origin main
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || git merge-base --is-ancestor origin/main HEAD ||
    die "origin/main tiene commits que tú no tienes (git pull primero)"

printf '\n==> Se publicará %s (commit %s)\n\n%s\n\n' "$TAG" "$(git rev-parse --short HEAD)" "$notes"
echo "QUÉ HACE: crea la etiqueta $TAG, sube main y la etiqueta a GitHub y crea la release con ps5-bazzite-toolbox.sh y su"
echo "          .sha256. Quien tenga la caja de herramientas verá el aviso de versión nueva al abrir el menú."
echo "DESHACER: gh release delete $TAG --cleanup-tag"
ask "¿Publicar $TAG?" || exit 1

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cp ps5-bazzite-toolbox.sh "$tmp/"
if command -v sha256sum >/dev/null; then (cd "$tmp" && sha256sum ps5-bazzite-toolbox.sh >ps5-bazzite-toolbox.sh.sha256)
else (cd "$tmp" && shasum -a 256 ps5-bazzite-toolbox.sh >ps5-bazzite-toolbox.sh.sha256); fi
printf '%s\n' "$notes" >"$tmp/notes.md"

git tag -a "$TAG" -m "ps5-bazzite-toolbox $TAG"
git push origin main "$TAG"
gh release create "$TAG" "$tmp/ps5-bazzite-toolbox.sh" "$tmp/ps5-bazzite-toolbox.sh.sha256" \
    --verify-tag --title "$TAG" --notes-file "$tmp/notes.md"
echo "Hecho: $(gh release view "$TAG" --json url --jq .url)"
