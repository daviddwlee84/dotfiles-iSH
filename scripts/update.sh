#!/bin/sh
# chezmoi calls this before applying the refreshed source.
set -eu
DOTFILES_REPO=$(CDPATH='' cd "$(dirname "$0")/.." && pwd -P)
export DOTFILES_REPO
# shellcheck source=scripts/core.sh
. "$DOTFILES_REPO/scripts/core.sh"
context
PACKAGE_NETWORK=${DOTFILES_PACKAGE_NETWORK:-}
SOURCE_NETWORK=${DOTFILES_SOURCE_NETWORK:-}
load_network_preferences
[ -e "$REPO/.git" ] || die 'Source is a snapshot. Run the current bootstrap once to migrate it to Git.'
# Refuse divergent local history; never auto-stash, commit, push or discard edits.
source_command git -C "$REPO" pull --ff-only
