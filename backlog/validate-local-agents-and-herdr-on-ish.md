# Validate local agents and Herdr on iSH

**Status**: in progress; SSH/Finder and Rust std device checks passed; Herdr CLI session works except resize, original-iPad workflow pending
**Effort**: L
**Related**: `TODO.md`, `docs/ssh-server.md`, `docs/finder-files.md`, `docs/experiments.md`

## Current state

SSH key/password login, PTY checks, verified SSH streams and legacy SCP work on
the iPad. Finder installation and one complete app restart without a manual
mount passed. SFTP fails its required PR_SET_DUMPABLE startup guard. hako's
version runs; provider authentication and full read/edit/shell turns are still
unconfirmed. Herdr's original SEQPACKET/process failure was reproduced on the device.
The experimental Rust std process and sleep patches now pass 18/18 cases on
that same original App and in the CLI; missing clock_nanosleep is covered by
the scoped nanosleep fallback. A parallel kernel SEQPACKET prototype passes
stock-std process cases in the CLI. The Zig i386 C ABI wrapper plus an explicit
iSH libc/page allocator now passes all 127 Ghostty API assertions in Linux and
the iSH CLI. Herdr's iSH local-socket fallbacks then enable server startup, pane
I/O, detach and same-pane reattach. CLI host-resize propagation remains stale,
and the original-iPad Herdr workflow is pending because SSH timed out before
scratch upload. The installer remains disabled.
The device still uses manager=sh and has no chezmoi binary. The locked v2.72.1
candidate prints its source-layout result but does not finish on the device;
CLI comparisons also fail. No binary was installed or manager changed.
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

## Compatibility experiments after checkpoint commits

User requested a checkpoint commit followed by parallel Rust std and kernel
experiments. iSH checkpoint: `2506416`; mirrored OpenWrt checkpoint: `3c392df`.
Both passed staged secret scans and commit hooks. Nothing was pushed. The format
hook excludes unified patch files because their empty context lines require a
space prefix; all four checkpoint patches reverse-applied to tested sources.

Rust 1.96.1 sources came from the official 2026-06-30 rust-src component:
`https://static.rust-lang.org/dist/2026-06-30/rust-src-1.96.1.tar.xz`.
SHA-256: `b343b6553bc772225f6a2b5be5055017f29794dcf4e08020366b27a0a40fc1c2`.
The distribution manifest was verified against its published SHA-256
`87eb76c53073e72b766083bed5530820694253b832a762d8385bda5759f03975`.
A private copy of the Linux toolchain was used; host/global rustup was untouched.
The std Cargo.lock SHA-256 is
`c7fbe8811bd7b2a3737deb1bc5d1ec2ee6d631bc00221d3d8a58d05814b3e965`.
All 40 registry dependencies were verified against that lock; only public cache
state was written. Downloads from a mirror were accepted only after matching
those checksums. Builds then ran offline.

The first process-only custom std artifact passed all 14 per-case device probes
on iSH 1.3.2 (494), Alpine 3.14.3, with SSH exit 0. Stock std's normal-spawn
control passed and pre-exec-success failed with EINVAL. The corresponding CLI
also printed all 14 passes, but the aggregate shell wrapper ended with host
SIGTERM; the device's clean exit is the stronger result. Process probe SHA-256:
`42ee007ccb0f4e9f96b9b7c56e58241cf2b8284b848ca1ae9d5fed206cd42698`.
These are historical process-only artifacts; later probes add sleep coverage.

The kernel branch's unchanged-stock-std Herdr progressed past spawn, then hit:

```text
assertion `left == right` failed
  left: 38
 right: 4
```

The assertion is in `library/std/src/sys/thread/unix.rs:581`.
Rust 1.96.1 uses clock_nanosleep; iSH calls.c has only sys_nanosleep at slot162.
This is a separate capability gap from SEQPACKET. The next std patch selects the
existing relative nanosleep fallback only for the private iSH cfg. iSH's existing
nanosleep implementation does not copy remaining time on EINTR, so interruption
behavior must be measured; no claim of full syscall conformance is implied.


Kernel prototype handoff: `experiments/patches/ish-seqpacket.patch`, after the
existing host-args patch, applies cleanly to the pinned base and matches all nine
compiled source files. `experiments/seqpacket/results.json` records source,
artifact hashes, individual cases, review fixes and remaining limits. Native
Linux 46/46; patched CLI 45/46 (socket SCM_RIGHTS intentionally unsupported).
Missing Unix socket-reference cycle collection and borrowed-fd syscall lifetime
handling prevent a complete-support or production-ready claim. No App was built
or installed. The independent review also prompted ordinary readv/ESPIPE,
listener ioctl, backlog wakeup and credential fixes before the final matrix.

The std sleep patch plus process patch passes 18/18 expanded CLI cases with host
exit 0, including SIGUSR1-interrupted sleep and concurrent pre_exec. A stock-std
control reproduces the ENOSYS 38/EINTR 4 panic. The first 18-case device attempt
could not get an SSH banner; the previous 14-case actual-device result remains
valid and separate. Herdr is rebuilding with both std patches.


A resumed Herdr Cargo target reused the process-only std after rust-src changed:
the resulting daemon/API started, but the client and stop command still panicked
at old thread/unix.rs line 581. That artifact is rejected and kept only as a
private diagnostic. Cold builds must use a host-created fresh output directory;
Docker's implicit creation of a missing `/var`-aliased source directory failed
with build-script permission denied and did not create the expected host path.
Precreating the directory and resolving the bind source fixed that build setup.
A trial Herdr opt-level 1 compilation then ended with rustc SIGKILL; the next
attempt returns to the previously successful default release profile with -j1.
No host Docker memory settings or unrelated containers were changed.

The fresh Herdr target's std artifact was independently tested before the long
main compile: direct rustc injection of matching std/core/alloc/builtins/unwind
rlibs passed sleep-relative and sleep-interrupted, both exit 0. The std SHA-256 is
`ad0a73a7722ec41ab132764a4a689a05e6ac7d95e6e5b2eefd8ff5adea485729`, stable before
and after probe compilation. This rules out the earlier stale-sleep artifact
for this target; the Herdr binary still needs its own runtime test.

## Original iPad expanded std acceptance and Herdr follow-up (2026-09-08)

After the earlier SSH banner timeout, the native macOS compiler variant was
transferred with its SHA-256 checked and passed all 18 per-case tests on the
original iSH 1.3.2 (494), Alpine 3.14.3 App. Each case had a 30-second deadline;
SSH exited 0. The probe SHA-256 is
`5b842353f621260517950a6c2c595ec0a583586e65bcfbda9854f8dcd1b7f062`
(1,480,092 bytes). This adds sleep-zero, relative/interrupted sleep and concurrent
pre_exec to the earlier 14-case revision. Stock controls still pass normal spawn,
fail pre_exec with EINVAL, and terminate relative sleep with `Bad system call`.
No device kernel or system libraries were replaced. The same native-host artifact
passed all 18 in the CLI; `experiments/rust-std/results.json` records both levels.

The fresh native Herdr binary then built and passed its version probe, but its
client did not become ready at first-pane initialization. A bounded C/Zig
reduction reproduced incorrect i386 by-value aggregate arguments both in Linux
container execution and the iSH CLI, while C-by-value and Zig-by-pointer controls
passed. This is separate from struct memory layout and the now-working std path.
See `experiments/zig-i386-abi/results.json`.

The historical 1,224,644-byte Ghostty archive with SHA-256
`2420a175e61fb0f02c1f51ece791b5391a15fb0d5b9712af56ca0b98c92e9196`
is therefore known ABI-broken and retained only as build provenance, not an
installation candidate. A separate C wrapper preserves public prototypes and
passes 127 API assertions across six suites in Linux Docker i386 binfmt execution.
In iSH, five mouse assertions pass; the other five suites terminate with SIGSEGV
before their first constructor-result assertion. Constructor diagnosis remains
open. The wrapper result is not full Herdr or iPad acceptance; see
`experiments/zig-i386-abi/ghostty-api-results.json`.

The actual vendored portable-pty rlib and matching native-target std were linked
directly into `experiments/portable-pty-probe.rs`, preserving all child setup.
In a fresh Alpine 3.14.10 CLI guest, the default mode receives
`PTY_READY\r\n40 120\r\nPTY_DONE\r\n`, then blocks waiting for EOF until its
30-second deadline. With `--wait-after-output`, the same output is followed by
successful child wait/reaping and a pass in 24 ms. Herdr's Unix actor sets
O_NONBLOCK, so this blocking EOF observation does not explain first-pane startup.
Final-output draining and pane cleanup still need acceptance. No Herdr installer
has been enabled.

## iSH allocator and local-socket acceptance (2026-09-08)

The public-prototype C ABI bridge passed 127 assertions in Linux but the five
terminal-creating suites still failed in the iSH CLI. Selecting Ghostty's normal
libc default allocator changed those failures from SIGSEGV to 45-second timeouts:
terminal page backing still used direct mappings. The follow-up opt-in build is
restricted to x86 Linux musl, links libc, uses page-aligned libc allocations for
the terminal memory pool and `Page` backing, and explicitly clears those pages.
It passed all 127 assertions in both Linux Docker binfmt and the iSH CLI. Archive
SHA-256: `a8c7123d6e8e6df0cab93cd54f21d060953fa628b0474b74a510463167ea2222`,
1,237,632 bytes. Results: `experiments/ghostty-allocator/results.json`.

The first rebuilt Herdr then started its API server and pane and returned the
expected shell output, but thin-client setup exposed iSH socket compatibility
gaps. The final iSH branch uses Rust UnixListener/UnixStream, omits a redundant
`set_nonblocking(false)` whose `interprocess` Linux implementation uses FIONBIO,
and treats InvalidInput/Unsupported receive-timeout options as best-effort for
client protocol and API compatibility checks. Non-iSH builds retain the original
paths.

Final binary SHA-256:
`3ede5a4aed39470a67a66453b305f086bf51275c03d7bd0c16c513beb3dd9809`,
21,556,492 bytes. A fresh CLI guest passed server start, client handshake, shell
input/output, Ctrl+B then q detach, server/pane survival, reattach with the same
shell PID, second detach and owned-server stop. Host PTY resize did not propagate:
the pane remained 43x105 after host resize from 44x132 to 55x172. That is a CLI
bridge result, not evidence about SSH PTY or iPad UI resize. Original-iPad scratch
upload was attempted only after these gates, but SSH timed out before transfer;
no binary was installed or existing Finder file replaced. Results:
`experiments/herdr/results.json`.


## Chezmoi device recheck (2026-09-08)

The missing command is consistent with manager=sh, not only a stale PATH.
The locked v2.72.1 archive and binary passed transferred SHA-256 checks in an
isolated scratch HOME. `--version` exited 0; the template printed `supported`
but did not finish, including after the 15-second SIGKILL deadline. The SSH
client's outer 120-second deadline expired. SSH later refused connections;
causality and the exact App failure mechanism remain unconfirmed. The user was
asked to reopen iSH, then confirmed the App had crashed and was reopened. SSH
recovered with manager=sh, sshd=on, finder=on and no chezmoi binary. No candidate
was installed and no manager state changed.

Eight CLI comparisons using the same binary also failed: seven emulator SIGSEGV
exits and one Go-runtime-error timeout. GOMAXPROCS=1 and asyncpreemptoff=1 did not
produce a passing process. They remain transient diagnostic settings. Results
are in `experiments/chezmoi/results.json`; retain sh until a compatible binary
passes checks and a full workflow can be validated. Plain version/template output
is not acceptance. The separate kernel crash diagnostic branch was stopped after
automatic review rejected it for possible cybersecurity risk; no result from
that incomplete branch is counted as a compatibility pass.

The follow-up matrix tested upstream i386 2.9.1, 2.20.0 and 2.40.0 plus Alpine
3.14's 2.0.16-r3. All failed repeatable clean-exit gates. The Alpine package was
occasionally able to print a version and exit 0 with single-processor or disabled
async-preemption settings, but repeats and template/help paths still timed out or
crashed. It also lacks `.chezmoi.workingTree`, introduced in 2.9.1.

For an upstream-kernel comparison, a separate CLI at the pinned iSH base was
rebuilt with open PR 2744 (SIGURG handler registration) and PR 2775 (futex bitset
operations). Modern 2.72.1 and Alpine 2.0.16 still failed in Go runtime/GC paths.
This rules out package pinning and those two kernel fixes as sufficient solutions.
The device remains `manager=sh`; no chezmoi candidate was installed. Full hashes
and case summaries are in `experiments/chezmoi/version-matrix.json`.
