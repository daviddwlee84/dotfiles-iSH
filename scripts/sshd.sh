#!/bin/sh
# iSH-only system setup. Never sourced by an interactive shell.
set -eu
DOTFILES_REPO=$(CDPATH='' cd "$(dirname "$0")/.." && pwd -P)
export DOTFILES_REPO
# shellcheck source=scripts/core.sh
. "$DOTFILES_REPO/scripts/core.sh"
context
[ "$PLATFORM" = ish ] || die 'SSH server setup is iSH-only.'
PACKAGE_NETWORK=${DOTFILES_PACKAGE_NETWORK:-}
SOURCE_NETWORK=${DOTFILES_SOURCE_NETWORK:-}
SSHD=${DOTFILES_SSHD:-}
load_network_preferences
load_sshd_preference
case "${1:-}" in ''|--status) ;; *) die 'Usage: sh scripts/sshd.sh [--status] (select with bootstrap --sshd on|off)' ;; esac
[ "$#" -le 1 ] || die 'Unexpected SSH setup arguments'

ssh_dir="$SYSROOT/etc/ssh/dotfiles-lite"
ssh_config="$ssh_dir/sshd_config"
ssh_service="$SYSROOT/etc/init.d/dotfiles-sshd"
ssh_marker="$ssh_dir/.managed"
# Absolute target paths ensure fixtures cannot accidentally run host daemons,
# key generators, or service managers if a stub is missing.
sshd_bin="$SYSROOT/usr/sbin/sshd"
keygen_bin="$SYSROOT/usr/bin/ssh-keygen"
rc_update="$SYSROOT/sbin/rc-update"
rc_service="$SYSROOT/sbin/rc-service"
rc_status="$SYSROOT/bin/rc-status"

owned_service() {
    [ -f "$ssh_marker" ] && [ ! -L "$ssh_marker" ] &&
        [ "$(cat "$ssh_marker")" = dotfiles-lite-sshd-v1 ] &&
        [ -f "$ssh_service" ] && [ ! -L "$ssh_service" ] &&
        grep -q '^# managed-by: dotfiles-lite;' "$ssh_service"
}

auth_status() {
    # Report only account state, never its password hash or authorized keys.
    if [ ! -r "$SYSROOT/etc/shadow" ] || ! awk -F: '
        $1=="root" && $2!="" && $2!~/^[!*]/ {valid=1}
        END {exit !valid}
    ' "$SYSROOT/etc/shadow"; then
        say 'SSH login pending: run passwd in iSH to set/unlock the root password, then add your Mac public key. Empty passwords are refused.'
    else
        say 'Root password is set; verify login from your Mac and add your public key.'
    fi
}

if [ "${1:-}" = --status ]; then
    say "SSH preference: $SSHD"
    if owned_service; then
        say "SSH config: $ssh_config (default port 22000; seed edits preserved)"
        if [ -L "$SYSROOT/etc/runlevels/default/dotfiles-sshd" ]; then say 'SSH autostart: registered in default';
        else say 'SSH autostart: not registered'; fi
        if [ -x "$rc_service" ] && "$rc_service" dotfiles-sshd status; then :
        else say 'SSH service is not confirmed running; reopen iSH after installing OpenRC.'; fi
        auth_status
    else
        say 'SSH server not prepared by this repository.'
    fi
    exit 0
fi

[ "$(id -u)" = 0 ] || die 'SSH server setup requires root; home config remains available with --config-only.'
for ssh_path in "$SYSROOT/etc/ssh" "$ssh_dir" "$ssh_config" "$ssh_marker" "$ssh_service" \
    "$SYSROOT/var/log/dotfiles-sshd.log" "$SYSROOT/run/dotfiles-sshd.pid"; do
    [ ! -L "$ssh_path" ] || die "SSH setup preserves symlink: $ssh_path"
done
if [ "$SSHD" = off ]; then
    if owned_service && [ -L "$SYSROOT/etc/runlevels/default/dotfiles-sshd" ]; then
        [ -x "$rc_update" ] || die 'OpenRC is missing; cannot remove the owned autostart registration.'
        "$rc_update" del dotfiles-sshd default || die 'Failed to remove SSH autostart registration'
    fi
    say 'SSH autostart off. Existing sessions, service processes, packages, configs and keys are preserved.'
    exit 0
fi

if [ -e "$ssh_dir" ]; then
    [ -d "$ssh_dir" ] && [ -f "$ssh_marker" ] && [ "$(cat "$ssh_marker")" = dotfiles-lite-sshd-v1 ] || die 'Unrecognized SSH setup directory preserved.'
fi
if [ -e "$ssh_service" ]; then owned_service || die 'Existing dotfiles-sshd service preserved; resolve the name conflict first.'; fi
install_packages "$REPO/config/packages-sshd.txt" || die 'SSH packages could not be installed.'
for ssh_program in "$sshd_bin" "$keygen_bin" "$rc_update" "$rc_service" "$rc_status"; do
    [ -x "$ssh_program" ] || die "SSH prerequisite missing: $ssh_program"
done
command -v timeout >/dev/null 2>&1 || die 'BusyBox timeout is required for bounded SSH setup.'

umask 077
mkdir -p "$ssh_dir" "$SYSROOT/etc/init.d" "$SYSROOT/var/log" "$SYSROOT/run"
if [ ! -f "$ssh_marker" ]; then
    (set -C; printf '%s\n' dotfiles-lite-sshd-v1 >"$ssh_marker") || die 'SSH ownership marker changed concurrently'
fi
seed_system_file() {
    if [ -e "$2" ]; then [ -f "$2" ] || die "Not a regular SSH seed: $2"; return; fi
    ssh_seed_tmp=$(mktemp "$(dirname "$2")/.sshd-seed.XXXXXX")
    if ! cp "$1" "$ssh_seed_tmp" || ! chmod "$3" "$ssh_seed_tmp" || ! ln "$ssh_seed_tmp" "$2"; then
        rm -f "$ssh_seed_tmp"
        die "Could not publish SSH seed without replacing an existing file: $2"
    fi
    rm -f "$ssh_seed_tmp"
}
seed_system_file "$REPO/config/sshd/sshd_config" "$ssh_config" 600
seed_system_file "$REPO/config/sshd/dotfiles-sshd" "$ssh_service" 755
ensure_host_key() (
    # The separate server uses only Ed25519. Generating unused RSA/DSA keys
    # is expensive under emulation and would recreate keys a user removed.
    ssh_key="$SYSROOT/etc/ssh/ssh_host_ed25519_key"
    for ssh_key_file in "$ssh_key" "$ssh_key.pub"; do
        [ ! -L "$ssh_key_file" ] || die "Existing host key symlink preserved: $ssh_key_file"
        [ ! -e "$ssh_key_file" ] || [ -f "$ssh_key_file" ] || die 'Host key path is not a regular file'
    done
    if [ -e "$ssh_key" ]; then
        [ -s "$ssh_key" ] || die 'Empty existing host key preserved; repair it before starting SSH.'
        return 0
    fi
    [ ! -e "$ssh_key.pub" ] || die 'Existing public host key without its private key preserved; review the key pair.'
    ssh_key_tmp=$(mktemp -d "$SYSROOT/etc/ssh/.dotfiles-hostkey.XXXXXX")
    trap 'rm -rf "$ssh_key_tmp"' EXIT HUP INT TERM
    say 'SSH: generating the missing Ed25519 host key (120s deadline)'
    timeout -s KILL 120 "$keygen_bin" -q -t ed25519 -N '' -C '' -f "$ssh_key_tmp/key" </dev/null || die 'Host key generation failed or timed out; SSH was not activated.'
    chmod 600 "$ssh_key_tmp/key"
    chmod 644 "$ssh_key_tmp/key.pub"
    ln "$ssh_key_tmp/key" "$ssh_key" || die 'A host key appeared concurrently; existing keys preserved.'
    ln "$ssh_key_tmp/key.pub" "$ssh_key.pub" || die 'A public host key appeared concurrently; inspect the key pair before starting SSH.'
)
ensure_host_key
timeout -s KILL 15 "$sshd_bin" -t -f "$ssh_config" || die 'SSH configuration validation failed; service not started or restarted.'

"$rc_update" add dotfiles-sshd default || die 'Failed to register SSH in the default runlevel'
if [ "$("$rc_status" -r 2>/dev/null || true)" != default ]; then
    say 'SSH prepared; reopen iSH to enter the OpenRC default runlevel and start it automatically. No global runlevel change was performed.'
elif "$rc_service" dotfiles-sshd status >/dev/null 2>&1; then
    say 'SSH already running; retaining the current process and connections.'
else
    timeout -s KILL 15 "$rc_service" dotfiles-sshd start || die 'SSH start failed (possibly port 22000 in use); inspect /var/log/dotfiles-sshd.log. Existing servers were not stopped.'
    "$rc_service" dotfiles-sshd status || die 'SSH startup was not confirmed; inspect /var/log/dotfiles-sshd.log.'
    say 'SSH started. Connect with: ssh -p 22000 root@<device-Wi-Fi-IP>'
fi
auth_status
