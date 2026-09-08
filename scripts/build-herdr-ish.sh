#!/bin/sh
# Maintainer-only reproducible iSH/i386 Herdr builder. Never runs on targets.
set -eu

REPO=$(CDPATH='' cd "$(dirname "$0")/.." && pwd -P)
LOCK="$REPO/config/herdr-build.lock"

herdr_version=''
herdr_commit=''
rust_version=''
rust_src_url=''
rust_src_sha256=''
rust_src_bytes=''
zig_version=''
zig_url=''
zig_sha256=''
zig_bytes=''
version=''
output="$REPO/dist/herdr-ish"
source_dir=''
work_dir=''
print_plan=0
keep_work=0
release_revision=r1

usage() {
    printf '%s\n' \
        'Usage: scripts/build-herdr-ish.sh [--version vX.Y.Z] [--output DIR] [--source DIR] [--work-dir DIR] [--release-revision rN] [--keep-work] [--print-plan]' \
        'Build host: x86_64 Linux. Unknown Herdr versions stop until a reviewed version patch and lock entry exist.'
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --version) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; version=$2; shift 2 ;;
        --output) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; output=$2; shift 2 ;;
        --source) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; source_dir=$2; shift 2 ;;
        --work-dir) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; work_dir=$2; shift 2 ;;
        --release-revision) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; release_revision=$2; shift 2 ;;
        --keep-work) keep_work=1; shift ;;
        --print-plan) print_plan=1; shift ;;
        --help|-h) usage; exit 0 ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done
case "$release_revision" in ''|*[!a-zA-Z0-9._-]*) printf 'Invalid release revision: %s\n' "$release_revision" >&2; exit 2 ;; esac

[ -r "$LOCK" ] || { printf 'Missing %s\n' "$LOCK" >&2; exit 1; }
# shellcheck disable=SC1090
. "$LOCK"
for value in herdr_version herdr_commit rust_version rust_src_url rust_src_sha256 rust_src_bytes zig_version zig_url zig_sha256 zig_bytes; do
    eval "locked_value=\${$value}"
    [ -n "$locked_value" ] || { printf 'Missing lock value: %s\n' "$value" >&2; exit 1; }
done
version=${version:-$herdr_version}
[ "$version" = "$herdr_version" ] || {
    printf 'No reviewed iSH patch lock for %s; current lock is %s\n' "$version" "$herdr_version" >&2
    exit 1
}

herdr_patch="$REPO/experiments/patches/herdr-${version#v}-ish.patch"
ghostty_abi_patch="$REPO/experiments/patches/ghostty-i386-c-abi.patch"
ghostty_allocator_patch="$REPO/experiments/patches/ghostty-vt-libc-option.patch"
rust_process_patch="$REPO/experiments/patches/rust-1.96.1-ish-process-pipe.patch"
rust_sleep_patch="$REPO/experiments/patches/rust-1.96.1-ish-thread-sleep.patch"
for patch in "$herdr_patch" "$ghostty_abi_patch" "$ghostty_allocator_patch" "$rust_process_patch" "$rust_sleep_patch"; do
    [ -r "$patch" ] || { printf 'Missing reviewed patch: %s\n' "$patch" >&2; exit 1; }
done

if [ "$print_plan" = 1 ]; then
    printf 'herdr_version=%s\nherdr_commit=%s\nrust_version=%s\nrust_src_sha256=%s\nzig_version=%s\n' \
        "$herdr_version" "$herdr_commit" "$rust_version" "$rust_src_sha256" "$zig_version"
    printf 'patch=%s\n' "$herdr_patch" "$ghostty_abi_patch" "$ghostty_allocator_patch" "$rust_process_patch" "$rust_sleep_patch"
    printf 'release_revision=%s\noutput=%s\n' "$release_revision" "$output"
    exit 0
fi

[ ! -d /proc/ish ] && [ ! -f /etc/openwrt_release ] || {
    printf 'Run this build on a maintainer host, not a target device.\n' >&2
    exit 1
}
[ "$(uname -s)" = Linux ] && [ "$(uname -m)" = x86_64 ] || {
    printf 'The automated builder requires x86_64 Linux.\n' >&2
    exit 1
}
for command in git curl tar sha256sum stat rustup timeout jq grep; do
    command -v "$command" >/dev/null 2>&1 || { printf 'Missing build command: %s\n' "$command" >&2; exit 1; }
done

cleanup=0
if [ -z "$work_dir" ]; then
    work_dir=$(mktemp -d "${TMPDIR:-/tmp}/herdr-ish-build.XXXXXX")
    cleanup=1
else
    mkdir -p "$work_dir"
    work_dir=$(CDPATH='' cd "$work_dir" && pwd -P)
fi
if [ "$keep_work" = 1 ]; then cleanup=0; fi
trap '[ "$cleanup" = 0 ] || rm -rf "$work_dir"' EXIT HUP INT TERM

mkdir -p "$output"
output=$(CDPATH='' cd "$output" && pwd -P)
artifact="herdr-$version-ish-i386"
[ ! -e "$output/$artifact" ] && [ ! -L "$output/$artifact" ] || {
    printf 'Output already exists: %s\n' "$output/$artifact" >&2
    exit 1
}

if [ -n "$source_dir" ]; then
    source_input=$(CDPATH='' cd "$source_dir" && pwd -P)
    [ -d "$source_input/.git" ] || { printf 'Source is not a Git checkout: %s\n' "$source_input" >&2; exit 1; }
    [ -z "$(git -C "$source_input" status --porcelain)" ] || { printf 'Source checkout is not clean.\n' >&2; exit 1; }
    source_dir="$work_dir/herdr"
    git clone --shared --no-checkout "$source_input" "$source_dir"
    git -C "$source_dir" checkout --detach "$herdr_commit"
else
    source_dir="$work_dir/herdr"
    git clone --filter=blob:none --depth=1 --branch "$version" https://github.com/herdrdev/herdr.git "$source_dir"
fi
[ "$(git -C "$source_dir" rev-parse HEAD)" = "$herdr_commit" ] || {
    printf 'Herdr tag commit mismatch.\n' >&2
    exit 1
}

for patch in "$herdr_patch" "$ghostty_abi_patch" "$ghostty_allocator_patch"; do
    git -C "$source_dir" apply --check "$patch"
    git -C "$source_dir" apply "$patch"
done

if [ -n "${ZIG:-}" ]; then
    zig=$ZIG
    [ "$("$zig" version)" = "$zig_version" ] || { printf 'Expected Zig %s\n' "$zig_version" >&2; exit 1; }
else
    zig_archive="$work_dir/zig.tar.xz"
    curl -fLsS --connect-timeout 15 --max-time 300 -o "$zig_archive" "$zig_url"
    [ "$(wc -c <"$zig_archive" | tr -d ' ')" = "$zig_bytes" ] || { printf 'Zig archive size mismatch.\n' >&2; exit 1; }
    printf '%s  %s\n' "$zig_sha256" "$zig_archive" | sha256sum -c -
    tar -xJf "$zig_archive" -C "$work_dir"
    zig="$work_dir/zig-x86_64-linux-$zig_version/zig"
fi

export RUSTUP_HOME="$work_dir/rustup"
export CARGO_HOME="$work_dir/cargo"
rustup toolchain install "$rust_version" --profile minimal
run_rustc() { rustup run "$rust_version" rustc "$@"; }
run_cargo() { rustup run "$rust_version" cargo "$@"; }
sysroot=$(run_rustc --print sysroot)
rust_src_archive="$work_dir/rust-src.tar.xz"
curl -fLsS --connect-timeout 15 --max-time 300 -o "$rust_src_archive" "$rust_src_url"
[ "$(wc -c <"$rust_src_archive" | tr -d ' ')" = "$rust_src_bytes" ] || { printf 'rust-src archive size mismatch.\n' >&2; exit 1; }
printf '%s  %s\n' "$rust_src_sha256" "$rust_src_archive" | sha256sum -c -
tar -xJf "$rust_src_archive" -C "$work_dir"
rust_source="$work_dir/rust-src-$rust_version/rust-src/lib/rustlib/src/rust"
[ -d "$rust_source/library/std" ] || { printf 'rust-src was not installed.\n' >&2; exit 1; }
mkdir -p "$sysroot/lib/rustlib"
ln -s "$work_dir/rust-src-$rust_version/rust-src/lib/rustlib/src" "$sysroot/lib/rustlib/src"
git -C "$rust_source" apply --check "$rust_process_patch"
git -C "$rust_source" apply "$rust_process_patch"
git -C "$rust_source" apply --check "$rust_sleep_patch"
git -C "$rust_source" apply "$rust_sleep_patch"

host=$(run_rustc -vV | sed -n 's/^host: //p')
linker="$sysroot/lib/rustlib/$host/bin/rust-lld"
[ -x "$linker" ] || { printf 'Rust bundled linker not found: %s\n' "$linker" >&2; exit 1; }

export ZIG="$zig"
export ZIG_GLOBAL_CACHE_DIR="$work_dir/zig-cache"
export CARGO_TARGET_DIR="$work_dir/target"
export RUSTC_BOOTSTRAP=1
export RUSTFLAGS="--cfg ish_compat --check-cfg=cfg(ish_compat) -C linker-flavor=ld.lld -C linker=$linker -C link-self-contained=yes"
export LIBGHOSTTY_VT_OPTIMIZE=ReleaseSmall
export LIBGHOSTTY_VT_SIMD=false

cd "$source_dir"
run_cargo fetch --locked --target i586-unknown-linux-musl
run_cargo build -Z build-std=std,panic_unwind --release --locked --target i586-unknown-linux-musl --bin herdr -j2

built="$CARGO_TARGET_DIR/i586-unknown-linux-musl/release/herdr"
[ -x "$built" ] || { printf 'Herdr output is missing.\n' >&2; exit 1; }
cp "$built" "$output/$artifact"
chmod 755 "$output/$artifact"
timeout -s KILL 20 "$output/$artifact" --version | grep -F "herdr ${version#v}"

digest=$(sha256sum "$output/$artifact" | awk '{print $1}')
bytes=$(stat -c '%s' "$output/$artifact")
printf '%s  %s\n' "$digest" "$artifact" >"$output/$artifact.sha256"

for patch in "$herdr_patch" "$ghostty_abi_patch" "$ghostty_allocator_patch" "$rust_process_patch" "$rust_sleep_patch"; do
    patch_name=$(basename "$patch")
    printf '%s  %s\n' "$(sha256sum "$patch" | awk '{print $1}')" "$patch_name"
done >"$output/patches.sha256"

jq -n \
    --arg version "$version" \
    --arg commit "$herdr_commit" \
    --arg rust "$rust_version" \
    --arg zig "$zig_version" \
    --arg artifact "$artifact" \
    --arg sha256 "$digest" \
    --argjson bytes "$bytes" \
    '{version:$version,commit:$commit,target:"i586-unknown-linux-musl",rust:$rust,zig:$zig,artifact:$artifact,sha256:$sha256,bytes:$bytes,verification:"x86_64 Linux version probe; iSH CLI and device acceptance remain separate"}' \
    >"$output/manifest.json"

release_tag="herdr-ish-$version-$release_revision"
repository=${GITHUB_REPOSITORY:-daviddwlee84/dotfiles-iSH}
printf 'herdr|i386|%s|https://github.com/%s/releases/download/%s/%s|%s|raw|-|%s\n' \
    "$version" "$repository" "$release_tag" "$artifact" "$digest" "$bytes" \
    >"$output/assets-lock-row.txt"

printf 'Built %s\nSHA-256: %s\nBytes: %s\nOutput: %s\n' "$artifact" "$digest" "$bytes" "$output"
