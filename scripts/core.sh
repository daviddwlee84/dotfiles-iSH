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

fetch() {
    if command -v curl >/dev/null 2>&1; then curl -fLsS --connect-timeout 15 --max-time 180 -o "$2" "$1"
    elif command -v wget >/dev/null 2>&1; then wget -T 180 -O "$2" "$1"
    elif command -v uclient-fetch >/dev/null 2>&1; then uclient-fetch -T 180 -O "$2" "$1"
    else warn 'Need curl, wget or uclient-fetch'; return 1; fi
}

sha256_file() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
    else warn 'A SHA-256 verifier is required'; return 1; fi
}

probe() {
    command -v timeout >/dev/null 2>&1 || { warn 'BusyBox timeout is required for bounded binary checks'; return 1; }
    timeout 15 "$1" --version >/dev/null 2>&1
}

install_asset() (
    tool=$1
    if command -v "$tool" >/dev/null 2>&1 && probe "$(command -v "$tool")"; then
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
    probe "$asset_tmp/candidate" || { warn "$tool failed its bounded --version check; not installed"; exit 1; }
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
            dev) ;;
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
    if [ "$SELECTED" = auto ] && [ -r "$STATE/manager" ]; then SELECTED=$(cat "$STATE/manager"); fi
    case "$SELECTED" in auto|chezmoi|sh) ;; *) die 'Invalid stored/requested manager' ;; esac
    if [ "$SELECTED" = auto ]; then
        if [ "$PLATFORM" = ish ]; then SELECTED='sh'
        elif command -v chezmoi >/dev/null 2>&1 && probe "$(command -v chezmoi)"; then SELECTED=chezmoi
        elif [ "$CONFIG_ONLY" = 0 ] && install_asset chezmoi; then SELECTED=chezmoi
        else SELECTED='sh'; warn 'chezmoi unavailable; first setup will use sh before any configuration writes.'; fi
    elif [ "$SELECTED" = chezmoi ]; then
        if ! command -v chezmoi >/dev/null 2>&1 || ! probe "$(command -v chezmoi)"; then
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

apply_chezmoi() {
    config=${CHEZMOI_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/chezmoi/chezmoi.toml}
    if [ -f "$config" ]; then
        source_path=$(chezmoi --config "$config" source-path) || return 1
        source_path=$(CDPATH='' cd "$source_path" && pwd -P) || return 1
        case "$source_path" in "$REPO"|"$REPO/home") ;; *)
            warn "Existing chezmoi source preserved: $source_path. Use --manager sh or explicitly migrate it."
            return 1 ;;
        esac
        chezmoi --config "$config" apply --source "$REPO" --destination "$HOME" --exclude=scripts || return 1
    else
        chezmoi --config "$config" init --source "$REPO" --destination "$HOME" --apply --exclude=scripts || return 1
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
    for tool in chezmoi herdr specstory codex; do
        if command -v "$tool" >/dev/null 2>&1; then
            if probe "$(command -v "$tool")"; then say "$tool: version probe passed; device workflow unverified"
            else warn "$tool: version probe failed"; failed=1; fi
        else say "$tool: not installed"; fi
    done
    return "$failed"
}
