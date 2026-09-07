#!/bin/sh
set -eu
DOTFILES_REPO=$(CDPATH='' cd "$(dirname "$0")/.." && pwd -P)
export DOTFILES_REPO
# shellcheck source=scripts/core.sh
. "$DOTFILES_REPO/scripts/core.sh"

MANAGER=chezmoi
WITH=''
WITH_SET=0
DRY_RUN=0
CONFIG_ONLY=0
PACKAGE_NETWORK=${DOTFILES_PACKAGE_NETWORK:-}
SOURCE_NETWORK=${DOTFILES_SOURCE_NETWORK:-}
ACTION=setup
parse_args() {
while [ "$#" -gt 0 ]; do
    case "$1" in
        --source-network) [ "$#" -ge 2 ] || die '--source-network requires a value'; SOURCE_NETWORK=$2; shift 2 ;;
        --package-network) [ "$#" -ge 2 ] || die '--package-network requires a value'; PACKAGE_NETWORK=$2; shift 2 ;;
        --manager) [ "$#" -ge 2 ] || die '--manager requires a value'; MANAGER=$2; shift 2 ;;
        --with) [ "$#" -ge 2 ] || die '--with requires a value'; WITH="$WITH $(printf '%s' "$2" | tr ',' ' ')"; WITH_SET=1; shift 2 ;;
        --dry-run) DRY_RUN=1; shift ;;
        --config-only) CONFIG_ONLY=1; shift ;;
        --doctor) ACTION=doctor; shift ;;
        --prepare-chezmoi) ACTION=prepare; MANAGER=chezmoi; shift ;;
        --record-chezmoi) ACTION=record; shift ;;
        --help|-h)
            printf '%s\n' 'Usage: sh bootstrap.sh [--manager auto|chezmoi|sh] [--with dev,starship,herdr,specstory,codex] [--source-network inherit|direct|proxy] [--package-network inherit|direct] [--config-only] [--dry-run] [--doctor]' 'Default: chezmoi with a Git source and baseline packages only; optional agent tools are OpenWrt-only.'
            exit 0 ;;
        *) die "Unknown argument: $1" ;;
    esac
done
}
parse_args "$@"
case "$MANAGER" in auto|sh|chezmoi) ;; *) die 'Expected --manager auto|sh|chezmoi' ;; esac
context
load_network_preferences
if [ "$WITH_SET" = 0 ] && [ -r "$STATE/options" ]; then WITH=$(cat "$STATE/options"); fi
validate_options
if [ "$ACTION" = doctor ]; then doctor; exit; fi
if [ "$DRY_RUN" = 1 ]; then
    say "Dry run: platform=$PLATFORM manager=$MANAGER optional=$WITH config-only=$CONFIG_ONLY"
    [ "$PLATFORM" != ish ] || say "Alpine repositories: $(branch_description)"
    [ "$CONFIG_ONLY" = 1 ] || cat "$REPO/config/packages-base.txt"
    cat "$REPO/config/files.list"
    exit 0
fi
if [ "$ACTION" = prepare ]; then
    check_sh_migration
    packages
    [ "$OPTIONAL_FAILED" = 0 ] || die 'Some explicitly requested optional tools failed.'
    exit 0
fi
if [ "$ACTION" = record ]; then SELECTED=chezmoi; record_state; exit 0; fi
OPTIONAL_FAILED=0
[ "$CONFIG_ONLY" = 1 ] || packages || die 'Baseline package installation failed; configuration has not been applied.'
choose_manager
if [ "$SELECTED" = chezmoi ] && [ "$CONFIG_ONLY" = 0 ] && [ ! -e "$REPO/.git" ] && [ ! -L "$REPO/.git" ]; then
    ensure_git_source || die 'Git source setup failed; existing snapshot and home configuration preserved.'
    # The new checkout may contain newer installer code. Re-enter it with the
    # original arguments; installed packages/binaries are retained on this pass.
    exec sh "$REPO/scripts/manage.sh" "$@"
fi
case "$SELECTED" in sh) apply_sh ;; chezmoi) apply_chezmoi ;; esac || die 'Configuration failed; manager selection was not changed.'
record_state
[ "$SELECTED" != chezmoi ] || say 'Daily commands: chezmoi diff, chezmoi apply, chezmoi update'
say 'Baseline configured. Open a login shell, or run: . ~/.profile'
[ "$OPTIONAL_FAILED" = 0 ] || die 'Baseline is ready, but one or more requested optional tools failed; retry after resolving the reported cause.'
