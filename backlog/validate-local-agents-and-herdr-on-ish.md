# Validate local agents and Herdr on iSH

**Status**: in progress; SSH/Finder device checks passed, agent workflow acceptance pending
**Effort**: L
**Related**: `TODO.md`, `docs/ssh-server.md`, `docs/finder-files.md`, `docs/experiments.md`

## Current state

SSH key/password login, PTY checks, verified SSH streams and legacy SCP work on
the iPad. Finder installation and one complete app restart without a manual
mount passed. SFTP fails its required PR_SET_DUMPABLE startup guard. hako's
version runs; provider authentication and full read/edit/shell turns are still
unconfirmed. Herdr's missing SEQPACKET/process path is reproduced on the device.
The sections below retain the chronological investigation, including earlier
pending states that were resolved by later checks.

## Scope agreed 2026-09-08

Use a copy of the current filesystem and same-Wi-Fi SSH from the Mac. SSH defaults
on, supports manually configured password plus public keys, and uses OpenRC for
app-boot autostart. New Alpine releases are separate filesystems. The sequence is
hako, Pi/Gemini, Herdr; only accepted device workflows enter optional installation.
Patched iSH is allowed through command-line emulator verification this round;
iOS signing/sideloading is deferred (no full Xcode/signing identity on this host).

## Implementation completed

SSH-only preparation before chezmoi probing, persistent selection shared between
managers, independent config/service seeds, no existing-server restart, default
runlevel registration, manual password/key setup, bounded SSH probes, bilingual
SSH/experiment docs and correction of the migrated SIGILL pitfall. Common files
are mirrored into the OpenWrt companion, whose SSH behavior remains unchanged.

## Build sources and measurements

- hako-code v0.2.3: `452291112f8a639aac5059070fb933e2d5bbb28b`.
- iSH CLI: `d189985e5cc6d0e70629efeb31505b51a9ce78af` (upstream checkout).
- Herdr v0.8.2: `9eb521456ac0d19d3ab3d9d7cea3cca10baa8a4c`.
- Zig 0.15.2 macOS arm64 archive SHA-256:
  `3cc2bab367e185cdfb27501c4b30b1b0653c28d9f73df8dc91488e66ece5fa6b`.
- Zig 0.15.2 Linux arm64 archive SHA-256:
  `958ed7d1e00d0ea76590d27666efbf7a932281b3d7ba0c6b01b0ff26498f667f`.
- Alpine 3.14.10 x86 minirootfs SHA-256:
  `cb1a66b40b1a80dff4c2f9349333ee01fa74fca7409f7526101d53f9e1ff2e4f`.
- Alpine 3.24.1 x86 minirootfs SHA-256:
  `634355e2245c9d56186d1b86fb6e034453eb303aea15b573ca250b343376fffd`.

`sh scripts/build-hako.sh --zig /path/to/zig --output /tmp/hako-i586`
produces a static 32-bit binary. Measured SHA-256 with Zig:
`605c8377fa9a168fc7492cfe5309690797a0f7a9337bc0fec07618faf731be31`.
Alpine GCC 10.3, `-static -Os -march=i586 -lpthread`, also builds and passes the
version probe in a disposable Linux x86 container (not the iSH emulator).

Both hako variants pass `--version` in the iSH CLI with Alpine 3.24.1. The Zig
variant also passes in Alpine 3.14.10. Shell, uname and reading the Alpine version
pass in both CLI guest filesystems. Hako help output is available. No authenticated
model turn or actual iPhone TUI has been accepted.

## Reproducing the emulator setup

Build the pinned iSH source using Meson 1.12.0 and Ninja, host C compiler and
libarchive/sqlite. The Apple host build needs an ELF i386 VDSO compiler: a local
`clang` wrapper delegates to verified Zig 0.15.2 `cc` and replaces the target
argument `i386-linux` with `x86-linux-musl`. Put only that wrapper in a temporary
PATH directory. Use Homebrew libarchive's pkg-config directory if needed. Do not
change the machine's compiler selection globally.

Create a derived tar archive from a checksum-verified minirootfs, adding the test
binary under `usr/local/bin`. Run the built `tools/fakefsify ARCHIVE GUEST_DIR`,
then `ish -f GUEST_DIR /usr/local/bin/hako --version` with a host-side timeout.
Never run the dotfiles target bootstrap on the maintainer outside fixture tests.

## Obstacles seen while setting up builds

Zig's macOS build runner failed linking host SDK symbols, including:

```text
error: undefined symbol: __availability_version_check
error: undefined symbol: _abort
```

This is a host build failure, not evidence about 32-bit libghostty or iSH. Continue
its cross-build in a Linux container with the verified Linux Zig distribution.
A minimal Ubuntu container initially reported `TlsInitializationFailed`; use a
normal CA certificate bundle rather than disabling TLS verification.

The inherited Rust mirror returned 404 for Herdr's pinned 1.96.1 toolchain.
Retry official Rust distribution endpoints with build-local environment overrides;
do not rewrite global preferences or a target device's repositories.

## Acceptance still required

Obtain the device Wi-Fi address, establish a trusted SSH host key and key login,
then run the probes in `docs/ssh-server.md`. The user sets passwords/provider
credentials locally. Record three cold app restarts, PTY and SFTP, then each
agent's read/edit/shell/follow-up workflow. Keep all authentication and private
session data out of this document. Do not mark this item shipped after a build
or a version probe alone.

## Further CLI results (2026-09-08)

- Hako renders its first-run provider selector through a PTY in the CLI guest.
  No provider was authenticated; the isolated test process was stopped at that UI.
- The exported Alpine 3.24 Node environment contains Node 24.18.1 and npm 11.12.1.
  Its version probe passes. A minimal JavaScript evaluation exits the release
  iSH CLI with SIGSEGV; `--jitless` and the upstream `cvtdq2pd` patch do not resolve
  it. A debug CLI build times out at 25 seconds. This has not been attributed to
  a specific root cause and is not a statement about all iSH builds or Node versions.
- Docker's separate qemu-i386 runner also timed out on a bounded JavaScript check;
  do not conflate that Linux-container observation with the iSH emulator result.
- Importing the exported rootfs initially failed with
  `error!!1! 242 0 Linkpath can't be converted from UTF-8 to current locale`.
  The host-only `experiments/patches/fakefsify-locale.patch` initializes the C
  locale from the environment; import succeeds with `LC_ALL=en_US.UTF-8`.
- The existing upstream instruction patch is preserved in
  `experiments/patches/ish-cvtdq2pd.patch`; it is not claimed to fix Node 24.
- libghostty-vt builds for `x86-linux-musl`, `-Dcpu=pentium`, `-Dsimd=false`,
  `ReleaseSmall`, using Linux Zig 0.15.2 in an ARM64 Ubuntu container. Its static
  archive is 1,224,644 bytes; SHA-256:
  `2420a175e61fb0f02c1f51ece791b5391a15fb0d5b9712af56ca0b98c92e9196`.
  This proves the terminal library can be built for 32-bit; it does not prove the
  Rust executable or PTY/runtime workflow works.
- `experiments/patches/herdr-i586-build.patch` adds the i586 target mapping,
  conservative CPU selection and scalar default to Herdr's build script. Apply
  it to the pinned Herdr tag, not an arbitrary latest checkout.

For Zig's transient GitHub fetch failures, prefetch the same pinned tarballs via
codeload and `zig fetch --global-cache-dir CACHE ARCHIVE`. The resulting package
hashes must match the dependency manifests. Do not edit expected hashes or turn
TLS checks off. Rust components were cached from a mirror only after checking
its release-manifest hash against the official endpoint and each component's
SHA-256. These are build-local caches, not target-device network preferences.

## SSH and build-environment follow-up

OpenSSH 8.6 on Alpine 3.14 accepts the seed config with the intended port/auth/
internal-sftp settings; OpenRC accepts the explicit default registration. Inside
the iSH CLI guest with Alpine 3.24, ephemeral Ed25519 generation completes in
1.42 seconds and the seed's config validation (using that ephemeral key path)
completes in 4.06 seconds. Neither is a real-device login or app-restart test.
The installer now generates only the missing Ed25519 key it actually uses,
preserving other host keys and avoiding unused RSA/DSA generation.

The host Rust toolchain was installed into a build-local prefix from the four
checksum-verified 1.96.1 distribution components (cargo, rustc, host std, i586 std).
The mirror manifest hash matched the official distribution manifest. No global
Rust toolchain, Cargo credentials or target device settings were changed.
Public crate archives were pre-cached only when their SHA-256 matched Cargo.lock;
subsequent Cargo builds use --offline --locked. The Ubuntu ARM64 build uses Zig
cc as its host linker and an x86-linux-musl/pentium wrapper as the target linker.
The wrappers select -O2 and omit Zig's implicit undefined-behavior sanitizer
runtime when linking Rust objects. Cargo runs with one job to avoid competing
cold Zig cache writes on the bind-mounted build cache.

## Herdr ABI port

The first Rust build reached the application but failed 38 generated layout
assertions, for example:

```text
error[E0080]: attempt to compute `8_usize - 16_usize`, which would overflow
```

The original bindings contain 64-bit size/offset expectations. Do not disable
those assertions. `experiments/generate-herdr-bindings.sh` regenerates an i586
file from the pinned vendor C headers using bindgen 0.72.1, Clang's explicit
`i586-unknown-linux-musl` target and Zig 0.15.2 musl headers. Include
`--with-derive-default` to retain the initialization traits used by the wrapper.
All 162 original types and 173 original functions remain present. The original
64-bit bindings stay untouched; only x86/musl selects `bindings_i586.rs`.
The port patch includes the generated file and module selection.

The libc 0.2.183 `time_t` deprecation warning is retained. Its default 32-bit
musl bindings use the legacy time32 compatibility entrypoints; the libc source
also provides an opt-in time64 configuration. Do not silently change this ABI
or suppress the warning without checking the chosen musl and runtime behavior.

The Zig target linker also needs to omit Rust's GNU-driver-only
`-Wl,-melf_i386` argument: Zig already selects ELF i386 through the explicit
`-target x86-linux-musl`. Keep all other linker arguments and verify the final
ELF class/machine. The build-local target wrapper used was:

```bash
#!/bin/bash
set -eu
args=()
for arg in "$@"; do
    case "$arg" in
        -Wl,-melf_i386) ;;
        *) args+=("$arg") ;;
    esac
done
exec /zig/zig cc -O2 -fno-sanitize=undefined -target x86-linux-musl -mcpu=pentium "${args[@]}"
```

This wrapper is a maintainer-container tool, never a prerequisite installed on
iSH. The Rust compile-time layout checks are still enabled.

## Final cross-build and launch result

The Zig driver attempted to rebuild libunwind without its C headers. The final
link therefore uses Rust's bundled rust-lld and self-contained target libraries:

```sh
cargo rustc --bin herdr --offline --locked --release --target i586-unknown-linux-musl -j1 -- \
  -C linker-flavor=ld.lld \
  -C linker=/toolchain/lib/rustlib/aarch64-unknown-linux-gnu/bin/rust-lld \
  -C link-self-contained=yes
```

The GCC-style target wrapper above is historical debugging context, not the
final executable link. Host build-script linking still uses the Zig cc wrapper.

The completed Herdr executable is ELF32/i386, statically linked, 20,455,488 bytes.
SHA-256: `b1a04a507c8263a89fb65d2563eae4b95f396b835775b3529b328537550b01eb`.
Both Alpine 3.14.10 and 3.24.1 CLI guest version probes return `herdr 0.8.2`
in approximately 0.06 seconds. The ABI layout checks remain enabled.

Named-session startup fails:

```text
herdr: failed to spawn herdr server: Invalid argument (os error 22)
```

The Rust diagnostic shows ordinary child spawning succeeds, but even an empty
pre_exec closure fails. Rust 1.96.1's Linux fork path requires SOCK_SEQPACKET,
which the tested iSH socket translator does not support. The separate host-argument
conversion patch does not implement that protocol, and does not resolve this
Herdr failure or Node 24's observed CLI failure. See
`pitfalls/herdr-server-spawn-invalid-argument.md` for the source-backed diagnosis.

Outcome: build and version stages succeeded; server/PTY/session/device stages
remain unaccepted. No iSH Herdr asset was added to the installer lock.

The socketpair conversion patch has a separate regression result: raw i386
socketcall STREAM+CLOEXEC / STREAM+CLOEXEC+NONBLOCK fails with error 93 on the
older CLI, and passes with preserved flags and EAGAIN behavior on the corrected
CLI. SEQPACKET still fails with EINVAL in both. See
`experiments/socketpair-probe.rs`; the libc wrapper's retry would mask this
conversion bug. This patch is not presented as the Herdr runtime fix.

All repository work is local and reviewable; no commit, push, device upgrade,
iOS signing or sideloading was performed. The SSH-only transfer bundle and
experimental binaries are private build artifacts. Actual device address and
authentication setup are still needed to continue the acceptance workflow.

## User-reported iPad follow-up (2026-09-08)

The user mounted Finder's iSH Documents directory using
`mount -t real "$(cat /proc/ish/documents)" /mnt/finder`, extracted the transfer
bundle into `~/ish-ssh-setup` and ran `sh setup-sshd.sh`.
OpenRC 0.43.3-r3 installed from the iSH Alpine 3.14 snapshot, followed by:

```text
[dotfiles] SSH prerequisite missing: /sbin/rc-status
```

Installer defect: `rc-status` is in `/bin`, while `rc-update` and `rc-service`
are in `/sbin`. This was verified by inspecting the official
[Alpine 3.14 x86 package](https://dl-cdn.alpinelinux.org/alpine/v3.14/main/x86/openrc-0.43.3-r3.apk)
archive. The fixture repeated the installer's incorrect assumption, so earlier
fixture checks did not catch it. Both now use the package's actual layout;
the SSH-only archive is rebuilt from the corrected source.

The failure occurs before the config/service seeds, host-key preparation and
default-runlevel registration. A restart alone cannot finish that preparation.
The user was given an in-place source fix (`sed` replacing `/sbin/rc-status`
with `/bin/rc-status`) followed by rerunning the same setup script. A manual
password change succeeded and need not be repeated. Device rerun, autostart and
SSH login remain pending; no device address has been provided yet.

The transferred hako binary opens normally according to the user. This confirms
reported device startup, not authentication or read/edit/shell-tool acceptance.
The transferred Herdr binary reproduces the exact server-spawn error 22 above.
No named session or PTY is accepted, and the CLI diagnosis is not a substitute
for running the minimal diagnostic on the device. Exact iSH/iPadOS builds and
device-side artifact hashes remain to be collected.

The next user report confirms SSH preparation now succeeds after the in-place
path correction: missing Ed25519 key generation completed, configuration
validation passed, and OpenRC registered `dotfiles-sshd` in `default`. The
script requested a complete iSH restart. Login and restart acceptance are still
pending; the password was already set manually.

The user also requested default-on Finder mounting in setup. It is integrated
as an independent `--finder on|off` selection plus `--prepare-finder`, a chezmoi
init prompt, saved state and an owned OpenRC service. The runtime helper lives
outside the source checkout, reads `/proc/ish/documents` every time, checks
`/proc/mounts`, adopts a correct manual mount and refuses to cover files,
symlinks or foreign/nested mounts. Disabling removes only autostart, never the
live mount. Manual Finder access is device-confirmed; automatic installation
and startup still need device acceptance. The default-on mount authorization
is recorded in AGENTS.md, and common core/manage/tests are mirrored to OpenWrt,
where the Finder flags are rejected without target changes.

The next SSH report confirms a complete iSH restart followed by successful
password-authenticated loopback login (`ssh localhost -p 22000`). This establishes
one restart/autostart plus local password login, not LAN reachability from the
Mac, key authentication, SFTP or the three-restart gate. The user then tried
`ifconfig` and received:

```text
ifconfig: /proc/net/dev: No such file or directory
ifconfig: ioctl 0x8912 failed: Not a tty
```

The device's Wi-Fi IPv4 address should be read in iPadOS Settings → Wi-Fi →
the connected network's Info button → IP Address. No address has been provided
yet. Device host-key fingerprints and authentication data are not copied into
this public research log.

## Direct SSH acceptance attempt (2026-09-08)

The user configured an SSH alias and authorized direct access. Strict known-host
checking and BatchMode public-key authentication succeeded, followed by remote
shell commands. Observed versions: iSH 1.3.2 (494), Alpine 3.14.3 and i686.
OpenRC reports `default`; `dotfiles-sshd` is started. The Finder helper is not
installed and the manual real mount was absent after the earlier app restart.
Agent executables are not on PATH or at the previously suggested root/ish-lab
locations; the known Finder transfer files still need checking after mounting.

A private staging directory was created under /tmp for the reviewed source
archive. SFTP closed before a successful transfer; a subsequent verbose attempt
showed `Connection timed out during banner exchange`. SSH streaming upload also
timed out before the banner. These failures are before SFTP negotiation and do
not establish a subsystem incompatibility. Finder installation has not run.
An independent SSH command succeeded between failures; a later retry with a
30-second connection deadline timed out again. The user was asked whether iSH
is in the foreground with the screen unlocked. Do not assume the cause is proven,
alter authentication, restart the live server or enable location keepalive.

The hako source review also found that initialization writes state before
handling --version. The maintainer probe now uses a scratch home/project and
cleared authentication environment, with a fixture testing write isolation,
environment isolation, cleanup and exit-code preservation. Runtime probes will
not read/copy device credentials. Fresh minimal Rust diagnostics were built from
experiments/ with the existing offline Rust 1.96.1 Linux toolchain. Both are
private i586 musl test artifacts; device execution remains pending. Their source
and binary SHA-256 values are recorded alongside the private binaries.

## Continued direct device testing

After the user reopened iSH, a single SSH connection streamed the reviewed
archive into a fresh private /tmp staging directory, checked its SHA-256, and
ran only `bootstrap.sh --prepare-finder`. The helper mounted `/mnt/finder`,
registered `dotfiles-finder` in `default`, and passed explicit OpenRC start and
status checks. OpenRC printed hardware-service and missing `/proc/filesystems`
warnings, but the owned helper/service returned success; unrelated services
were not changed. The transferred hako/Herdr hashes match the earlier artifacts.

Fresh Rust diagnostics in `private/ish-lab/device-diagnostics/` were streamed as
a compressed archive, individually hash-checked and run with 15-second limits.
Observed output:

```text
pre_exec=false exit=Some(0) output=child-ok
pre_exec=true error=Invalid argument (os error 22)
stream: available flags=passed
stream-cloexec: unavailable Protocol not supported (os error 93)
stream-flags: unavailable Protocol not supported (os error 93)
seqpacket: unavailable Invalid argument (os error 22)
```

The raw socket diagnostic exits 1 for the flagged STREAM failures. hako's
isolated version probe returns `hako-code v0.2.3`. No device credentials were
read/copied for these probes. The user's hako provider/login state is still
unconfirmed. Source checks also found SEQPACKET IPC in Rust 1.90/1.93; no older
toolchain rebuild was attempted or claimed to fix Herdr.

SFTP was isolated from the intermittent banner stalls by using an authenticated
SSH master connection: an exec channel passed, but an SFTP channel closed.
The external server with stderr/debug logging also closed after authentication.
Its `-Q requests` works, while direct startup with stdin closed exits 255 and
prints `unable to make the process undumpable`. OpenSSH's strict startup guard
requires PR_SET_DUMPABLE, absent from the investigated iSH implementation. See
`pitfalls/sftp-connection-closed.md`; no guard was removed or auth setting changed.

Legacy SCP (`scp -O`) upload/download passed byte comparison. SSH stdin streaming
already passed archive/binary hash checks. SSH PTY input/output and a 31x97
terminal-size check also passed. These provide a working test channel while
SFTP stays unsupported. The user was asked for another full app restart without
manual mounting to verify Finder autostart. Repeated boot acceptance is pending.
Temporary SSH masters were closed; the explicit staging path is stored only in
`private/ish-lab/active-device-staging.txt` for later cleanup or resumed tests.

## Finder app-restart confirmation

The user explicitly confirmed a full app restart with Finder already mounted.
The subsequent direct SSH check performed no mounting or service start. It found
OpenRC in `default`, Finder mounted, both services healthy, the Finder OpenRC
start marker updated, and the SSH log's server-start count advanced from two to
three. The hako/Herdr hashes remained identical to the transferred build artifacts.
This confirms one complete Finder app-restart cycle. The remaining repetitions
in the original three-restart plan are unrecorded; authenticated agent workflow
acceptance and SFTP support are not implied by this result.

## Herdr workaround research follow-up

The user asked whether the pre_exec/SEQPACKET blocker has a solution. A concrete
precedent was found in
[Rust #129654](https://github.com/rust-lang/rust/issues/129654): its ESXi reporter
[published a local std pipe revert](https://github.com/rust-lang/rust/issues/129654#issuecomment-2313274834)
and reported their example working. The change they reverted,
[Rust #113939](https://github.com/rust-lang/rust/pull/113939), merged on
2023-08-09 to transfer pidfds from child to parent through SEQPACKET/ancillary
data. The discussion does not provide a merged general fix or iSH validation.

Direct source checks of Rust 1.88, 1.96.1 and the current stable branch show
Linux still creating a SEQPACKET pair before the fork path, even when no pidfd
was requested. Other Unix targets use a pipe. Herdr's locked time 0.3.47 requires
Rust 1.88; ratatui 0.30 requires 1.86, so going back before the 2023 change would
also require dependency/API work. No older compiler build was attempted.

Preferred candidate for a future bounded prototype: rebuild only the iSH
application's Rust std with a reviewed pipe channel for non-pidfd spawning,
retain all pre_exec callbacks and exec-error/CLOEXEC semantics, and explicitly
reject unsupported pidfd requests. First test successful exec, callback failure,
nonexistent executable, EOF and descriptor behavior; then rebuild Herdr and test
PTY/session creation, input/output, resize and detach/attach. This is an engineering
proposal informed by the upstream precedent, not an implemented fix.

Herdr's daemon pre_exec calls setsid. Its vendored portable-pty also uses
pre_exec to reset signal state, establish a session and set the controlling TTY;
removing the daemon hook alone would not solve the full workflow. Implementing
proper SEQPACKET semantics in iSH is the alternative, but requires a new iSH
build and broader kernel work. Current iSH master still has no SEQPACKET case in
its socket type translator. The existing host-argument conversion patch remains
independent and insufficient.
