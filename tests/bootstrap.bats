#!/usr/bin/env bats

setup() {
    export REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
    export REAL_CHEZMOI="$(command -v chezmoi || true)"
    export DOTFILES_TEST_ROOT="$BATS_TEST_TMPDIR/fixture"
    export DOTFILES_TEST_MODE=fixture-only-v1
    export HOME="$DOTFILES_TEST_ROOT/home"
    export XDG_CONFIG_HOME="$HOME/.config"
    export XDG_DATA_HOME="$HOME/.local/share"
    export XDG_STATE_HOME="$HOME/.local/state"
    export XDG_CACHE_HOME="$HOME/.cache"
    export CHEZMOI_CONFIG="$XDG_CONFIG_HOME/chezmoi/chezmoi.toml"
    mkdir -p "$HOME" "$DOTFILES_TEST_ROOT/bin" "$DOTFILES_TEST_ROOT/etc/apk"
    touch "$DOTFILES_TEST_ROOT/.fixture"
    export TEST_PLATFORM="$(cat "$REPO/config/platform")"
    if [ "$TEST_PLATFORM" = ish ]; then
        mkdir -p "$DOTFILES_TEST_ROOT/proc/ish"
        export TEST_ARCH=i686
    else
        touch "$DOTFILES_TEST_ROOT/etc/openwrt_release"
        export TEST_ARCH=aarch64
    fi
    cat >"$DOTFILES_TEST_ROOT/etc/apk/repositories" <<'EOF'
# iSH default snapshot
http://apk.ish.app/v3.14-2023-05-19/main/x86
http://apk.ish.app/v3.14-2023-05-19/community/x86
EOF
    cat >"$DOTFILES_TEST_ROOT/bin/uname" <<'EOF'
#!/bin/sh
case "$1" in -s) echo Linux ;; -m) echo "$TEST_ARCH" ;; esac
EOF
    cat >"$DOTFILES_TEST_ROOT/bin/id" <<'EOF'
#!/bin/sh
echo 0
EOF
    cat >"$DOTFILES_TEST_ROOT/bin/apk" <<'EOF'
#!/bin/sh
printf 'apk %s\n' "$*" >>"$DOTFILES_TEST_ROOT/calls"
case "$1" in info) exit 1 ;; add) exit "${FAIL_PACKAGES:-0}" ;; update) exit 0 ;; esac
EOF
    cat >"$DOTFILES_TEST_ROOT/bin/timeout" <<'EOF'
#!/bin/sh
shift
exec "$@"
EOF
    # A fixture must never contact the network, even when the installer regresses.
    for tool in curl wget uclient-fetch; do
        cat >"$DOTFILES_TEST_ROOT/bin/$tool" <<'EOF'
#!/bin/sh
echo 'network fixture failure' >&2
exit 22
EOF
    done
    chmod +x "$DOTFILES_TEST_ROOT/bin/"*
    export PATH="$DOTFILES_TEST_ROOT/bin:$PATH"
}

@test "sh setup is idempotent and keeps SSH, tmux, profile and credentials" {
    mkdir -p "$HOME/.ssh"
    printf 'Host personal\n    HostName example.invalid\n' >"$HOME/.ssh/config"
    printf '# custom tmux\n' >"$HOME/.tmux.conf"
    printf 'export PERSONAL=value\n# >>> ish-bootstrap (obsidian) >>>\novault() { : legacy; }\n' >"$HOME/.profile"
    printf '[credential]\n helper = custom\n' >"$HOME/.gitconfig"
    cp "$HOME/.ssh/config" "$BATS_TEST_TMPDIR/ssh"
    run sh "$REPO/bootstrap.sh" --manager sh --config-only
    [ "$status" = 0 ]
    cp "$HOME/.profile" "$BATS_TEST_TMPDIR/profile"
    run sh "$REPO/bootstrap.sh" --manager sh --config-only
    [ "$status" = 0 ]
    cmp "$HOME/.profile" "$BATS_TEST_TMPDIR/profile"
    cmp "$HOME/.ssh/config" "$BATS_TEST_TMPDIR/ssh"
    grep -q custom "$HOME/.tmux.conf"
    grep -q custom "$HOME/.gitconfig"
    [ "$(grep -c '# >>> dotfiles-lite >>>' "$HOME/.profile")" = 1 ]
    run sh -c '. "$HOME/.profile"; ovault'
    [ "$status" = 0 ]
}

@test "dry-run does not create home files or contact a package manager" {
    run sh "$REPO/bootstrap.sh" --dry-run
    [ "$status" = 0 ]
    [ -z "$(find "$HOME" -type f -print)" ]
    [ ! -e "$DOTFILES_TEST_ROOT/calls" ]
}

@test "native target markers are mandatory even with a package manager" {
    rm -rf "$DOTFILES_TEST_ROOT/proc/ish"
    rm -f "$DOTFILES_TEST_ROOT/etc/openwrt_release"
    run sh "$REPO/bootstrap.sh" --manager sh --config-only
    [ "$status" != 0 ]
    [ ! -e "$HOME/.profile" ]
}

@test "fixture redirection cannot target a real HOME" {
    export HOME="$BATS_TEST_TMPDIR/other"
    run sh "$REPO/bootstrap.sh" --manager sh --config-only
    [ "$status" != 0 ]
    [[ "$output" == *'Fixture HOME must be isolated'* ]]
}

@test "baseline package failure leaves home configuration untouched" {
    export FAIL_PACKAGES=1
    run sh "$REPO/bootstrap.sh" --manager sh
    [ "$status" != 0 ]
    [ ! -e "$HOME/.profile" ]
    grep -q 'apk add' "$DOTFILES_TEST_ROOT/calls"
}

@test "managed-file edits and symlinks are preserved instead of overwritten" {
    run sh "$REPO/bootstrap.sh" --manager sh --config-only
    [ "$status" = 0 ]
    printf '# user edit\n' >>"$HOME/.config/dotfiles-lite/profile.sh"
    run sh "$REPO/bootstrap.sh" --manager sh --config-only
    [ "$status" != 0 ]
    grep -q 'user edit' "$HOME/.config/dotfiles-lite/profile.sh"
    rm "$HOME/.profile"
    printf 'external\n' >"$BATS_TEST_TMPDIR/external"
    ln -s "$BATS_TEST_TMPDIR/external" "$HOME/.profile"
    run sh "$REPO/bootstrap.sh" --manager sh --config-only
    [ "$status" != 0 ]
    [ "$(cat "$BATS_TEST_TMPDIR/external")" = external ]
}

@test "explicit chezmoi failure does not silently fall back" {
    printf '#!/bin/sh\nexit 1\n' >"$DOTFILES_TEST_ROOT/bin/chezmoi"
    chmod +x "$DOTFILES_TEST_ROOT/bin/chezmoi"
    run sh "$REPO/bootstrap.sh" --manager chezmoi --config-only
    [ "$status" != 0 ]
    [ ! -e "$HOME/.profile" ]
}

@test "initial auto can use sh and retains that selection on subsequent runs" {
    printf '#!/bin/sh\nexit 1\n' >"$DOTFILES_TEST_ROOT/bin/chezmoi"
    chmod +x "$DOTFILES_TEST_ROOT/bin/chezmoi"
    run sh "$REPO/bootstrap.sh" --config-only
    [ "$status" = 0 ]
    [ "$(cat "$HOME/.local/state/dotfiles-lite/manager")" = sh ]
    rm "$DOTFILES_TEST_ROOT/bin/chezmoi"
    run sh "$REPO/bootstrap.sh" --config-only
    [ "$status" = 0 ]
    [ "$(cat "$HOME/.local/state/dotfiles-lite/manager")" = sh ]
}

@test "chezmoi and sh deploy identical configuration from the same source" {
    [ -n "$REAL_CHEZMOI" ] || skip 'chezmoi not installed on test host'
    run sh "$REPO/bootstrap.sh" --manager sh --config-only
    [ "$status" = 0 ]
    cp -R "$HOME" "$BATS_TEST_TMPDIR/sh-home"
    run sh "$REPO/bootstrap.sh" --manager chezmoi --config-only
    [ "$status" = 0 ]
    [ "$(cat "$HOME/.local/state/dotfiles-lite/manager")" = chezmoi ]
    while IFS='|' read -r kind source target mode; do
        cmp "$HOME/$target" "$BATS_TEST_TMPDIR/sh-home/$target"
    done <"$REPO/config/files.list"
    # Fresh target render also uses real chezmoi, with scripts excluded.
    mkdir "$BATS_TEST_TMPDIR/fresh"
    run "$REAL_CHEZMOI" --config "$CHEZMOI_CONFIG" apply --source "$REPO" --destination "$BATS_TEST_TMPDIR/fresh" --exclude=scripts --force
    [ "$status" = 0 ]
    while IFS='|' read -r kind source target mode; do
        cmp "$BATS_TEST_TMPDIR/fresh/$target" "$BATS_TEST_TMPDIR/sh-home/$target"
    done <"$REPO/config/files.list"
}

@test "existing unrelated chezmoi source is not taken over" {
    [ -n "$REAL_CHEZMOI" ] || skip 'chezmoi not installed on test host'
    mkdir -p "$(dirname "$CHEZMOI_CONFIG")" "$BATS_TEST_TMPDIR/unrelated"
    printf 'sourceDir = "%s"\n' "$BATS_TEST_TMPDIR/unrelated" >"$CHEZMOI_CONFIG"
    cp "$CHEZMOI_CONFIG" "$BATS_TEST_TMPDIR/config-before"
    run sh "$REPO/bootstrap.sh" --manager chezmoi --config-only
    [ "$status" != 0 ]
    cmp "$CHEZMOI_CONFIG" "$BATS_TEST_TMPDIR/config-before"
    [ ! -e "$HOME/.profile" ]
}

@test "direct chezmoi init --apply runs native hooks from paths with spaces and quotes" {
    [ -n "$REAL_CHEZMOI" ] || skip 'chezmoi not installed on test host'
    source_copy="$BATS_TEST_TMPDIR/source with ' quote"
    mkdir -p "$source_copy"
    cp -R "$REPO/scripts" "$REPO/config" "$REPO/home" "$REPO/.chezmoiroot" "$source_copy/"
    run "$REAL_CHEZMOI" --config "$CHEZMOI_CONFIG" init --source "$source_copy" --destination "$HOME" --apply
    [ "$status" = 0 ]
    grep -q 'apk add' "$DOTFILES_TEST_ROOT/calls"
    [ -f "$HOME/.profile" ]
    [ "$(cat "$HOME/.local/state/dotfiles-lite/manager")" = chezmoi ]
}

@test "iSH snapshot, standard and custom repository URLs are diagnosed" {
    [ "$TEST_PLATFORM" = ish ] || skip 'iSH only'
    run sh "$REPO/bootstrap.sh" --dry-run
    [ "$status" = 0 ]
    [[ "$output" == *'v3.14-2023-05-19'* ]]
    printf 'https://dl-cdn.alpinelinux.org/alpine/v3.18/main\n' >"$DOTFILES_TEST_ROOT/etc/apk/repositories"
    run sh "$REPO/bootstrap.sh" --dry-run
    [[ "$output" == *'v3.18'* ]]
    printf 'https://example.invalid/custom/main\n' >"$DOTFILES_TEST_ROOT/etc/apk/repositories"
    run sh "$REPO/bootstrap.sh" --dry-run
    [[ "$output" == *'unknown (custom repository URL)'* ]]
}

@test "iSH rejects optional local agents before touching packages" {
    [ "$TEST_PLATFORM" = ish ] || skip 'iSH only'
    run sh "$REPO/bootstrap.sh" --with codex
    [ "$status" != 0 ]
    [ ! -e "$DOTFILES_TEST_ROOT/calls" ]
}

@test "OpenWrt optional failure still configures the baseline and returns failure" {
    [ "$TEST_PLATFORM" = openwrt ] || skip 'OpenWrt only'
    # Unsupported architecture avoids relying on tools installed on the test host.
    export TEST_ARCH=mips
    for tool in herdr specstory; do
        printf '#!/bin/sh\nexit 1\n' >"$DOTFILES_TEST_ROOT/bin/$tool"
        chmod +x "$DOTFILES_TEST_ROOT/bin/$tool"
    done
    run sh "$REPO/bootstrap.sh" --manager sh --with herdr,specstory
    [ "$status" != 0 ]
    [ -f "$HOME/.profile" ]
    [[ "$output" == *'no locked release for mips'* ]]
    [ ! -e "$HOME/.local/bin/herdr" ]
}

@test "OpenWrt supports opkg without invoking apk or changing feeds" {
    [ "$TEST_PLATFORM" = openwrt ] || skip 'OpenWrt only'
    # opkg-only fixture PATH; retain required host utilities but no host apk.
    rm "$DOTFILES_TEST_ROOT/bin/apk"
    command -v apk >/dev/null 2>&1 && skip 'Host apk would hide opkg fallback'
    cat >"$DOTFILES_TEST_ROOT/bin/opkg" <<'EOF'
#!/bin/sh
printf 'opkg %s\n' "$*" >>"$DOTFILES_TEST_ROOT/calls"
case "$1" in status) exit 1 ;; *) exit 0 ;; esac
EOF
    chmod +x "$DOTFILES_TEST_ROOT/bin/opkg"
    run sh "$REPO/bootstrap.sh" --manager sh
    [ "$status" = 0 ]
    grep -q 'opkg install' "$DOTFILES_TEST_ROOT/calls"
    ! grep -q upgrade "$DOTFILES_TEST_ROOT/calls"
    [ ! -e "$DOTFILES_TEST_ROOT/etc/opkg.conf" ]
}
