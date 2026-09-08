#!/bin/sh
# Maintainer-side, key-authenticated probes of one explicitly selected iSH.
set -eu
probe_host=''
probe_port=22000
probe_user=root
probe_identity=''
probe_case=inventory
probe_output=''
usage() {
    echo 'Usage: sh scripts/ish-probe.sh --host IP_OR_SSH_ALIAS [--port 22000] [--user root] [--identity FILE] [--case inventory|node|hako|pi|gemini|herdr] [--output FILE]'
}
while [ "$#" -gt 0 ]; do
    case "$1" in
        --help|-h) usage; exit 0 ;;
        --host|--port|--user|--identity|--case|--output)
            [ "$#" -ge 2 ] || { usage >&2; exit 2; }
            case "$1" in
                --host) probe_host=$2 ;; --port) probe_port=$2 ;; --user) probe_user=$2 ;;
                --identity) probe_identity=$2 ;; --case) probe_case=$2 ;; --output) probe_output=$2 ;;
            esac
            shift 2 ;;
        *) usage >&2; exit 2 ;;
    esac
done
case "$probe_host" in ''|-*|*[!a-zA-Z0-9._:-]*) echo 'Specify one host/IP, without SSH options or a username.' >&2; exit 2 ;; esac
case "$probe_user" in ''|-*|*[!a-zA-Z0-9._-]*) echo 'Invalid SSH username' >&2; exit 2 ;; esac
case "$probe_port" in ''|*[!0-9]*) echo 'Invalid SSH port' >&2; exit 2 ;; esac
[ "$probe_port" -ge 1 ] && [ "$probe_port" -le 65535 ] || { echo 'Invalid SSH port' >&2; exit 2; }
case "$probe_case" in inventory|node|hako|pi|gemini|herdr) ;; *) echo 'Unknown probe case' >&2; exit 2 ;; esac
if [ -n "$probe_output" ] && { [ -e "$probe_output" ] || [ -L "$probe_output" ]; }; then
    echo 'Output already exists; choose a new report path.' >&2; exit 2
fi
set -- -p "$probe_port" -l "$probe_user" -o BatchMode=yes -o StrictHostKeyChecking=yes \
    -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=2
if [ -n "$probe_identity" ]; then
    [ -r "$probe_identity" ] || { echo 'Identity file is not readable' >&2; exit 2; }
    set -- "$@" -i "$probe_identity" -o IdentitiesOnly=yes
fi
umask 077
probe_tmp=$(mktemp)
trap 'rm -f "$probe_tmp"' EXIT HUP INT TERM
probe_status=0
ssh "$@" "$probe_host" sh -s -- "$probe_case" >"$probe_tmp" <<'REMOTE' || probe_status=$?
set -eu
[ -d /proc/ish ] || { echo 'Refusing probe: remote target is not iSH.' >&2; exit 1; }
printf 'verification=ish-runtime-probe (not full device workflow acceptance)\n'
date -u '+date=%Y-%m-%dT%H:%M:%SZ'
printf 'arch='; uname -m
printf 'alpine='; cat /etc/alpine-release
printf 'ish='; cat /proc/ish/version
printf '\n'
command -v timeout >/dev/null 2>&1 || { echo 'BusyBox timeout is required.' >&2; exit 1; }
probe_agent_version() (
    probe_agent_path=$(command -v "$1") || { echo "Agent is not installed: $1" >&2; exit 1; }
    case "$probe_agent_path" in
        /*) ;;
        *) probe_agent_path=$(CDPATH='' cd "$(dirname "$probe_agent_path")" && pwd -P)/$(basename "$probe_agent_path") ;;
    esac
    probe_version_dir=$(mktemp -d)
    trap 'rm -rf "$probe_version_dir"' EXIT HUP INT TERM
    mkdir "$probe_version_dir/home" "$probe_version_dir/project"
    cd "$probe_version_dir/project"
    # Some agents load and save credentials/project state before parsing --version.
    # Keep the installed executable/runtime PATH, but give it no user state or auth.
    timeout -s KILL 15 env -i HOME="$probe_version_dir/home" PATH="$PATH" \
        XDG_CONFIG_HOME="$probe_version_dir/home/.config" \
        XDG_DATA_HOME="$probe_version_dir/home/.local/share" \
        XDG_STATE_HOME="$probe_version_dir/home/.local/state" \
        XDG_CACHE_HOME="$probe_version_dir/home/.cache" LC_ALL=C TERM=dumb \
        "$probe_agent_path" --version
)
case "$1" in
    inventory)
        for probe_tool in ssh tmux node hako pi gemini herdr; do
            if command -v "$probe_tool" >/dev/null 2>&1; then printf '%s=installed\n' "$probe_tool";
            else printf '%s=missing\n' "$probe_tool"; fi
        done
        df -Pk /tmp
        if [ -r /proc/meminfo ]; then awk '/^MemTotal:|^MemAvailable:/' /proc/meminfo; fi ;;
    node)
        timeout -s KILL 15 node --version
        timeout -s KILL 15 node <<'JS'
const fs = require('fs');
const os = require('os');
const path = require('path');
const {spawnSync} = require('child_process');
const {Worker} = require('worker_threads');
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ish-node-probe-'));
try {
  const file = path.join(dir, 'sample');
  fs.writeFileSync(file, 'ish-file-ok');
  if (fs.readFileSync(file, 'utf8') !== 'ish-file-ok') throw Error('file roundtrip failed');
  const child = spawnSync('/bin/sh', ['-c', 'printf ish-child-ok'], {encoding:'utf8', timeout:5000});
  if (child.status !== 0 || child.stdout !== 'ish-child-ok') throw Error('child process failed');
  console.log('file=passed child_process=passed');
} finally {
  fs.rmSync(dir, {recursive:true, force:true});
}
const worker = new Worker("require('worker_threads').parentPort.postMessage(6*7)", {eval:true});
worker.on('message', value => { if(value!==42) throw Error('worker result'); console.log('worker=passed'); });
worker.on('error', error => { console.error(error.message); process.exitCode=1; });
require('https').get('https://nodejs.org/', {timeout:8000}, response => {
  response.resume(); console.log('https=connected status='+response.statusCode);
}).on('timeout', function() { this.destroy(Error('HTTPS timeout')); }).on('error', error => {
  console.error(error.message); process.exitCode=1;
});
JS
        ;;
    hako|pi|gemini|herdr)
        probe_agent_version "$1"
        echo 'version_probe=passed; interactive/authenticated workflow remains unverified' ;;
esac
REMOTE
cat "$probe_tmp"
if [ -n "$probe_output" ]; then
    (set -C; cat "$probe_tmp" >"$probe_output") || { echo 'Could not create the report; existing output preserved.' >&2; exit 1; }
fi
exit "$probe_status"
