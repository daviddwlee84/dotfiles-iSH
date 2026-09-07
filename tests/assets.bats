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


@test "a probe kills a TERM-ignoring process and reports failure" {
    export REAL_TIMEOUT="$(command -v timeout || true)"
    [ -n "$REAL_TIMEOUT" ] || skip 'real timeout is required'
    mkdir -p "$HOME/bin"
    cat >"$HOME/bin/timeout" <<'EOF'
#!/bin/sh
[ "$1" = -s ] && [ "$2" = KILL ] && [ "$3" = 15 ] || exit 97
shift 3
# Shorten only the duration while exercising the actual timeout/signal behavior.
exec "$REAL_TIMEOUT" -s KILL 1 "$@"
EOF
    cat >"$HOME/bin/stubborn" <<'EOF'
#!/bin/sh
trap '' TERM
: >"$HOME/probe-started"
while :; do :; done
EOF
    chmod +x "$HOME/bin/timeout" "$HOME/bin/stubborn"
    run env PATH="$HOME/bin:$PATH" sh -c '
        DOTFILES_REPO=$REPO
        . "$REPO/scripts/core.sh"
        bounded_probe "$HOME/bin/stubborn"
    '
    [ "$status" != 0 ]
    [ -f "$HOME/probe-started" ]
    [[ "$output" == *'Probe timed out'* ]]
}
