#!/usr/bin/env bats

setup() {
    export REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
    export GIT_CONFIG_NOSYSTEM=1
    export GIT_CONFIG_GLOBAL="$BATS_TEST_TMPDIR/gitconfig"
    printf '[url "file:///nonexistent-fixture-network/"]\n insteadOf = https://\n[core]\n hooksPath = /dev/null\n[user]\n name = Fixture\n email = fixture@example.invalid\n' >"$GIT_CONFIG_GLOBAL"
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
[ "$1" = -s ] && [ "$2" = KILL ] || exit 97
case "$3" in 15|120) ;; *) exit 97 ;; esac
shift 3
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
    if [ "$TEST_PLATFORM" = ish ]; then
        mkdir -p "$DOTFILES_TEST_ROOT/usr/sbin" "$DOTFILES_TEST_ROOT/usr/bin" "$DOTFILES_TEST_ROOT/sbin"
        printf '%s\n' /var/mobile/Containers/Data/Application/fixture/Documents >"$DOTFILES_TEST_ROOT/proc/ish/documents"
        : >"$DOTFILES_TEST_ROOT/proc/mounts"
        cat >"$DOTFILES_TEST_ROOT/bin/mount" <<'EOF'
#!/bin/sh
printf 'mount %s\n' "$*" >>"$DOTFILES_TEST_ROOT/finder-calls"
test "$#" = 4 && test "$1" = -t && test "$2" = real || exit 90
test "$4" = "$DOTFILES_TEST_ROOT/mnt/finder" || exit 90
test "${FAIL_FINDER_MOUNT:-0}" = 0 || exit 1
escaped_source=$(printf '%s' "$3" | sed 's/\\/\\134/g; s/ /\\040/g')
printf '%s %s real rw 0 0\n' "$escaped_source" "$4" >>"$DOTFILES_TEST_ROOT/proc/mounts"
EOF
        cat >"$DOTFILES_TEST_ROOT/usr/bin/ssh-keygen" <<'EOF'
#!/bin/sh
printf 'ssh-keygen %s\n' "$*" >>"$DOTFILES_TEST_ROOT/ssh-calls"
test "${FAIL_HOST_KEYS:-0}" = 0 || exit 1
key=''
while [ "$#" -gt 0 ]; do
    case "$1" in
        -q) shift ;;
        -t) test "$2" = ed25519 || exit 91; shift 2 ;;
        -N|-C) test -z "$2" || exit 91; shift 2 ;;
        -f) key=$2; shift 2 ;;
        *) exit 91 ;;
    esac
done
test -n "$key" || exit 91
printf 'generated-fixture-host-key\n' >"$key"
printf 'generated-fixture-public-key\n' >"$key.pub"
EOF
        cat >"$DOTFILES_TEST_ROOT/usr/sbin/sshd" <<'EOF'
#!/bin/sh
printf 'sshd %s\n' "$*" >>"$DOTFILES_TEST_ROOT/ssh-calls"
test "$1" = -t && test "$2" = -f || exit 92
exit "${FAIL_SSH_CONFIG:-0}"
EOF
        # Match Alpine openrc's package layout: rc-status is in /bin.
        cat >"$DOTFILES_TEST_ROOT/bin/rc-status" <<'EOF'
#!/bin/sh
printf '%s\n' "${TEST_RUNLEVEL:-default}"
EOF
        cat >"$DOTFILES_TEST_ROOT/sbin/rc-update" <<'EOF'
#!/bin/sh
case "$2" in
    dotfiles-sshd) call_log="$DOTFILES_TEST_ROOT/ssh-calls" ;;
    dotfiles-finder) call_log="$DOTFILES_TEST_ROOT/finder-service-calls" ;;
    *) exit 93 ;;
esac
printf 'rc-update %s\n' "$*" >>"$call_log"
test "$3" = default || exit 93
mkdir -p "$DOTFILES_TEST_ROOT/etc/runlevels/default"
case "$1" in
 add) ln -sf "../../init.d/$2" "$DOTFILES_TEST_ROOT/etc/runlevels/default/$2" ;;
 del) rm -f "$DOTFILES_TEST_ROOT/etc/runlevels/default/$2" ;;
 *) exit 94 ;;
esac
EOF
        cat >"$DOTFILES_TEST_ROOT/sbin/rc-service" <<'EOF'
#!/bin/sh
printf 'rc-service %s\n' "$*" >>"$DOTFILES_TEST_ROOT/ssh-calls"
test "$1" = dotfiles-sshd || exit 95
case "$2" in
 status) test -f "$DOTFILES_TEST_ROOT/ssh-running" ;;
 start) test "${FAIL_SSH_START:-0}" = 0 || exit 1; touch "$DOTFILES_TEST_ROOT/ssh-running" ;;
 *) exit 96 ;;
esac
EOF
        chmod +x "$DOTFILES_TEST_ROOT/usr/bin/ssh-keygen" "$DOTFILES_TEST_ROOT/usr/sbin/sshd" "$DOTFILES_TEST_ROOT/bin/rc-status" "$DOTFILES_TEST_ROOT/bin/mount" "$DOTFILES_TEST_ROOT/sbin/"*
    fi
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

@test "explicit snapshot update preserves the old source and refuses Git checkouts" {
    repository=$(basename "$REPO")
    standalone="$BATS_TEST_TMPDIR/standalone"
    destination="$HOME/.local/share/$repository"
    mkdir -p "$standalone" "$destination/scripts" "$destination/config" "$BATS_TEST_TMPDIR/archive/root/scripts" "$BATS_TEST_TMPDIR/archive/root/config"
    cp "$REPO/bootstrap.sh" "$standalone/bootstrap.sh"
    printf 'old source\n' >"$destination/custom-note"
    printf '%s\n' "$TEST_PLATFORM" >"$destination/config/platform"
    printf '#!/bin/sh\nexit 0\n' >"$destination/scripts/manage.sh"
    printf '#!/bin/sh\necho updated-source\n' >"$BATS_TEST_TMPDIR/archive/root/scripts/manage.sh"
    printf '%s\n' "$TEST_PLATFORM" >"$BATS_TEST_TMPDIR/archive/root/config/platform"
    tar -czf "$DOTFILES_TEST_ROOT/new-source.tar.gz" -C "$BATS_TEST_TMPDIR/archive" root
    export REAL_TAR="$(command -v tar)"
    cat >"$DOTFILES_TEST_ROOT/bin/tar" <<'EOF'
#!/bin/sh
for arg in "$@"; do case "$arg" in --strip-components*) exit 99;; esac; done
exec "$REAL_TAR" "$@"
EOF
    chmod +x "$DOTFILES_TEST_ROOT/bin/tar"
    cat >"$DOTFILES_TEST_ROOT/bin/curl" <<'EOF'
#!/bin/sh
while [ "$#" -gt 0 ]; do
    if [ "$1" = -o ]; then cp "$DOTFILES_TEST_ROOT/new-source.tar.gz" "$2"; exit; fi
    shift
done
exit 1
EOF
    chmod +x "$DOTFILES_TEST_ROOT/bin/curl"
    run sh "$standalone/bootstrap.sh" --update-source
    [ "$status" = 0 ]
    [[ "$output" == *updated-source* ]]
    [ ! -e "$destination/custom-note" ]
    [ "$(cat "$HOME/.local/share/.$repository.previous."*/source/custom-note)" = 'old source' ]
    mkdir "$destination/.git"
    run sh "$standalone/bootstrap.sh" --update-source
    [ "$status" != 0 ]
    [[ "$output" == *'Git checkout preserved'* ]]
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

@test "package-network direct clears proxies only for native package operations" {
    export http_proxy=http://parent.invalid:1234
    export HTTPS_PROXY=http://parent.invalid:1234
    cat >"$DOTFILES_TEST_ROOT/bin/apk" <<'EOF'
#!/bin/sh
test -z "${http_proxy:-}${HTTPS_PROXY:-}" || exit 44
test "$NO_PROXY" = '*' || exit 45
case "$1" in info) exit 1;; *) exit 0;; esac
EOF
    chmod +x "$DOTFILES_TEST_ROOT/bin/apk"
    run sh "$REPO/bootstrap.sh" --manager sh --package-network direct
    [ "$status" = 0 ]
    [ "$http_proxy" = http://parent.invalid:1234 ]
    [ "$HTTPS_PROXY" = http://parent.invalid:1234 ]
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

@test "an old chezmoi without workingTree is not accepted by a version-only probe" {
    cat >"$DOTFILES_TEST_ROOT/bin/chezmoi" <<'EOF'
#!/bin/sh
case "$1" in --version) echo 'chezmoi version v2.0.16';; execute-template) exit 0;; *) exit 1;; esac
EOF
    chmod +x "$DOTFILES_TEST_ROOT/bin/chezmoi"
    run sh "$REPO/bootstrap.sh" --manager chezmoi --config-only
    [ "$status" != 0 ]
    [ ! -e "$HOME/.profile" ]
}

@test "noninteractive shells do not initialize prompts and Bash can use Starship" {
    run sh "$REPO/bootstrap.sh" --manager sh --config-only
    [ "$status" = 0 ]
    cat >"$DOTFILES_TEST_ROOT/bin/starship" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$DOTFILES_TEST_ROOT/starship-calls"
printf 'PS1="starship-test> "\n'
EOF
    chmod +x "$DOTFILES_TEST_ROOT/bin/starship"
    run bash --noprofile --norc -c '. "$HOME/.profile"'
    [ "$status" = 0 ]
    [ ! -e "$DOTFILES_TEST_ROOT/starship-calls" ]
    run env TERM=xterm-256color bash --noprofile --norc -ic '. "$HOME/.bashrc"; test "$PS1" = "starship-test> "'
    [ "$status" = 0 ]
    grep -q '^init bash$' "$DOTFILES_TEST_ROOT/starship-calls"
}

@test "default and auto require chezmoi rather than silently retaining legacy sh" {
    printf '#!/bin/sh\nexit 1\n' >"$DOTFILES_TEST_ROOT/bin/chezmoi"
    chmod +x "$DOTFILES_TEST_ROOT/bin/chezmoi"
    mkdir -p "$HOME/.local/state/dotfiles-lite"
    echo sh >"$HOME/.local/state/dotfiles-lite/manager"
    run sh "$REPO/bootstrap.sh" --config-only
    [ "$status" != 0 ]
    [ ! -f "$HOME/.profile" ]
    run sh "$REPO/bootstrap.sh" --config-only --manager auto
    [ "$status" != 0 ]
    rm "$DOTFILES_TEST_ROOT/bin/chezmoi"
    [ -n "$REAL_CHEZMOI" ] || skip 'chezmoi not installed on test host'
    run sh "$REPO/bootstrap.sh" --config-only
    [ "$status" = 0 ]
    [ "$(cat "$HOME/.local/state/dotfiles-lite/manager")" = chezmoi ]
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

@test "explicit offline config-only keeps a snapshot free of empty Git metadata" {
    [ -n "$REAL_CHEZMOI" ] || skip 'chezmoi not installed on test host'
    source_copy="$BATS_TEST_TMPDIR/source-snapshot"
    mkdir -p "$source_copy"
    cp -R "$REPO/scripts" "$REPO/config" "$REPO/home" "$REPO/.chezmoiroot" "$source_copy/"
    run sh "$source_copy/scripts/manage.sh" --manager chezmoi --config-only
    [ "$status" = 0 ]
    [ ! -e "$source_copy/.git" ]
    [ -f "$HOME/.profile" ]
}

@test "direct chezmoi init --apply runs native hooks from paths with spaces and quotes" {
    [ -n "$REAL_CHEZMOI" ] || skip 'chezmoi not installed on test host'
    source_copy="$BATS_TEST_TMPDIR/source with ' quote"
    mkdir -p "$source_copy"
    cp -R "$REPO/scripts" "$REPO/config" "$REPO/home" "$REPO/.chezmoiroot" "$source_copy/"
    run "$REAL_CHEZMOI" --config "$CHEZMOI_CONFIG" init --promptDefaults --source "$source_copy" --destination "$HOME" --apply
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

@test "SSH defaults on and is prepared before a failing chezmoi probe" {
    [ "$TEST_PLATFORM" = ish ] || skip 'iSH only'
    printf '#!/bin/sh\nexit 1\n' >"$DOTFILES_TEST_ROOT/bin/chezmoi"
    chmod +x "$DOTFILES_TEST_ROOT/bin/chezmoi"
    run sh "$REPO/bootstrap.sh"
    [ "$status" != 0 ]
    [ -f "$DOTFILES_TEST_ROOT/ssh-running" ]
    [ "$(cat "$HOME/.local/state/dotfiles-lite/sshd")" = on ]
    [ -L "$DOTFILES_TEST_ROOT/etc/runlevels/default/dotfiles-sshd" ]
    [ ! -f "$HOME/.profile" ]
}

@test "SSH-only recovery is independent of saved optional tool selections" {
    [ "$TEST_PLATFORM" = ish ] || skip 'iSH only'
    mkdir -p "$HOME/.local/state/dotfiles-lite"
    echo obsolete-option >"$HOME/.local/state/dotfiles-lite/options"
    run sh "$REPO/bootstrap.sh" --prepare-sshd
    [ "$status" = 0 ]
    [ -f "$DOTFILES_TEST_ROOT/ssh-running" ]
    [ "$(cat "$HOME/.local/state/dotfiles-lite/options")" = obsolete-option ]
}

@test "SSH setup retains native config, keys and sessions across repeats and disable" {
    [ "$TEST_PLATFORM" = ish ] || skip 'iSH only'
    mkdir -p "$DOTFILES_TEST_ROOT/etc/ssh" "$HOME/.ssh"
    echo 'Port 2222' >"$DOTFILES_TEST_ROOT/etc/ssh/sshd_config"
    echo 'existing-key-fixture' >"$DOTFILES_TEST_ROOT/etc/ssh/ssh_host_ed25519_key"
    echo 'existing-authorized-key-fixture' >"$HOME/.ssh/authorized_keys"
    run sh "$REPO/bootstrap.sh" --prepare-sshd
    [ "$status" = 0 ]
    printf '\n# personal edit\n' >>"$DOTFILES_TEST_ROOT/etc/ssh/dotfiles-lite/sshd_config"
    run sh "$REPO/bootstrap.sh" --prepare-sshd
    [ "$status" = 0 ]
    [ "$(grep -c 'rc-service dotfiles-sshd start' "$DOTFILES_TEST_ROOT/ssh-calls")" = 1 ]
    grep -q 'personal edit' "$DOTFILES_TEST_ROOT/etc/ssh/dotfiles-lite/sshd_config"
    [ "$(cat "$DOTFILES_TEST_ROOT/etc/ssh/sshd_config")" = 'Port 2222' ]
    [ "$(cat "$DOTFILES_TEST_ROOT/etc/ssh/ssh_host_ed25519_key")" = existing-key-fixture ]
    [ "$(cat "$HOME/.ssh/authorized_keys")" = existing-authorized-key-fixture ]
    run sh "$REPO/bootstrap.sh" --prepare-sshd --sshd off
    [ "$status" = 0 ]
    [ ! -L "$DOTFILES_TEST_ROOT/etc/runlevels/default/dotfiles-sshd" ]
    [ -f "$DOTFILES_TEST_ROOT/ssh-running" ]
    [ "$(cat "$HOME/.local/state/dotfiles-lite/sshd")" = off ]
    ! grep -Eq ' restart| stop|passwd|chpasswd' "$DOTFILES_TEST_ROOT/ssh-calls"
}

@test "SSH dry-run, config-only and explicit off do not activate services" {
    [ "$TEST_PLATFORM" = ish ] || skip 'iSH only'
    run sh "$REPO/bootstrap.sh" --prepare-sshd --dry-run
    [ "$status" = 0 ]
    [ ! -e "$DOTFILES_TEST_ROOT/ssh-calls" ]
    [ ! -e "$HOME/.local/state/dotfiles-lite/sshd" ]
    run sh "$REPO/bootstrap.sh" --manager sh --config-only --sshd off
    [ "$status" = 0 ]
    [ ! -e "$DOTFILES_TEST_ROOT/ssh-calls" ]
    run sh "$REPO/bootstrap.sh" --manager sh
    [ "$status" = 0 ]
    [ ! -e "$DOTFILES_TEST_ROOT/ssh-calls" ]
    ! grep -q 'apk add openssh openrc' "$DOTFILES_TEST_ROOT/calls"
}

@test "SSH first OpenRC boot registers default and leaves runlevel untouched" {
    [ "$TEST_PLATFORM" = ish ] || skip 'iSH only'
    export TEST_RUNLEVEL=sysinit
    run sh "$REPO/bootstrap.sh" --prepare-sshd
    [ "$status" = 0 ]
    [[ "$output" == *'reopen iSH'* ]]
    [ -L "$DOTFILES_TEST_ROOT/etc/runlevels/default/dotfiles-sshd" ]
    [ ! -e "$DOTFILES_TEST_ROOT/ssh-running" ]
    ! grep -q 'rc-service .* start' "$DOTFILES_TEST_ROOT/ssh-calls"
}

@test "SSH config and host-key failures do not register or start a server" {
    [ "$TEST_PLATFORM" = ish ] || skip 'iSH only'
    export FAIL_HOST_KEYS=1
    run sh "$REPO/bootstrap.sh" --prepare-sshd
    [ "$status" != 0 ]
    [ ! -L "$DOTFILES_TEST_ROOT/etc/runlevels/default/dotfiles-sshd" ]
    export FAIL_HOST_KEYS=0 FAIL_SSH_CONFIG=1
    run sh "$REPO/bootstrap.sh" --prepare-sshd
    [ "$status" != 0 ]
    [ ! -L "$DOTFILES_TEST_ROOT/etc/runlevels/default/dotfiles-sshd" ]
    [ ! -e "$DOTFILES_TEST_ROOT/ssh-running" ]
}

@test "SSH generates only its missing Ed25519 key and preserves orphaned public keys" {
    [ "$TEST_PLATFORM" = ish ] || skip 'iSH only'
    run sh "$REPO/bootstrap.sh" --prepare-sshd
    [ "$status" = 0 ]
    [ -s "$DOTFILES_TEST_ROOT/etc/ssh/ssh_host_ed25519_key" ]
    [ -s "$DOTFILES_TEST_ROOT/etc/ssh/ssh_host_ed25519_key.pub" ]
    run sh "$REPO/bootstrap.sh" --prepare-sshd
    [ "$status" = 0 ]
    [ "$(grep -c '^ssh-keygen ' "$DOTFILES_TEST_ROOT/ssh-calls")" = 1 ]
    ! grep -q 'ssh-keygen -A' "$DOTFILES_TEST_ROOT/ssh-calls"
    rm "$DOTFILES_TEST_ROOT/etc/ssh/ssh_host_ed25519_key"
    run sh "$REPO/bootstrap.sh" --prepare-sshd
    [ "$status" != 0 ]
    [[ "$output" == *'public host key without its private key preserved'* ]]
    [ ! -f "$DOTFILES_TEST_ROOT/etc/ssh/ssh_host_ed25519_key" ]
}

@test "SSH startup failure preserves baseline and reports failure" {
    [ "$TEST_PLATFORM" = ish ] || skip 'iSH only'
    export FAIL_SSH_START=1
    run sh "$REPO/bootstrap.sh" --manager sh
    [ "$status" != 0 ]
    [ -f "$HOME/.profile" ]
    [[ "$output" == *'possibly port 22000 in use'* ]]
    ! grep -Eq ' stop| restart' "$DOTFILES_TEST_ROOT/ssh-calls"
}

@test "SSH refuses foreign service names, directories and symlinks" {
    [ "$TEST_PLATFORM" = ish ] || skip 'iSH only'
    mkdir -p "$DOTFILES_TEST_ROOT/etc/init.d"
    echo foreign >"$DOTFILES_TEST_ROOT/etc/init.d/dotfiles-sshd"
    run sh "$REPO/bootstrap.sh" --prepare-sshd
    [ "$status" != 0 ]
    [ "$(cat "$DOTFILES_TEST_ROOT/etc/init.d/dotfiles-sshd")" = foreign ]
    [ ! -e "$DOTFILES_TEST_ROOT/calls" ]
    rm "$DOTFILES_TEST_ROOT/etc/init.d/dotfiles-sshd"
    mkdir -p "$DOTFILES_TEST_ROOT/etc/ssh"
    ln -s "$BATS_TEST_TMPDIR/external" "$DOTFILES_TEST_ROOT/etc/ssh/dotfiles-lite"
    run sh "$REPO/bootstrap.sh" --prepare-sshd
    [ "$status" != 0 ]
    [ ! -e "$BATS_TEST_TMPDIR/external" ]
}

@test "SSH fixtures cannot fall through to a host key generator or daemon" {
    [ "$TEST_PLATFORM" = ish ] || skip 'iSH only'
    rm "$DOTFILES_TEST_ROOT/usr/bin/ssh-keygen"
    run sh "$REPO/bootstrap.sh" --prepare-sshd
    [ "$status" != 0 ]
    [[ "$output" == *'SSH prerequisite missing:'* ]]
    [ ! -e "$DOTFILES_TEST_ROOT/ssh-calls" ]
}

@test "SSH reports missing password without changing account or auth files" {
    [ "$TEST_PLATFORM" = ish ] || skip 'iSH only'
    echo 'root:!:0:0:99999:7:::' >"$DOTFILES_TEST_ROOT/etc/shadow"
    cp "$DOTFILES_TEST_ROOT/etc/shadow" "$BATS_TEST_TMPDIR/shadow-before"
    run sh "$REPO/bootstrap.sh" --prepare-sshd
    [ "$status" = 0 ]
    [[ "$output" == *'SSH login pending'* ]]
    cmp "$DOTFILES_TEST_ROOT/etc/shadow" "$BATS_TEST_TMPDIR/shadow-before"
    grep -q '^PermitEmptyPasswords no$' "$DOTFILES_TEST_ROOT/etc/ssh/dotfiles-lite/sshd_config"
    grep -q '^Subsystem sftp internal-sftp$' "$DOTFILES_TEST_ROOT/etc/ssh/dotfiles-lite/sshd_config"
    [ ! -f "$HOME/.ssh/authorized_keys" ]
}

@test "SSH and Finder init answers persist and apply does not restore stale data" {
    [ "$TEST_PLATFORM" = ish ] || skip 'iSH only'
    [ -n "$REAL_CHEZMOI" ] || skip 'chezmoi required'
    source_copy="$BATS_TEST_TMPDIR/ssh-init-source"
    mkdir -p "$source_copy"
    cp -R "$REPO/scripts" "$REPO/config" "$REPO/home" "$REPO/.chezmoiroot" "$source_copy/"
    run "$REAL_CHEZMOI" --config "$CHEZMOI_CONFIG" init --promptDefaults --source "$source_copy" --destination "$HOME" --apply
    [ "$status" = 0 ]
    [ "$(cat "$HOME/.local/state/dotfiles-lite/sshd")" = on ]
    [ "$(cat "$HOME/.local/state/dotfiles-lite/finder")" = on ]
    run sh "$source_copy/scripts/manage.sh" --prepare-sshd --sshd off
    [ "$status" = 0 ]
    run sh "$source_copy/scripts/manage.sh" --prepare-finder --finder off
    [ "$status" = 0 ]
    run "$REAL_CHEZMOI" --config "$CHEZMOI_CONFIG" apply
    [ "$status" = 0 ]
    [ "$(cat "$HOME/.local/state/dotfiles-lite/sshd")" = off ]
    [ "$(cat "$HOME/.local/state/dotfiles-lite/finder")" = off ]
    [ ! -L "$DOTFILES_TEST_ROOT/etc/runlevels/default/dotfiles-sshd" ]
    [ ! -L "$DOTFILES_TEST_ROOT/etc/runlevels/default/dotfiles-finder" ]
    run "$REAL_CHEZMOI" --config "$CHEZMOI_CONFIG" init --promptBool 'Enable iSH SSH server=true' --promptBool 'Mount iSH Finder files=true' --source "$source_copy" --destination "$HOME" --apply
    [ "$status" = 0 ]
    [ "$(cat "$HOME/.local/state/dotfiles-lite/sshd")" = on ]
    [ "$(cat "$HOME/.local/state/dotfiles-lite/finder")" = on ]
}

@test "Finder defaults on independently of SSH and mounts only once across setup runs" {
    [ "$TEST_PLATFORM" = ish ] || skip 'iSH only'
    run sh "$REPO/bootstrap.sh" --manager sh --sshd off
    [ "$status" = 0 ]
    [ "$(cat "$HOME/.local/state/dotfiles-lite/finder")" = on ]
    [ -x "$DOTFILES_TEST_ROOT/usr/local/libexec/dotfiles-finder" ]
    [ -L "$DOTFILES_TEST_ROOT/etc/runlevels/default/dotfiles-finder" ]
    [ ! -e "$DOTFILES_TEST_ROOT/etc/init.d/dotfiles-sshd" ]
    run sh "$REPO/bootstrap.sh" --prepare-finder
    [ "$status" = 0 ]
    [ "$(wc -l <"$DOTFILES_TEST_ROOT/finder-calls" | tr -d ' ')" = 1 ]
    [ "$(cat "$HOME/.local/state/dotfiles-lite/manager")" = sh ]
}

@test "Finder preserves a correct manual mount and disabling retains shared files" {
    [ "$TEST_PLATFORM" = ish ] || skip 'iSH only'
    mkdir -p "$DOTFILES_TEST_ROOT/mnt/finder"
    echo shared-file >"$DOTFILES_TEST_ROOT/mnt/finder/shared.txt"
    printf '/private%s %s real rw 0 0\n' "$(cat "$DOTFILES_TEST_ROOT/proc/ish/documents")" "$DOTFILES_TEST_ROOT/mnt/finder" >"$DOTFILES_TEST_ROOT/proc/mounts"
    cp "$DOTFILES_TEST_ROOT/proc/mounts" "$BATS_TEST_TMPDIR/mounts-before"
    run sh "$REPO/bootstrap.sh" --prepare-finder
    [ "$status" = 0 ]
    [ ! -f "$DOTFILES_TEST_ROOT/finder-calls" ]
    run sh "$REPO/bootstrap.sh" --prepare-finder --finder off
    [ "$status" = 0 ]
    [ ! -L "$DOTFILES_TEST_ROOT/etc/runlevels/default/dotfiles-finder" ]
    [ "$(cat "$DOTFILES_TEST_ROOT/mnt/finder/shared.txt")" = shared-file ]
    cmp "$DOTFILES_TEST_ROOT/proc/mounts" "$BATS_TEST_TMPDIR/mounts-before"
    [ -x "$DOTFILES_TEST_ROOT/usr/local/libexec/dotfiles-finder" ]
    ! grep -q 'rc-service .* stop' "$DOTFILES_TEST_ROOT/finder-service-calls"
}

@test "Finder refuses hidden contents, symlinks, foreign and nested mounts" {
    [ "$TEST_PLATFORM" = ish ] || skip 'iSH only'
    mkdir -p "$DOTFILES_TEST_ROOT/mnt/finder"
    echo keep >"$DOTFILES_TEST_ROOT/mnt/finder/.hidden"
    run sh "$REPO/bootstrap.sh" --prepare-finder
    [ "$status" != 0 ]
    [[ "$output" == *'Nonempty /mnt/finder preserved'* ]]
    [ ! -f "$DOTFILES_TEST_ROOT/calls" ]
    rm "$DOTFILES_TEST_ROOT/mnt/finder/.hidden"
    rmdir "$DOTFILES_TEST_ROOT/mnt/finder"
    ln -s "$BATS_TEST_TMPDIR/external" "$DOTFILES_TEST_ROOT/mnt/finder"
    run sh "$REPO/bootstrap.sh" --prepare-finder
    [ "$status" != 0 ]
    [ ! -e "$BATS_TEST_TMPDIR/external" ]
    rm "$DOTFILES_TEST_ROOT/mnt/finder"
    mkdir "$DOTFILES_TEST_ROOT/mnt/finder"
    for target in "$DOTFILES_TEST_ROOT/mnt/finder" "$DOTFILES_TEST_ROOT/mnt/finder/nested"; do
        printf '/foreign %s real rw 0 0\n' "$target" >"$DOTFILES_TEST_ROOT/proc/mounts"
        run sh "$REPO/bootstrap.sh" --prepare-finder
        [ "$status" != 0 ]
        [[ "$output" == *'Existing mount at or below /mnt/finder preserved'* ]]
    done
    [ ! -f "$DOTFILES_TEST_ROOT/finder-calls" ]
    [ ! -e "$DOTFILES_TEST_ROOT/etc/init.d/dotfiles-finder" ]
}

@test "Finder boot helper rereads relocated Documents without depending on the checkout" {
    [ "$TEST_PLATFORM" = ish ] || skip 'iSH only'
    run sh "$REPO/bootstrap.sh" --prepare-finder
    [ "$status" = 0 ]
    : >"$DOTFILES_TEST_ROOT/proc/mounts"
    printf '%s\n' '/var/mobile/Containers/Data/Application/new id\literal/Documents' >"$DOTFILES_TEST_ROOT/proc/ish/documents"
    run env DOTFILES_REPO=/nonexistent sh "$DOTFILES_TEST_ROOT/usr/local/libexec/dotfiles-finder" mount
    [ "$status" = 0 ]
    run sh "$DOTFILES_TEST_ROOT/usr/local/libexec/dotfiles-finder" status
    [ "$status" = 0 ]
    [ "$(wc -l <"$DOTFILES_TEST_ROOT/finder-calls" | tr -d ' ')" = 2 ]
    grep -Fq 'new id\literal/Documents' "$DOTFILES_TEST_ROOT/finder-calls"
}

@test "Finder mount failures and missing fixture mount cannot activate autostart" {
    [ "$TEST_PLATFORM" = ish ] || skip 'iSH only'
    export FAIL_FINDER_MOUNT=1
    run sh "$REPO/bootstrap.sh" --prepare-finder
    [ "$status" != 0 ]
    [ ! -L "$DOTFILES_TEST_ROOT/etc/runlevels/default/dotfiles-finder" ]
    rm "$DOTFILES_TEST_ROOT/bin/mount" "$DOTFILES_TEST_ROOT/finder-calls"
    run sh "$REPO/bootstrap.sh" --prepare-finder
    [ "$status" != 0 ]
    [[ "$output" == *'Finder prerequisite missing:'* ]]
    [ ! -f "$DOTFILES_TEST_ROOT/finder-calls" ]
    [ ! -L "$DOTFILES_TEST_ROOT/etc/runlevels/default/dotfiles-finder" ]
}

@test "Finder dry-run, config-only and saved off do not mount or register" {
    [ "$TEST_PLATFORM" = ish ] || skip 'iSH only'
    run sh "$REPO/bootstrap.sh" --prepare-finder --dry-run
    [ "$status" = 0 ]
    [ ! -e "$HOME/.local/state/dotfiles-lite/finder" ]
    run sh "$REPO/bootstrap.sh" --manager sh --config-only --finder off
    [ "$status" = 0 ]
    run sh "$REPO/bootstrap.sh" --prepare-finder
    [ "$status" = 0 ]
    [ "$(cat "$HOME/.local/state/dotfiles-lite/finder")" = off ]
    [ ! -f "$DOTFILES_TEST_ROOT/finder-calls" ]
    [ ! -e "$DOTFILES_TEST_ROOT/etc/init.d/dotfiles-finder" ]
}

@test "OpenWrt rejects SSH server options without target changes" {
    [ "$TEST_PLATFORM" = openwrt ] || skip 'OpenWrt only'
    run sh "$REPO/bootstrap.sh" --sshd on
    [ "$status" != 0 ]
    [ ! -e "$DOTFILES_TEST_ROOT/calls" ]
    run sh "$REPO/bootstrap.sh" --prepare-sshd
    [ "$status" != 0 ]
    [ ! -e "$DOTFILES_TEST_ROOT/calls" ]
}

@test "OpenWrt rejects Finder mount options without target changes" {
    [ "$TEST_PLATFORM" = openwrt ] || skip 'OpenWrt only'
    run sh "$REPO/bootstrap.sh" --finder on
    [ "$status" != 0 ]
    run sh "$REPO/bootstrap.sh" --prepare-finder
    [ "$status" != 0 ]
    [ ! -e "$DOTFILES_TEST_ROOT/calls" ]
    [ ! -e "$DOTFILES_TEST_ROOT/mnt/finder" ]
}


make_git_fixture() {
    export DOTFILES_TEST_GIT_REMOTE="$BATS_TEST_TMPDIR/upstream"
    mkdir -p "$DOTFILES_TEST_GIT_REMOTE"
    cp -R "$REPO/scripts" "$REPO/config" "$REPO/home" "$REPO/.chezmoiroot" "$DOTFILES_TEST_GIT_REMOTE/"
    git init -q "$DOTFILES_TEST_GIT_REMOTE"
    git -C "$DOTFILES_TEST_GIT_REMOTE" checkout -q -b main
    git -C "$DOTFILES_TEST_GIT_REMOTE" add .
    git -C "$DOTFILES_TEST_GIT_REMOTE" commit -qm initial
    source_copy="$BATS_TEST_TMPDIR/source with ' quote"
    mkdir -p "$source_copy"
    cp -R "$DOTFILES_TEST_GIT_REMOTE/." "$source_copy/"
    rm -rf "$source_copy/.git"
}

@test "snapshot migrates to tracking Git then plain chezmoi update pulls and applies" {
    [ -n "$REAL_CHEZMOI" ] || skip 'chezmoi not installed on test host'
    make_git_fixture
    echo custom-source-note >"$source_copy/personal-note"
    run sh "$source_copy/scripts/manage.sh" --package-network direct
    [ "$status" = 0 ]
    [ "$(git -C "$source_copy" symbolic-ref --short HEAD)" = main ]
    [ "$(git -C "$source_copy" rev-parse --abbrev-ref '@{u}')" = origin/main ]
    [ -z "$(git -C "$source_copy" status --porcelain)" ]
    [ "$(cat "$BATS_TEST_TMPDIR"/.dotfiles-*.snapshot.*/source/personal-note)" = custom-source-note ]
    [ "$(cat "$HOME/.local/state/dotfiles-lite/manager")" = chezmoi ]
    [ "$(cat "$HOME/.local/state/dotfiles-lite/package-network")" = direct ]
    printf '\nexport DOTFILES_UPDATE_TEST=updated\n' >>"$DOTFILES_TEST_GIT_REMOTE/home/dot_config/dotfiles-lite/profile.sh"
    git -C "$DOTFILES_TEST_GIT_REMOTE" add .
    git -C "$DOTFILES_TEST_GIT_REMOTE" commit -qm update
    run "$REAL_CHEZMOI" update --no-pager
    [ "$status" = 0 ]
    grep -q DOTFILES_UPDATE_TEST=updated "$HOME/.config/dotfiles-lite/profile.sh"
    [ "$(git -C "$source_copy" rev-parse HEAD)" = "$(git -C "$DOTFILES_TEST_GIT_REMOTE" rev-parse HEAD)" ]
    # A one-command connectivity override must not replace the saved policy.
    run env DOTFILES_PACKAGE_NETWORK=inherit "$REAL_CHEZMOI" apply
    [ "$status" = 0 ]
    [ "$(cat "$HOME/.local/state/dotfiles-lite/package-network")" = direct ]
    # A local source edit conflicting with upstream must survive a failed update.
    printf 'local-edit\n' >"$source_copy/home/dot_config/dotfiles-lite/prompt.sh"
    printf '\n# upstream-change\n' >>"$DOTFILES_TEST_GIT_REMOTE/home/dot_config/dotfiles-lite/prompt.sh"
    git -C "$DOTFILES_TEST_GIT_REMOTE" add .
    git -C "$DOTFILES_TEST_GIT_REMOTE" commit -qm conflict
    cp "$HOME/.config/dotfiles-lite/prompt.sh" "$BATS_TEST_TMPDIR/prompt-before"
    run "$REAL_CHEZMOI" update --no-pager
    [ "$status" != 0 ]
    [ "$(cat "$source_copy/home/dot_config/dotfiles-lite/prompt.sh")" = local-edit ]
    cmp "$HOME/.config/dotfiles-lite/prompt.sh" "$BATS_TEST_TMPDIR/prompt-before"
    # An offline pull must fail before the application hook can alter HOME.
    git -C "$source_copy" remote set-url origin "$BATS_TEST_TMPDIR/missing"
    cp "$HOME/.profile" "$BATS_TEST_TMPDIR/profile-before"
    run "$REAL_CHEZMOI" update --no-pager
    [ "$status" != 0 ]
    cmp "$HOME/.profile" "$BATS_TEST_TMPDIR/profile-before"
}

@test "failed Git acquisition preserves snapshot and leaves home unconfigured" {
    [ -n "$REAL_CHEZMOI" ] || skip 'chezmoi not installed on test host'
    make_git_fixture
    export DOTFILES_TEST_GIT_REMOTE="$BATS_TEST_TMPDIR/missing"
    echo preserved >"$source_copy/personal-note"
    run sh "$source_copy/scripts/manage.sh"
    [ "$status" != 0 ]
    [ "$(cat "$source_copy/personal-note")" = preserved ]
    [ ! -e "$source_copy/.git" ]
    [ ! -e "$HOME/.profile" ]
}

@test "legacy same-source config gains update command and preserves custom settings" {
    [ -n "$REAL_CHEZMOI" ] || skip 'chezmoi not installed on test host'
    mkdir -p "$(dirname "$CHEZMOI_CONFIG")"
    printf 'sourceDir = "%s"\n# personal comment\n[data]\n personal = "value"\n' "$REPO" >"$CHEZMOI_CONFIG"
    run sh "$REPO/bootstrap.sh" --config-only
    [ "$status" = 0 ]
    grep -q '# personal comment' "$CHEZMOI_CONFIG"
    grep -q '^\[update\]' "$CHEZMOI_CONFIG"
    run "$REAL_CHEZMOI" execute-template '{{ .personal }}'
    [ "$status" = 0 ]
    [ "$output" = value ]
    cp "$CHEZMOI_CONFIG" "$BATS_TEST_TMPDIR/config-first"
    run sh "$REPO/bootstrap.sh" --config-only
    [ "$status" = 0 ]
    cmp "$CHEZMOI_CONFIG" "$BATS_TEST_TMPDIR/config-first"
}

@test "custom chezmoi update command is preserved" {
    [ -n "$REAL_CHEZMOI" ] || skip 'chezmoi not installed on test host'
    mkdir -p "$(dirname "$CHEZMOI_CONFIG")"
    printf 'sourceDir = "%s"\n[update]\n command = "custom-update"\n' "$REPO" >"$CHEZMOI_CONFIG"
    cp "$CHEZMOI_CONFIG" "$BATS_TEST_TMPDIR/config-before"
    run sh "$REPO/bootstrap.sh" --config-only
    [ "$status" = 0 ]
    cmp "$CHEZMOI_CONFIG" "$BATS_TEST_TMPDIR/config-before"
}


@test "sh to chezmoi migration preserves a locally edited managed file" {
    [ -n "$REAL_CHEZMOI" ] || skip 'chezmoi not installed on test host'
    run sh "$REPO/bootstrap.sh" --manager sh --config-only
    [ "$status" = 0 ]
    printf '# intentional local change\n' >>"$HOME/.config/dotfiles-lite/profile.sh"
    cp "$HOME/.config/dotfiles-lite/profile.sh" "$BATS_TEST_TMPDIR/local-edit"
    run sh "$REPO/bootstrap.sh" --config-only
    [ "$status" != 0 ]
    cmp "$HOME/.config/dotfiles-lite/profile.sh" "$BATS_TEST_TMPDIR/local-edit"
    [ "$(cat "$HOME/.local/state/dotfiles-lite/manager")" = sh ]
}
