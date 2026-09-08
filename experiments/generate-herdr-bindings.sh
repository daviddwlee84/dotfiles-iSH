#!/bin/sh
# Maintainer-only code generation; emits the i586 bindings on stdout.
set -eu
[ "$#" = 3 ] || { echo 'Usage: generate-herdr-bindings.sh BINDGEN HERDR_CHECKOUT ZIG_DIRECTORY > bindings_i586.rs' >&2; exit 2; }
bindings_tool=$1
herdr_source=$2
zig_root=$3
[ "$("$bindings_tool" --version)" = 'bindgen 0.72.1' ] || { echo 'bindgen 0.72.1 is required' >&2; exit 1; }
[ "$(git -C "$herdr_source" rev-parse HEAD)" = 9eb521456ac0d19d3ab3d9d7cea3cca10baa8a4c ] || { echo 'Expected the pinned Herdr v0.8.2 checkout' >&2; exit 1; }
git -C "$herdr_source" diff --quiet HEAD -- vendor/libghostty-vt/include || { echo 'Vendored header edits need separate ABI review' >&2; exit 1; }
if [ -z "${LIBCLANG_PATH:-}" ] && [ -f /Library/Developer/CommandLineTools/usr/lib/libclang.dylib ]; then
    LIBCLANG_PATH=/Library/Developer/CommandLineTools/usr/lib
    export LIBCLANG_PATH
fi
exec "$bindings_tool" "$herdr_source/vendor/libghostty-vt/include/ghostty/vt.h" \
    --allowlist-type 'Ghostty.*' --allowlist-function 'ghostty_.*' \
    --allowlist-var 'GHOSTTY_.*' --no-doc-comments --with-derive-default --rust-target 1.82 \
    -- -target i586-unknown-linux-musl -nostdinc \
    "-I$herdr_source/vendor/libghostty-vt/include" \
    "-I$zig_root/lib/libc/include/x86-linux-musl" \
    "-I$zig_root/lib/libc/include/generic-musl" "-I$zig_root/lib/include"
