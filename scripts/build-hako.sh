#!/bin/sh
# Maintainer build only; never called by bootstrap or a home hook.
set -eu
build_zig=''
build_source=''
build_output=''
while [ "$#" -gt 0 ]; do
    case "$1" in
        --zig|--source|--output)
            [ "$#" -ge 2 ] || exit 2
            case "$1" in --zig) build_zig=$2 ;; --source) build_source=$2 ;; --output) build_output=$2 ;; esac
            shift 2 ;;
        --help|-h) echo 'Usage: sh scripts/build-hako.sh --zig /path/to/zig --output FILE [--source PINNED_CHECKOUT]'; exit 0 ;;
        *) echo 'Unknown build argument' >&2; exit 2 ;;
    esac
done
[ ! -d /proc/ish ] && [ ! -f /etc/openwrt_release ] || { echo 'Run this build on a maintainer host, not a target device.' >&2; exit 1; }
[ -n "$build_zig" ] && [ -x "$build_zig" ] && [ -n "$build_output" ] || { echo 'An explicit Zig executable and output file are required.' >&2; exit 2; }
[ "$("$build_zig" version)" = 0.15.2 ] || { echo 'This recipe is pinned to Zig 0.15.2.' >&2; exit 1; }
[ ! -e "$build_output" ] && [ ! -L "$build_output" ] || { echo 'Existing output preserved.' >&2; exit 1; }
build_tmp=$(mktemp -d)
trap 'rm -rf "$build_tmp"' EXIT HUP INT TERM
if [ -z "$build_source" ]; then
    git clone --depth 1 --branch v0.2.3 https://github.com/mithraeums/hako-code.git "$build_tmp/source"
    build_source="$build_tmp/source"
fi
build_commit=452291112f8a639aac5059070fb933e2d5bbb28b
[ "$(git -C "$build_source" rev-parse HEAD)" = "$build_commit" ] || { echo 'hako source commit does not match the pinned v0.2.3 revision.' >&2; exit 1; }
git -C "$build_source" diff --quiet HEAD -- || { echo 'Source edits need their own reviewed recipe; pinned checkout required.' >&2; exit 1; }
"$build_zig" cc -target x86-linux-musl -mcpu=pentium -Os -static \
    "$build_source/hako.c" -lpthread -o "$build_tmp/hako"
[ "$(od -An -tu1 -j4 -N1 "$build_tmp/hako" | tr -d ' ')" = 1 ] || { echo 'Expected a 32-bit ELF artifact.' >&2; exit 1; }
mkdir -p "$(dirname "$build_output")"
# Noclobber also protects a file created during compilation.
(set -C; cat "$build_tmp/hako" >"$build_output")
chmod 755 "$build_output"
printf 'source_commit=%s\ncompiler=zig-0.15.2\ntarget=x86-linux-musl/pentium\nverification=build-only\n' "$build_commit"
if command -v sha256sum >/dev/null 2>&1; then sha256sum "$build_output";
else shasum -a 256 "$build_output"; fi
echo 'Not installed. Device workflow acceptance is required before enabling an installer.'
