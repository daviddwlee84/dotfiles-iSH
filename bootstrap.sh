#!/bin/sh
# Standalone entrypoint: usable before git, chezmoi, bash or just is installed.
set -eu
REPOSITORY=dotfiles-iSH
UPDATE_SOURCE=0
if [ "${1:-}" = --update-source ]; then UPDATE_SOURCE=1; shift; fi
BASE=$(CDPATH='' cd "$(dirname "$0")" && pwd -P)
if [ "$UPDATE_SOURCE" = 0 ] && [ -f "$BASE/scripts/manage.sh" ] && [ -f "$BASE/config/platform" ]; then
    exec sh "$BASE/scripts/manage.sh" "$@"
fi
OFFLINE_ACTION=0
for argument in "$@"; do
    case "$argument" in
        --config-only|--doctor) OFFLINE_ACTION=1 ;;
        --help|-h) printf '%s\n' 'bootstrap.sh [--update-source] [--manager auto|sh|chezmoi] [--with dev,starship,herdr,specstory,codex] [--sshd on|off] [--prepare-sshd] [--finder on|off] [--prepare-finder] [--source-network inherit|direct|proxy] [--package-network inherit|direct] [--config-only] [--dry-run] [--doctor]'; exit 0 ;;
        --dry-run) printf 'Would fetch %s, then inspect native prerequisites without applying.\n' "$REPOSITORY"; exit 0 ;;
    esac
done
SYSROOT=''
if [ -n "${DOTFILES_TEST_ROOT:-}" ]; then
    [ "${DOTFILES_TEST_MODE:-}" = fixture-only-v1 ] || { echo 'Invalid fixture mode' >&2; exit 1; }
    case "$DOTFILES_TEST_ROOT" in /*) ;; *) exit 1;; esac
    [ "$DOTFILES_TEST_ROOT" != / ] && [ -f "$DOTFILES_TEST_ROOT/.fixture" ] && [ "$HOME" = "$DOTFILES_TEST_ROOT/home" ] || exit 1
    SYSROOT=$DOTFILES_TEST_ROOT
fi
case "$REPOSITORY" in
    dotfiles-iSH) [ -d "$SYSROOT/proc/ish" ] || { echo 'This bootstrap is for iSH only.' >&2; exit 1; } ;;
    dotfiles-OpenWrt) [ -f "$SYSROOT/etc/openwrt_release" ] || { echo 'This bootstrap is for OpenWrt/ImmortalWrt only.' >&2; exit 1; } ;;
esac
REF=${DOTFILES_REF:-main}
case "$REF" in ''|*[!a-zA-Z0-9._-]*) echo 'DOTFILES_REF must be a simple tag or commit.' >&2; exit 1 ;; esac
DEST="$HOME/.local/share/$REPOSITORY"
if [ -e "$DEST" ]; then
    [ -d "$DEST" ] && [ ! -L "$DEST" ] || { echo 'Unsafe existing source path' >&2; exit 1; }
    if [ "$OFFLINE_ACTION" = 1 ] && [ "$UPDATE_SOURCE" = 0 ] && [ -f "$DEST/scripts/manage.sh" ]; then
        exec sh "$DEST/scripts/manage.sh" "$@"
    fi
    if [ "$UPDATE_SOURCE" = 1 ] || { [ ! -e "$DEST/.git" ] && [ ! -L "$DEST/.git" ]; }; then
        [ ! -e "$DEST/.git" ] && [ ! -L "$DEST/.git" ] || { echo 'Git checkout preserved: update it with chezmoi update.' >&2; exit 1; }
        [ -f "$DEST/scripts/manage.sh" ] && [ -f "$DEST/config/platform" ] || { echo 'Unrecognized source snapshot' >&2; exit 1; }
    elif [ -f "$DEST/scripts/manage.sh" ]; then
        echo "Using existing source at $DEST (install-only; update the source explicitly)."
        exec sh "$DEST/scripts/manage.sh" "$@"
    else
        echo "Existing source path is not a recognized checkout: $DEST" >&2
        exit 1
    fi
fi
TASK_TMP=$(mktemp -d)
trap 'rm -rf "$TASK_TMP"' EXIT HUP INT TERM
URL="https://api.github.com/repos/daviddwlee84/$REPOSITORY/tarball/$REF"
if command -v curl >/dev/null 2>&1; then curl -fLsS --connect-timeout 15 --max-time 180 -o "$TASK_TMP/source.tar.gz" "$URL"
elif command -v wget >/dev/null 2>&1; then wget -T 180 -O "$TASK_TMP/source.tar.gz" "$URL"
elif command -v uclient-fetch >/dev/null 2>&1; then uclient-fetch -T 180 -O "$TASK_TMP/source.tar.gz" "$URL"
else echo 'Need curl, wget or uclient-fetch; a copied checkout also works offline.' >&2; exit 1; fi
mkdir "$TASK_TMP/source"
# OpenWrt's reduced BusyBox tar lacks --strip-components.
tar -xzf "$TASK_TMP/source.tar.gz" -C "$TASK_TMP/source"
SOURCE_ROOT=''
for CANDIDATE in "$TASK_TMP/source"/*; do
    [ -d "$CANDIDATE" ] && [ ! -L "$CANDIDATE" ] && [ -z "$SOURCE_ROOT" ] || { echo 'Expected one source archive directory' >&2; exit 1; }
    SOURCE_ROOT=$CANDIDATE
done
[ -f "$SOURCE_ROOT/scripts/manage.sh" ] || { echo 'Incomplete source archive' >&2; exit 1; }
mkdir -p "$(dirname "$DEST")"
# Publish within the destination filesystem; do not expose a half-copied tree.
STAGED=$(mktemp -d "$(dirname "$DEST")/.${REPOSITORY}.XXXXXX")
if ! cp -R "$SOURCE_ROOT/." "$STAGED/"; then rm -rf "$STAGED"; exit 1; fi
if [ -d "$DEST" ]; then
    BACKUP=$(mktemp -d "$(dirname "$DEST")/.${REPOSITORY}.previous.XXXXXX")
    mv "$DEST" "$BACKUP/source"
    if ! mv "$STAGED" "$DEST"; then mv "$BACKUP/source" "$DEST"; exit 1; fi
    printf 'Previous source snapshot preserved at %s/source\n' "$BACKUP"
else
    mv "$STAGED" "$DEST"
fi
sh "$DEST/scripts/manage.sh" "$@"
