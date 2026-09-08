#!/usr/bin/env bats

setup() {
    export REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
}

@test "Herdr iSH builder prints the locked reproducible plan without network or output" {
    output_dir="$BATS_TEST_TMPDIR/output"
    run sh "$REPO/scripts/build-herdr-ish.sh" --print-plan --output "$output_dir"
    [ "$status" = 0 ]
    [[ "$output" == *'herdr_version=v0.9.0'* ]]
    [[ "$output" == *'herdr_commit=b99002ac99b09e00b4ca692436cb15a6b0d676f1'* ]]
    [[ "$output" == *'herdr-0.9.0-ish.patch'* ]]
    [[ "$output" == *'ghostty-i386-c-abi.patch'* ]]
    [[ "$output" == *'rust-1.96.1-ish-process-pipe.patch'* ]]
    [ ! -e "$output_dir" ]
}

@test "Herdr iSH builder rejects an unreviewed upstream version" {
    run sh "$REPO/scripts/build-herdr-ish.sh" --version v0.9.1 --print-plan
    [ "$status" != 0 ]
    [[ "$output" == *'No reviewed iSH patch lock for v0.9.1'* ]]
}

@test "Herdr iSH builder rejects unsafe release revision text" {
    run sh "$REPO/scripts/build-herdr-ish.sh" --release-revision '../latest' --print-plan
    [ "$status" = 2 ]
    [[ "$output" == *'Invalid release revision'* ]]
}

@test "Herdr iSH build lock names complete pinned inputs" {
    run awk -F= '
        /^[a-z0-9_][a-z0-9_]*=/ { seen[$1]++; next }
        /^#/ || /^$/ { next }
        { bad=1 }
        END {
            required="herdr_version herdr_commit rust_version rust_src_url rust_src_sha256 rust_src_bytes zig_version zig_url zig_sha256 zig_bytes"
            count=split(required,names," ")
            for(i=1;i<=count;i++) if(seen[names[i]]!=1) bad=1
            exit bad
        }
    ' "$REPO/config/herdr-build.lock"
    [ "$status" = 0 ]
}
