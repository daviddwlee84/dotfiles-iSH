#!/bin/sh
# Standalone entrypoint: usable before git, chezmoi, bash or just is installed.
set -eu
REPOSITORY=dotfiles-iSH
BASE=$(CDPATH='' cd "$(dirname "$0")" && pwd -P)
if [ -f "$BASE/scripts/manage.sh" ] && [ -f "$BASE/config/platform" ]; then
    exec sh "$BASE/scripts/manage.sh" "$@"
fi
for argument in "$@"; do
    case "$argument" in
        --help|-h) printf '%s\n' 'bootstrap.sh [--manager auto|sh|chezmoi] [--with dev,herdr,specstory,codex] [--config-only] [--dry-run] [--doctor]'; exit 0 ;;
        --dry-run) printf 'Would fetch %s, then inspect native prerequisites without applying.\n' "$REPOSITORY"; exit 0 ;;
    esac
done
case "$REPOSITORY" in
    dotfiles-iSH) [ -d /proc/ish ] || { echo 'This bootstrap is for iSH only.' >&2; exit 1; } ;;
    dotfiles-OpenWrt) [ -f /etc/openwrt_release ] || { echo 'This bootstrap is for OpenWrt/ImmortalWrt only.' >&2; exit 1; } ;;
esac
REF=${DOTFILES_REF:-main}
case "$REF" in ''|*[!a-zA-Z0-9._-]*) echo 'DOTFILES_REF must be a simple tag or commit.' >&2; exit 1 ;; esac
DEST="$HOME/.local/share/$REPOSITORY"
if [ -e "$DEST" ]; then
    if [ -f "$DEST/scripts/manage.sh" ]; then
        echo "Using existing source at $DEST (install-only; update the source explicitly)."
        exec sh "$DEST/scripts/manage.sh" "$@"
    fi
    echo "Existing source path is not a recognized checkout: $DEST" >&2
    exit 1
fi
TASK_TMP=$(mktemp -d)
trap 'rm -rf "$TASK_TMP"' EXIT HUP INT TERM
URL="https://api.github.com/repos/daviddwlee84/$REPOSITORY/tarball/$REF"
if command -v curl >/dev/null 2>&1; then curl -fLsS --connect-timeout 15 --max-time 180 -o "$TASK_TMP/source.tar.gz" "$URL"
elif command -v wget >/dev/null 2>&1; then wget -T 180 -O "$TASK_TMP/source.tar.gz" "$URL"
elif command -v uclient-fetch >/dev/null 2>&1; then uclient-fetch -T 180 -O "$TASK_TMP/source.tar.gz" "$URL"
else echo 'Need curl, wget or uclient-fetch; a copied checkout also works offline.' >&2; exit 1; fi
mkdir "$TASK_TMP/source"
tar -xzf "$TASK_TMP/source.tar.gz" -C "$TASK_TMP/source" --strip-components=1
[ -f "$TASK_TMP/source/scripts/manage.sh" ] || { echo 'Incomplete source archive' >&2; exit 1; }
mkdir -p "$(dirname "$DEST")"
# Publish within the destination filesystem; do not expose a half-copied tree.
STAGED=$(mktemp -d "$(dirname "$DEST")/.${REPOSITORY}.XXXXXX")
if cp -R "$TASK_TMP/source/." "$STAGED/"; then mv "$STAGED" "$DEST"
else rm -rf "$STAGED"; exit 1; fi
sh "$DEST/scripts/manage.sh" "$@"
