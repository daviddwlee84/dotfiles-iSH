#!/usr/bin/env bats

setup() {
    export REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
    export PROBE_TMP="$BATS_TEST_TMPDIR"
    mkdir "$PROBE_TMP/bin"
    cat >"$PROBE_TMP/bin/ssh" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" >"$PROBE_TMP/ssh-args"
cat >"$PROBE_TMP/payload"
printf 'fixture probe result\n'
exit "${PROBE_EXIT:-0}"
EOF
    chmod +x "$PROBE_TMP/bin/ssh"
    export PATH="$PROBE_TMP/bin:$PATH"
}

@test "probe rejects option injection and unknown cases without connecting" {
    for target in '-oProxyCommand=bad' 'root@device' 'device;touch bad'; do
        run sh "$REPO/scripts/ish-probe.sh" --host "$target"
        [ "$status" = 2 ]
    done
    run sh "$REPO/scripts/ish-probe.sh" --host device --case 'node;id'
    [ "$status" = 2 ]
    [ ! -f "$PROBE_TMP/ssh-args" ]
}

@test "probe requires known host keys, limits connection and runtime, and preserves failure" {
    export PROBE_EXIT=23
    run sh "$REPO/scripts/ish-probe.sh" --host device --case node --output "$PROBE_TMP/report"
    [ "$status" = 23 ]
    grep -qx StrictHostKeyChecking=yes "$PROBE_TMP/ssh-args"
    grep -qx BatchMode=yes "$PROBE_TMP/ssh-args"
    grep -qx ConnectTimeout=10 "$PROBE_TMP/ssh-args"
    grep -q '\[ -d /proc/ish \]' "$PROBE_TMP/payload"
    grep -q 'timeout -s KILL 15' "$PROBE_TMP/payload"
    [ "$(cat "$PROBE_TMP/report")" = 'fixture probe result' ]
    rm "$PROBE_TMP/ssh-args"
    run sh "$REPO/scripts/ish-probe.sh" --host device --output "$PROBE_TMP/report"
    [ "$status" = 2 ]
    [ ! -f "$PROBE_TMP/ssh-args" ]
}

@test "agent version probes isolate home, project and auth even when the program writes state" {
    export DOTFILES_TEST_MODE=fixture-only-v1 DOTFILES_TEST_ROOT="$PROBE_TMP"
    export HOME="$PROBE_TMP/home" TMPDIR="$PROBE_TMP/scratch"
    mkdir -p "$HOME/.hako" "$TMPDIR" "$PROBE_TMP/project"
    touch "$PROBE_TMP/.fixture" "$HOME/original-home-marker" "$PROBE_TMP/project/original-project-marker"
    printf 'preserve-user-state\n' >"$HOME/.hako/state"
    cat >"$PROBE_TMP/bin/timeout" <<'EOF'
#!/bin/sh
[ "$1" = -s ] && [ "$2" = KILL ] && [ "$3" = 15 ] || exit 90
shift 3
exec "$@"
EOF
    cat >"$PROBE_TMP/bin/hako" <<'EOF'
#!/bin/sh
set -eu
[ "$1" = --version ]
[ -z "${HAKO_API_KEY:-}${NODE_OPTIONS:-}${SSH_AUTH_SOCK:-}" ]
[ ! -e "$HOME/original-home-marker" ] && [ ! -e ./original-project-marker ]
mkdir -p "$HOME/.hako"
printf 'new-probe-state\n' >"$HOME/.hako/state"
touch ./probe-project-write
echo 'fixture agent version'
EOF
    chmod +x "$PROBE_TMP/bin/timeout" "$PROBE_TMP/bin/hako"
    run sh "$REPO/scripts/ish-probe.sh" --host fixture --case hako
    [ "$status" = 0 ]
    # Execute the exact isolated function captured from the remote payload.
    awk '/^probe_agent_version\(\) \($/ {copy=1} copy {print} copy && /^\)$/ {exit}' "$PROBE_TMP/payload" >"$PROBE_TMP/version-function.sh"
    [ -s "$PROBE_TMP/version-function.sh" ]
    cd "$PROBE_TMP/project"
    export HAKO_API_KEY=fixture-auth-sentinel NODE_OPTIONS=fixture-option SSH_AUTH_SOCK=fixture-socket
    run sh -c '. "$1"; probe_agent_version hako' _ "$PROBE_TMP/version-function.sh"
    [ "$status" = 0 ]
    [ "$output" = 'fixture agent version' ]
    [ "$(cat "$HOME/.hako/state")" = preserve-user-state ]
    [ ! -e ./probe-project-write ]
    [ -z "$(ls -A "$TMPDIR")" ]
    printf '#!/bin/sh\nexit 17\n' >"$PROBE_TMP/bin/hako"
    run sh -c '. "$1"; probe_agent_version hako' _ "$PROBE_TMP/version-function.sh"
    [ "$status" = 17 ]
    [ -z "$(ls -A "$TMPDIR")" ]
}
