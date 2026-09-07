#!/bin/sh
# Shared with dotfiles-OpenWrt/scripts/core.sh. Keep the two copies identical.
# Source from an entrypoint with DOTFILES_REPO set. No work at source time.

say() { printf '[dotfiles] %s\n' "$*"; }
warn() { printf '[dotfiles] %s\n' "$*" >&2; }
die() { warn "$*"; exit 1; }

context() {
    REPO=$(CDPATH='' cd "$DOTFILES_REPO" && pwd -P)
    PLATFORM=$(cat "$REPO/config/platform")
    STATE="$HOME/.local/state/dotfiles-lite"
    SYSROOT=''
    if [ -n "${DOTFILES_TEST_ROOT:-}" ]; then
        [ "${DOTFILES_TEST_MODE:-}" = fixture-only-v1 ] || die 'Test root requires fixture-only-v1'
        case "$DOTFILES_TEST_ROOT" in /*) ;; *) die 'Test root must be absolute' ;; esac
        [ "$DOTFILES_TEST_ROOT" != / ] && [ -f "$DOTFILES_TEST_ROOT/.fixture" ] || die 'Invalid fixture root'
        [ "$HOME" = "$DOTFILES_TEST_ROOT/home" ] || die 'Fixture HOME must be isolated'
        SYSROOT=$DOTFILES_TEST_ROOT
    fi
    [ "$(uname -s)" = Linux ] || die 'This repository requires its native Linux target; use tests for host validation.'
    ARCH=$(uname -m)
    case "$PLATFORM" in
        ish)
            [ -d "$SYSROOT/proc/ish" ] || die 'Not iSH: /proc/ish is absent (ordinary Alpine is not iSH).'
            case "$ARCH" in i386|i486|i586|i686) ARCH=i386 ;; *) die "Unsupported iSH architecture: $ARCH" ;; esac
            command -v apk >/dev/null 2>&1 || die 'iSH requires apk'
            PM=apk ;;
        openwrt)
            [ -f "$SYSROOT/etc/openwrt_release" ] || die 'Not OpenWrt/ImmortalWrt: /etc/openwrt_release is absent.'
            case "$ARCH" in aarch64|arm64) ARCH=arm64 ;; x86_64|amd64) ARCH=amd64 ;; esac
            if command -v apk >/dev/null 2>&1; then PM=apk
            elif command -v opkg >/dev/null 2>&1; then PM=opkg
            else die 'Neither apk nor opkg is available'; fi ;;
        *) die "Unknown platform: $PLATFORM" ;;
    esac
    PATH="$HOME/.local/bin:$PATH"
    export PATH
}

branch_description() {
    if [ ! -r "$SYSROOT/etc/apk/repositories" ]; then printf '%s\n' unknown; return; fi
    awk '
        /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
        { n=split($0,a,"/"); for(i=1;i<=n;i++) if(a[i] ~ /^v[0-9]+\.[0-9]+([-][0-9-]+)?$/ || a[i]=="edge") {
            if(!seen[a[i]]++) { if(found++) printf ", "; printf "%s",a[i] }; break
        }}
        END { if(!found) printf "unknown (custom repository URL)"; printf "\n" }
    ' "$SYSROOT/etc/apk/repositories"
}

load_network_preferences() {
    if [ -z "$PACKAGE_NETWORK" ]; then PACKAGE_NETWORK=$(cat "$STATE/package-network" 2>/dev/null || printf inherit); fi
    if [ -z "$SOURCE_NETWORK" ]; then SOURCE_NETWORK=$(cat "$STATE/source-network" 2>/dev/null || printf inherit); fi
    case "$PACKAGE_NETWORK" in inherit|direct) ;; *) die 'Expected --package-network inherit|direct' ;; esac
    case "$SOURCE_NETWORK" in
        inherit|direct) ;;
        proxy) [ "$PLATFORM" = openwrt ] || die '--source-network proxy requires OpenWrt Nikki; use inherited proxy variables on iSH.' ;;
        *) die 'Expected --source-network inherit|direct|proxy' ;;
    esac
}

source_command() (
    case "${SOURCE_NETWORK:-inherit}" in
        direct)
            unset http_proxy https_proxy all_proxy ftp_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY FTP_PROXY no_proxy NO_PROXY
            no_proxy='*'; NO_PROXY='*'; export no_proxy NO_PROXY ;;
        proxy) exec sh "$REPO/home/dot_local/bin/executable_netrun" proxy -- "$@" ;;
    esac
    exec "$@"
)

ensure_git_source() (
    command -v git >/dev/null 2>&1 || { warn 'Git is required for chezmoi update'; exit 1; }
    [ ! -e "$REPO/.git" ] && [ ! -L "$REPO/.git" ] || { warn 'Existing Git metadata preserved'; exit 1; }
    case "$PLATFORM" in ish) repository=dotfiles-iSH ;; openwrt) repository=dotfiles-OpenWrt ;; esac
    remote="https://github.com/daviddwlee84/$repository.git"
    # Offline integration fixtures cannot redirect a real device's upstream.
    if [ -n "$SYSROOT" ] && [ -n "${DOTFILES_TEST_GIT_REMOTE:-}" ]; then
        case "$DOTFILES_TEST_GIT_REMOTE" in /*) remote=$DOTFILES_TEST_GIT_REMOTE ;; *) exit 1 ;; esac
    fi
    ref=${DOTFILES_REF:-main}
    case "$ref" in ''|*[!a-zA-Z0-9._-]*) warn 'DOTFILES_REF must be a simple branch, tag or commit'; exit 1 ;; esac
    git_tmp=$(mktemp -d "$(dirname "$REPO")/.${repository}.git.XXXXXX")
    trap 'rm -rf "$git_tmp"' EXIT HUP INT TERM
    git init -q "$git_tmp/source" || exit 1
    git -C "$git_tmp/source" remote add origin "$remote" || exit 1
    say "Creating Git source for $repository ($ref)"
    source_command git -C "$git_tmp/source" fetch --depth=1 origin "$ref" || exit 1
    if [ "$ref" = main ]; then
        git -C "$git_tmp/source" checkout -q -B main FETCH_HEAD || exit 1
        git -C "$git_tmp/source" config branch.main.remote origin || exit 1
        git -C "$git_tmp/source" config branch.main.merge refs/heads/main || exit 1
    else
        git -C "$git_tmp/source" checkout -q --detach FETCH_HEAD || exit 1
        warn 'Pinned source: switch to a tracking branch before using chezmoi update.'
    fi
    [ -f "$git_tmp/source/scripts/manage.sh" ] && [ "$(cat "$git_tmp/source/config/platform")" = "$PLATFORM" ] || exit 1
    backup=$(mktemp -d "$(dirname "$REPO")/.${repository}.snapshot.XXXXXX")
    mv "$REPO" "$backup/source" || exit 1
    if ! mv "$git_tmp/source" "$REPO"; then mv "$backup/source" "$REPO"; exit 1; fi
    say "Previous snapshot (including any custom source files) preserved at $backup/source"
)

fetch() {
    if command -v curl >/dev/null 2>&1; then source_command curl -fLsS --connect-timeout 15 --max-time 180 -o "$2" "$1"
    elif command -v wget >/dev/null 2>&1; then source_command wget -T 180 -O "$2" "$1"
    elif command -v uclient-fetch >/dev/null 2>&1; then source_command uclient-fetch -T 180 -O "$2" "$1"
    else warn 'Need curl, wget or uclient-fetch'; return 1; fi
}

sha256_file() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
    else warn 'A SHA-256 verifier is required'; return 1; fi
}

probe() {
    command -v timeout >/dev/null 2>&1 || { warn 'timeout is required (OpenWrt: install coreutils-timeout) for bounded binary checks'; return 1; }
    timeout 15 "$1" --version >/dev/null 2>&1
}

# The Alpine 3.14 chezmoi package runs, but predates .chezmoiroot/workingTree.
# Test the capability used by our source instead of treating --version as enough.
tool_ready() (
    tool_name=$1
    binary=$2
    probe "$binary" || exit 1
    if [ "$tool_name" = chezmoi ]; then
        capability=$(timeout 15 "$binary" execute-template '{{ if hasKey .chezmoi "workingTree" }}supported{{ end }}' 2>/dev/null) || exit 1
        [ "$capability" = supported ] || exit 1
    fi
)

install_asset() (
    tool=$1
    if command -v "$tool" >/dev/null 2>&1 && tool_ready "$tool" "$(command -v "$tool")"; then
        say "$tool already runs; keeping the installed version (install-only)."
        exit 0
    fi
    row=$(awk -F '|' -v t="$tool" -v a="$ARCH" '$1==t && $2==a {print}' "$REPO/config/assets.lock")
    [ -n "$row" ] || { warn "$tool has no locked release for $ARCH"; exit 1; }
    IFS='|' read -r _tool _arch version url digest format member bytes <<EOF
$row
EOF
    say "$tool $version ($ARCH); checking storage before download"
    asset_tmp=$(mktemp -d)
    trap 'rm -rf "$asset_tmp"' EXIT HUP INT TERM
    for location in "$HOME" "$asset_tmp"; do
        available=$(df -Pk "$location" | awk 'END {print $4}')
        required=$((bytes * 4 / 1024 + 16384))
        case "$available" in ''|*[!0-9]*) warn 'Cannot measure available storage'; exit 1 ;; esac
        [ "$available" -ge "$required" ] || { warn "$tool needs at least $required KiB staging space at $location; available $available KiB"; exit 1; }
    done
    fetch "$url" "$asset_tmp/download" || exit 1
    actual=$(sha256_file "$asset_tmp/download") || exit 1
    [ "$actual" = "$digest" ] || { warn "$tool checksum mismatch; installed binary preserved"; exit 1; }
    case "$format" in
        raw) cp "$asset_tmp/download" "$asset_tmp/candidate" ;;
        tar.gz) tar -xzOf "$asset_tmp/download" "$member" >"$asset_tmp/candidate" || exit 1 ;;
        *) warn "Unknown archive format: $format"; exit 1 ;;
    esac
    chmod 755 "$asset_tmp/candidate"
    tool_ready "$tool" "$asset_tmp/candidate" || { warn "$tool failed its bounded compatibility check; not installed"; exit 1; }
    mkdir -p "$HOME/.local/bin"
    [ ! -L "$HOME/.local/bin/$tool" ] || { warn "Refusing to replace symlink: $tool"; exit 1; }
    # Same-filesystem rename keeps a previous executable intact on copy failure.
    staged=$(mktemp "$HOME/.local/bin/.$tool.XXXXXX")
    cp "$asset_tmp/candidate" "$staged" && chmod 755 "$staged" && mv "$staged" "$HOME/.local/bin/$tool" || {
        rm -f "$staged"; exit 1;
    }
    say "$tool installed; interactive/device verification is still required."
)

package_present() {
    case "$PM" in
        apk) apk info -e "$1" >/dev/null 2>&1 ;;
        opkg) opkg status "$1" 2>/dev/null | grep -q '^Status: .* installed$' ;;
    esac
}

install_packages() (
    # Explicit per-stage choice: native OpenWrt apk-fetch/wget does not support
    # this authenticated proxy in the same way curl does. Never switch silently.
    if [ "${PACKAGE_NETWORK:-inherit}" = direct ]; then
        unset http_proxy https_proxy all_proxy ftp_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY FTP_PROXY no_proxy NO_PROXY
        no_proxy='*'; NO_PROXY='*'
        export no_proxy NO_PROXY
    fi
    manifest=$1
    missing=''
    while IFS= read -r package || [ -n "$package" ]; do
        case "$package" in ''|'#'*) continue ;; esac
        package_present "$package" || missing="$missing $package"
    done <"$manifest"
    [ -n "$missing" ] || { say 'Requested packages are already installed.'; exit 0; }
    [ "$(id -u)" = 0 ] || { warn 'Package installation requires root; use --config-only for home configuration.'; exit 1; }
    say "$PM install:$missing"
    "$PM" update || { warn 'Index refresh failed; trying existing cached indexes.'; }
    # Names come only from the repository-owned manifest, never shell input.
    # shellcheck disable=SC2086
    case "$PM" in apk) apk add $missing ;; opkg) opkg install $missing ;; esac
)

validate_options() {
    for option in $WITH; do
        case "$option" in
            dev|starship) ;;
            herdr|specstory|codex) [ "$PLATFORM" = openwrt ] || die "$option is remote-only on iSH; no local installer is offered." ;;
            *) die "Unknown optional group/tool: $option" ;;
        esac
    done
}

packages() {
    [ "$PLATFORM" != ish ] || say "Alpine repositories: $(branch_description); keeping current feeds."
    install_packages "$REPO/config/packages-base.txt" || return 1
    OPTIONAL_FAILED=0
    for option in $WITH; do
        case "$option" in
            dev) install_packages "$REPO/config/packages-dev.txt" || OPTIONAL_FAILED=1 ;;
            starship)
                if install_packages "$REPO/config/packages-starship.txt"; then
                    if [ "$PLATFORM" = ish ]; then
                        probe "$(command -v starship)" || OPTIONAL_FAILED=1
                    else install_asset starship || OPTIONAL_FAILED=1; fi
                else OPTIONAL_FAILED=1; fi ;;
            codex)
                warn 'Codex is experimental on OpenWrt. Check free RAM; no swap or sandbox policy is changed.'
                if install_packages "$REPO/config/packages-codex.txt"; then
                    install_asset codex || OPTIONAL_FAILED=1
                else OPTIONAL_FAILED=1; fi ;;
            herdr|specstory) install_asset "$option" || OPTIONAL_FAILED=1 ;;
        esac
    done
    export OPTIONAL_FAILED
    # Explicit optional failures do not prevent configuration of the baseline.
    return 0
}

choose_manager() {
    SELECTED=$MANAGER
    [ "$SELECTED" != auto ] || SELECTED=chezmoi
    if [ "$SELECTED" = chezmoi ]; then
        if ! command -v chezmoi >/dev/null 2>&1 || ! tool_ready chezmoi "$(command -v chezmoi)"; then
            [ "$CONFIG_ONLY" = 0 ] && install_asset chezmoi || die 'chezmoi unavailable. Retry explicitly with --manager sh.'
        fi
    fi
    [ "$PLATFORM:$SELECTED" != ish:chezmoi ] || warn 'iSH chezmoi support is experimental; a successful version check does not prove emulator stability.'
    say "Configuration manager: $SELECTED"
}

apply_sh() (
    # Only this explicit, reviewed manifest is deployed. Metadata never enters HOME.
    apply_tmp=$(mktemp -d)
    trap 'rm -rf "$apply_tmp"' EXIT HUP INT TERM
    while IFS='|' read -r kind source target mode; do
        case "$kind" in ''|'#'*) continue ;; esac
        dest="$HOME/$target"
        case "$target" in /*|*..*) warn 'Invalid target in files.list'; exit 1 ;; esac
        [ ! -L "$dest" ] || { warn "Refusing symlink target: $dest"; exit 1; }
        [ ! -e "$dest" ] || [ -f "$dest" ] || { warn "Not a regular target: $dest"; exit 1; }
        if [ "$kind" = seed ] && [ -e "$dest" ]; then continue; fi
        mkdir -p "$apply_tmp/$(dirname "$target")"
        case "$kind" in
            modify)
                if [ -f "$dest" ]; then sh "$REPO/$source" <"$dest" >"$apply_tmp/$target"
                else sh "$REPO/$source" </dev/null >"$apply_tmp/$target"; fi || exit 1 ;;
            managed|seed) cp "$REPO/$source" "$apply_tmp/$target" || exit 1 ;;
            *) warn "Unknown file mode: $kind"; exit 1 ;;
        esac
        if [ "$kind" = managed ] && [ -f "$dest" ] && ! cmp -s "$dest" "$apply_tmp/$target"; then
            if [ ! -f "$STATE/managed/$target" ] || ! cmp -s "$dest" "$STATE/managed/$target"; then
                warn "Local edit/conflict preserved: $dest. Review with diff before applying."
                exit 1
            fi
        fi
        chmod "$mode" "$apply_tmp/$target"
    done <"$REPO/config/files.list"
    while IFS='|' read -r kind source target mode; do
        case "$kind" in ''|'#'*) continue ;; esac
        [ -f "$apply_tmp/$target" ] || continue
        dest="$HOME/$target"
        mkdir -p "$(dirname "$dest")"
        [ "$target" != .ssh/config ] || chmod 700 "$HOME/.ssh"
        staged=$(mktemp "$(dirname "$dest")/.dotfiles.XXXXXX")
        cp "$apply_tmp/$target" "$staged" && chmod "$mode" "$staged" && mv "$staged" "$dest" || {
            rm -f "$staged"; exit 1;
        }
        if [ "$kind" = managed ]; then
            mkdir -p "$STATE/managed/$(dirname "$target")"
            cp "$apply_tmp/$target" "$STATE/managed/$target"
        fi
    done <"$REPO/config/files.list"
)

upgrade_update_config() {
    has_update=$(chezmoi --config "$config" execute-template '{{ if hasKey (fromToml (include .chezmoi.configFile)) "update" }}yes{{ else }}no{{ end }}') || return 1
    [ "$has_update" = no ] || return 0
    [ ! -L "$config" ] || { warn 'chezmoi config symlink preserved; add the update command to its source manually.'; return 1; }
    backup_config=$(mktemp "$(dirname "$config")/.chezmoi-before-git-update.XXXXXX")
    cp "$config" "$backup_config" && chmod 600 "$backup_config" || return 1
    config_tmp=$(mktemp "$(dirname "$config")/.dotfiles-update.XXXXXX")
    cp "$backup_config" "$config_tmp"
    printf '\n' >>"$config_tmp"
    if ! chezmoi --config "$config" execute-template --source "$REPO" --destination "$HOME" <"$REPO/config/chezmoi-update.toml.tmpl" >>"$config_tmp"; then
        rm -f "$config_tmp"; return 1
    fi
    if ! cmp -s "$config" "$backup_config"; then
        rm -f "$config_tmp"; warn 'chezmoi config changed concurrently; preserving it'; return 1
    fi
    chmod 600 "$config_tmp" && mv "$config_tmp" "$config" || return 1
    say "Added chezmoi update command; previous config retained at $backup_config"
}

check_sh_migration() {
    [ "$(cat "$STATE/manager" 2>/dev/null || true)" = sh ] || return 0
    while IFS='|' read -r kind source target mode; do
        [ "$kind" = managed ] || continue
        dest="$HOME/$target"
        [ ! -L "$dest" ] || { warn "Local symlink preserved: $dest"; return 1; }
        [ -f "$dest" ] || continue
        if ! cmp -s "$dest" "$REPO/$source"; then
            if [ ! -f "$STATE/managed/$target" ] || ! cmp -s "$dest" "$STATE/managed/$target"; then
                warn "Local edit preserved during sh migration: $dest. Move your override to local.sh or edit the source first."
                return 1
            fi
        fi
    done <"$REPO/config/files.list"
}

apply_chezmoi() {
    check_sh_migration || return 1
    config=${CHEZMOI_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/chezmoi/chezmoi.toml}
    if [ -f "$config" ]; then
        source_path=$(chezmoi --config "$config" source-path) || return 1
        source_path=$(CDPATH='' cd "$source_path" && pwd -P) || return 1
        case "$source_path" in "$REPO"|"$REPO/home") ;; *)
            warn "Existing chezmoi source preserved: $source_path. Use --manager sh or explicitly migrate it."
            return 1 ;;
        esac
        upgrade_update_config || return 1
        chezmoi --config "$config" apply --source "$REPO" --destination "$HOME" --exclude=scripts || return 1
    else
        # Render config without init: Git is prepared above; config-only stays offline.
        mkdir -p "$(dirname "$config")"
        config_tmp=$(mktemp "$(dirname "$config")/.dotfiles-chezmoi.XXXXXX")
        if ! chezmoi --config "$config" execute-template --source "$REPO" --destination "$HOME" <"$REPO/home/.chezmoi.toml.tmpl" >"$config_tmp"; then
            rm -f "$config_tmp"; return 1
        fi
        chmod 600 "$config_tmp"
        if ! chezmoi --config "$config_tmp" --config-format toml apply --source "$REPO" --destination "$HOME" --exclude=scripts; then
            rm -f "$config_tmp"; return 1
        fi
        # Do not clobber a configuration created concurrently by another writer.
        if ! (umask 077; set -C; cat "$config_tmp" >"$config"); then
            rm -f "$config_tmp"; return 1
        fi
        rm -f "$config_tmp"
    fi
    # Enables a later explicit sh switch without clobbering intervening local edits.
    while IFS='|' read -r kind source target mode; do
        [ "$kind" = managed ] || continue
        mkdir -p "$STATE/managed/$(dirname "$target")"
        cp "$HOME/$target" "$STATE/managed/$target"
    done <"$REPO/config/files.list"
}

record_state() {
    mkdir -p "$STATE"
    printf '%s\n' "$SELECTED" >"$STATE/manager"
    printf '%s\n' "$WITH" >"$STATE/options"
    # Direct chezmoi commands may have one-shot environment overrides. Only
    # explicit setup persists connectivity choices, never the post-apply hook.
    if [ "${ACTION:-setup}" != record ]; then
        printf '%s\n' "$SOURCE_NETWORK" >"$STATE/source-network"
        printf '%s\n' "$PACKAGE_NETWORK" >"$STATE/package-network"
    fi
}

doctor() {
    say "Platform=$PLATFORM arch=$ARCH package-manager=$PM"
    [ "$PLATFORM" != ish ] || say "Alpine repositories: $(branch_description)"
    say "Manager: $(cat "$STATE/manager" 2>/dev/null || printf unconfigured)"
    if [ -r "$SYSROOT/proc/meminfo" ]; then awk '/^MemTotal:|^MemAvailable:/ {print}' "$SYSROOT/proc/meminfo"; fi
    df -Pk "$HOME"
    failed=0
    for tool in git ssh tmux curl; do
        if command -v "$tool" >/dev/null 2>&1; then say "$tool: $(command -v "$tool")"
        else warn "$tool: missing"; failed=1; fi
    done
    for tool in chezmoi starship herdr specstory codex; do
        if command -v "$tool" >/dev/null 2>&1; then
            if tool_ready "$tool" "$(command -v "$tool")"; then say "$tool: compatibility probe passed; device workflow unverified"
            else warn "$tool: compatibility probe failed"; failed=1; fi
        else say "$tool: not installed"; fi
    done
    return "$failed"
}
