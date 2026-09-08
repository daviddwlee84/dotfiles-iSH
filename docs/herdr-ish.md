# Herdr on iSH

Herdr has an experimental iSH/i386 compatibility build. The verified v0.8.2
binary is installed on one original iPad at `~/.local/bin/herdr`; its exact
version, size and SHA-256 were checked over SSH. This establishes installation
and startup on that device. Resize, longer sessions and a real coding-agent
workflow still need acceptance before the bootstrap installer opens to everyone.

The iSH build is maintained here because upstream Herdr releases currently ship
64-bit Linux artifacts, while iSH runs 32-bit x86 userspace. The compatibility
build also needs scoped Rust standard-library, local-socket and Ghostty ABI/
allocator patches. Upstream [Herdr v0.9.0](https://github.com/herdrdev/herdr/releases/tag/v0.9.0)
is pinned for the next artifact. The current 24,286,088-byte candidate builds and
passes CLI named-session, pane I/O, detach and reattach checks with SHA-256
`fe35d6587f524626512f6897d3113825717d2cdf3bdc791161988f8b084672af`.
CLI host resize remains unresolved, and original-iPad transfer is pending.

## Current device installation

The tested v0.8.2 artifact has these properties:

| Field | Value |
|---|---|
| Path | `~/.local/bin/herdr` |
| Version | `herdr 0.8.2` |
| Bytes | `21556492` |
| SHA-256 | `3ede5a4aed39470a67a66453b305f086bf51275c03d7bd0c16c513beb3dd9809` |

The managed profile adds `~/.local/bin` to `PATH`. Start a new login shell or
reload it after a manual installation:

```sh
. ~/.profile
command -v herdr
herdr --version
```

The existing file is install-only: bootstrap and update hooks preserve a working
binary until the user explicitly selects a newer locked release.

## Distribution to users

Accepted iSH builds will be published as assets on this repository's GitHub
Releases. A release tag such as `herdr-ish-v0.9.0-r1` distinguishes the upstream
version from this compatibility packaging revision. Each release contains the
ELF32 binary, its SHA-256 file, a build manifest and patch checksums.

After an exact release artifact passes original-device acceptance, maintainers
copy the generated row into `config/assets.lock`, enable the iSH `herdr` option,
and add installer fixtures. Users can then install it through:

```sh
sh bootstrap.sh --manager sh --with herdr
```

Until that release row exists, iSH deliberately rejects `--with herdr`. This
prevents bootstrap from depending on an unpublished artifact or treating a host
build/version probe as device acceptance.

## Reproducible v0.9.0 build

On an x86_64 Linux maintainer host, inspect the fully pinned plan without network
or output changes:

```sh
sh scripts/build-herdr-ish.sh --print-plan
```

Build the reviewed version into a new output directory:

```sh
sh scripts/build-herdr-ish.sh \
  --version v0.9.0 \
  --release-revision r1 \
  --output /tmp/herdr-ish
```

`config/herdr-build.lock` pins the upstream tag commit, Rust/rust-src, Zig, byte
sizes and SHA-256 values. The script clones that exact commit, applies the
reviewed version patch and shared compatibility patches, builds the i586 musl
binary, checks its version, and writes:

- `herdr-v0.9.0-ish-i386`
- `herdr-v0.9.0-ish-i386.sha256`
- `manifest.json`
- `patches.sha256`
- `assets-lock-row.txt`

The `Herdr iSH artifact` GitHub Actions workflow checks weekly whether upstream
has a newer release. A new tag makes the check fail with a review notice; it does
not build unknown code automatically. A manual run builds and retains an Actions
artifact. Publishing also requires explicit confirmation that this exact binary
passed the original-device checks.

For each new upstream version, update the lock and create a reviewed
`experiments/patches/herdr-VERSION-ish.patch`. Patch application, lock validation,
the build and device acceptance must all pass. This boundary keeps upstream API,
IPC and vendored Ghostty changes visible instead of silently carrying old iSH
assumptions forward.

## Acceptance before publishing

Test the exact final SHA-256 on the original iSH App through trusted SSH:

1. Verify transfer size, SHA-256 and `herdr --version`.
2. Start a named session and a shell pane; check input and output.
3. Detach and reattach to the same pane and process.
4. Resize the SSH PTY and verify the pane receives the new dimensions.
5. Run a bounded real-agent workflow, then stop only the test-owned session.
6. Reopen iSH and repeat the startup/session check without replacing user config.

Record the verification level in the manifest and [experiment results](experiments.md).
