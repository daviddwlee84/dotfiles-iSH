#!/bin/sh
# iSH-only Finder mount installation. Never sourced by an interactive shell.
set -eu
DOTFILES_REPO=$(CDPATH='' cd "$(dirname "$0")/.." && pwd -P)
export DOTFILES_REPO
# shellcheck source=scripts/core.sh
. "$DOTFILES_REPO/scripts/core.sh"
context
[ "$PLATFORM" = ish ] || die 'Finder mount setup is iSH-only.'
PACKAGE_NETWORK=${DOTFILES_PACKAGE_NETWORK:-}
SOURCE_NETWORK=${DOTFILES_SOURCE_NETWORK:-}
FINDER=${DOTFILES_FINDER:-}
load_network_preferences
load_finder_preference
case "${1:-}" in ''|--status) ;; *) die 'Usage: sh scripts/finder.sh [--status]' ;; esac
[ "$#" -le 1 ] || die 'Unexpected Finder setup arguments'
finder_helper="$SYSROOT/usr/local/libexec/dotfiles-finder"
finder_service="$SYSROOT/etc/init.d/dotfiles-finder"
finder_rc_update="$SYSROOT/sbin/rc-update"

finder_owned() {
    [ -f "$finder_helper" ] && [ ! -L "$finder_helper" ] &&
        [ -f "$finder_service" ] && [ ! -L "$finder_service" ] &&
        grep -q '^# managed-by: dotfiles-lite-finder;' "$finder_helper" &&
        grep -q '^# managed-by: dotfiles-lite-finder;' "$finder_service"
}

if [ "${1:-}" = --status ]; then
    say "Finder preference: $FINDER"
    if finder_owned && [ -L "$SYSROOT/etc/runlevels/default/dotfiles-finder" ]; then
        say 'Finder autostart: registered in default'
    else say 'Finder autostart: not registered'; fi
    sh "$REPO/scripts/finder-mount.sh" status || say 'Finder mount is not confirmed ready.'
    exit 0
fi
[ "$(id -u)" = 0 ] || die 'Finder setup requires root; use --config-only for home configuration.'
for finder_path in "$SYSROOT/usr/local" "$SYSROOT/usr/local/libexec" "$finder_helper" "$SYSROOT/etc/init.d" "$finder_service"; do
    [ ! -L "$finder_path" ] || die "Finder setup preserves symlink: $finder_path"
done
if [ "$FINDER" = off ]; then
    if finder_owned && [ -L "$SYSROOT/etc/runlevels/default/dotfiles-finder" ]; then
        [ -x "$finder_rc_update" ] || die 'OpenRC is missing; cannot remove Finder autostart registration.'
        "$finder_rc_update" del dotfiles-finder default || die 'Failed to remove Finder autostart registration'
    fi
    say 'Finder autostart off. Current mounts, shared files and service seeds are preserved.'
    exit 0
fi
for finder_path in "$finder_helper" "$finder_service"; do
    if [ -e "$finder_path" ]; then
        [ -f "$finder_path" ] && grep -q '^# managed-by: dotfiles-lite-finder;' "$finder_path" || die "Existing Finder service/helper preserved: $finder_path"
    fi
done
sh "$REPO/scripts/finder-mount.sh" check || die 'Finder mount preflight failed; no service changes were made.'
install_packages "$REPO/config/packages-finder.txt" || die 'Finder OpenRC package could not be installed.'
[ -x "$finder_rc_update" ] || die "Finder prerequisite missing: $finder_rc_update"
mkdir -p "$SYSROOT/usr/local/libexec" "$SYSROOT/etc/init.d"
finder_seed() {
    [ ! -e "$2" ] || return 0
    finder_seed_tmp=$(mktemp "$(dirname "$2")/.finder-seed.XXXXXX")
    if ! cp "$1" "$finder_seed_tmp" || ! chmod 755 "$finder_seed_tmp" || ! ln "$finder_seed_tmp" "$2"; then
        rm -f "$finder_seed_tmp"
        die "Could not publish Finder seed without replacing an existing file: $2"
    fi
    rm -f "$finder_seed_tmp"
}
finder_seed "$REPO/scripts/finder-mount.sh" "$finder_helper"
finder_seed "$REPO/config/finder/dotfiles-finder" "$finder_service"
sh "$finder_helper" mount || die 'Finder mounting failed; autostart was not registered by this run.'
"$finder_rc_update" add dotfiles-finder default || die 'Failed to register Finder mounting in the default runlevel'
say 'Finder files ready at /mnt/finder; automatic mounting registered for iSH startup.'
