#!/bin/sh
# CI-only helpers: installation is confined to a fresh temporary HOME.
set -eu
[ "${GITHUB_ACTIONS:-}" = true ] || { echo 'CI helper requires GitHub Actions' >&2; exit 1; }
DOTFILES_REPO=$(CDPATH='' cd "$(dirname "$0")/.." && pwd -P)
REPO=$DOTFILES_REPO
# shellcheck source=scripts/core.sh
. "$REPO/scripts/core.sh"
case "$(uname -m)" in x86_64) ARCH=amd64 ;; aarch64) ARCH=arm64 ;; *) exit 1 ;; esac
HOME=$(mktemp -d)
export HOME
case "${1:-}" in
    chezmoi)
        install_asset chezmoi
        printf '%s\n' "$HOME/.local/bin" >>"$GITHUB_PATH" ;;
    smoke)
        trap 'rm -rf "$HOME"' EXIT HUP INT TERM
        for tool in chezmoi herdr specstory codex; do install_asset "$tool"; done
        if [ -f "$REPO/home/dot_config/herdr/create_config.toml" ]; then
            HERDR_CONFIG_PATH="$REPO/home/dot_config/herdr/create_config.toml" "$HOME/.local/bin/herdr" config check
        fi ;;
    *) exit 2 ;;
esac
