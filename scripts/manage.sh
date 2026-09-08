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
SSHD=${DOTFILES_SSHD:-}
SSHD_INITIAL=''
FINDER=${DOTFILES_FINDER:-}
FINDER_INITIAL=''
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
        --sshd) [ "$#" -ge 2 ] || die '--sshd requires on or off'; SSHD=$2; shift 2 ;;
        --sshd-initial) [ "$#" -ge 2 ] || die '--sshd-initial requires on or off'; SSHD_INITIAL=$2; shift 2 ;;
        --prepare-sshd) ACTION=sshd; shift ;;
        --finder) [ "$#" -ge 2 ] || die '--finder requires on or off'; FINDER=$2; shift 2 ;;
        --finder-initial) [ "$#" -ge 2 ] || die '--finder-initial requires on or off'; FINDER_INITIAL=$2; shift 2 ;;
        --prepare-finder) ACTION=finder; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        --config-only) CONFIG_ONLY=1; shift ;;
        --doctor) ACTION=doctor; shift ;;
        --prepare-chezmoi) ACTION=prepare; MANAGER=chezmoi; shift ;;
        --record-chezmoi) ACTION=record; shift ;;
        --help|-h)
            printf '%s\n' 'Usage: sh bootstrap.sh [--manager auto|chezmoi|sh] [--with dev,starship,herdr,specstory,codex] [--sshd on|off] [--prepare-sshd] [--finder on|off] [--prepare-finder] [--source-network inherit|direct|proxy] [--package-network inherit|direct] [--config-only] [--dry-run] [--doctor]' 'Default: chezmoi with a Git source. iSH also prepares SSH on port 22000 and Finder files at /mnt/finder; agent installers require device acceptance.'
            exit 0 ;;
        *) die "Unknown argument: $1" ;;
    esac
done
}
parse_args "$@"
case "$MANAGER" in auto|sh|chezmoi) ;; *) die 'Expected --manager auto|sh|chezmoi' ;; esac
context
load_network_preferences
load_sshd_preference
load_finder_preference
if [ "$ACTION" = sshd ] || [ "$ACTION" = finder ]; then
    [ "$WITH_SET" = 0 ] || die "--prepare-$ACTION cannot be combined with --with"
else
    if [ "$WITH_SET" = 0 ] && [ -r "$STATE/options" ]; then WITH=$(cat "$STATE/options"); fi
    validate_options
fi
if [ "$ACTION" = doctor ]; then doctor; exit; fi
[ "$ACTION" != sshd ] || { [ "$PLATFORM" = ish ] && [ "$CONFIG_ONLY" = 0 ]; } || die '--prepare-sshd requires iSH and cannot be combined with --config-only'
[ "$ACTION" != finder ] || { [ "$PLATFORM" = ish ] && [ "$CONFIG_ONLY" = 0 ]; } || die '--prepare-finder requires iSH and cannot be combined with --config-only'
if [ "$DRY_RUN" = 1 ]; then
    say "Dry run: platform=$PLATFORM manager=$MANAGER optional=$WITH config-only=$CONFIG_ONLY"
    [ "$PLATFORM" != ish ] || say "Alpine repositories: $(branch_description)"
    [ "$PLATFORM" != ish ] || say "SSH server: $SSHD (create-once config; default runlevel; no restart)"
    [ "$PLATFORM" != ish ] || say "Finder files: $FINDER (/mnt/finder; default runlevel; existing contents preserved)"
    if [ "$ACTION" = sshd ]; then
        [ "$SSHD" = off ] || cat "$REPO/config/packages-sshd.txt"
        exit 0
    fi
    if [ "$ACTION" = finder ]; then
        [ "$FINDER" = off ] || cat "$REPO/config/packages-finder.txt"
        exit 0
    fi
    [ "$CONFIG_ONLY" = 1 ] || cat "$REPO/config/packages-base.txt"
    cat "$REPO/config/files.list"
    exit 0
fi
if [ "$ACTION" = sshd ]; then prepare_sshd; exit; fi
if [ "$ACTION" = finder ]; then prepare_finder; exit; fi
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
