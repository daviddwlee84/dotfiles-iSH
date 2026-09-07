#!/usr/bin/env bats

setup() {
    export REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
    export HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$HOME/.local/bin"
}

@test "checksum failure preserves an existing binary and never executes the download" {
    printf 'original executable\n' >"$HOME/.local/bin/herdr"
    run sh -c '
        set -eu
        DOTFILES_REPO=$REPO
        . "$REPO/scripts/core.sh"
        ARCH=arm64
        probe() { return 1; }
        fetch() { printf "invalid download" >"$2"; }
        install_asset herdr
    '
    [ "$status" != 0 ]
    [[ "$output" == *'checksum mismatch'* ]]
    [ "$(cat "$HOME/.local/bin/herdr")" = 'original executable' ]
}

@test "low storage rejects download before touching the network" {
    run sh -c '
        set -eu
        DOTFILES_REPO=$REPO
        . "$REPO/scripts/core.sh"
        ARCH=arm64
        probe() { return 1; }
        df() { printf "fs 100 99 1 99%% /\n"; }
        fetch() { touch "$HOME/network-called"; return 1; }
        install_asset codex
    '
    [ "$status" != 0 ]
    [[ "$output" == *'staging space'* ]]
    [ ! -e "$HOME/network-called" ]
}

@test "every locked release has a checksum, size and unique tool/architecture pair" {
    run awk -F '|' '
        /^#/ {next}
        NF!=8 || $5 !~ /^[0-9a-f]+$/ || length($5)!=64 || $8 !~ /^[0-9]+$/ {bad=1}
        ++seen[$1 FS $2]>1 {bad=1}
        END {exit bad}
    ' "$REPO/config/assets.lock"
    [ "$status" = 0 ]
}
