# Local coding-agent experiments

**No local agent is accepted for automatic installation yet.** A host build,
container run, command-line emulator test and authenticated iPhone/iPad workflow
are separate verification levels. SSH setup provides the test channel.

2026-09-08 update: the custom Rust process/sleep standard library passes **18/18
cases on the original iPad App**. The rebuilt Herdr now passes CLI server, pane,
shell I/O, detach and same-pane reattach checks. Its complete binary is installed
at `~/.local/bin/herdr` on the original iPad with matching size/SHA-256 and a
successful version probe. CLI host-resize propagation and a recorded full iPad
Herdr workflow remain unaccepted.

## Environments and order

Keep the original filesystem and a backup. First test its imported Alpine 3.14
copy; separately test a verified **x86** Alpine 3.24.1 minirootfs using the
[system upgrade guide](system-upgrade.md). Do not mix branches or replace the
working environment's feeds. Alpine 3.18 is only a historical Node comparison.

1. **SSH:** follow [SSH setup](ssh-server.md). Test three complete app restarts,
   public-key/password login, PTY input and SFTP.
2. **hako-code:** build pinned C sources for 32-bit musl, test startup/TUI, then
   a cloud-model turn using read, edit and shell tools. Local models are excluded.
3. **Pi, then Gemini:** first verify Node file I/O, child processes, a worker and
   HTTPS. Satisfy the full dependency tree's Node requirements and provide working
   32-bit search tools. Optional PTY fallback is not a sandbox/isolation override.
4. **Herdr:** cross-build Rust plus Zig/libghostty-vt; test startup, one shell pane,
   input/output, resize, socket CLI, detach/attach, then an accepted agent. Keep
   minimal config rather than deploying the full Unix helper/plugin overlay.

Use a throwaway project. The user configures credentials locally; reports must
exclude tokens, passwords, private prompts and agent histories. Acceptance means
reading a file, making the requested edit, executing a simple shell command and
completing a follow-up turn. A version probe alone does not pass that gate.

## Repeatable probes

The maintainer-only hako recipe pins Zig 0.15.2 and the v0.2.3 source commit:

```sh
sh scripts/build-hako.sh --zig /path/to/zig --output /tmp/hako-i586
```

It creates a 32-bit static artifact, prints its hash, and does not install it.
Use a Zig download verified against its official checksum. `--source CHECKOUT`
can reuse a clean checkout of the exact pinned commit.

The maintainer-only Herdr recipe pins upstream v0.9.0 plus its Rust, rust-src,
Zig and reviewed compatibility patches. It runs on x86_64 Linux and emits the
binary, manifest, checksums and proposed `assets.lock` row without installing:

```sh
sh scripts/build-herdr-ish.sh --print-plan
sh scripts/build-herdr-ish.sh --version v0.9.0 --output /tmp/herdr-ish
```

The matching Actions workflow detects upstream releases weekly and builds only
by manual dispatch. Publishing requires an explicit original-device acceptance
confirmation. See [Herdr on iSH](herdr-ish.md).

After trusted public-key SSH setup, run from the Mac:

```sh
sh scripts/ish-probe.sh --host DEVICE_IP
sh scripts/ish-probe.sh --host DEVICE_IP --case node
sh scripts/ish-probe.sh --host DEVICE_IP --case hako
sh scripts/ish-probe.sh --host DEVICE_IP --case pi
sh scripts/ish-probe.sh --host DEVICE_IP --case gemini
sh scripts/ish-probe.sh --host DEVICE_IP --case herdr
```

Agent cases only check startup. Continue with interactive SSH workflow tests.
Record exact iSH/iOS/Alpine versions, source commits, patches, compiler versions,
binary hashes, elapsed time and relevant errors/opcodes. Never bypass checksum
failures or disable agent isolation to produce a passing result.

Official iSH and patched iSH need separate result rows. This round allows patched
**command-line emulator** testing; iOS signing and sideloading remain deferred.

## Starting evidence

| Candidate | Evidence | Independent device workflow |
|---|---|---|
| hako-code v0.2.3 | C/libc/pthread and curl; user confirms opening the transferred binary on iPad | Startup reported; authenticated tools pending |
| Pi 0.73.1 | Node; transitive version floor and ia32 downloader need checking | Pending |
| Gemini 0.58.0 | Node with child-process fallback; transitive version floor applies | Pending |
| Herdr v0.8.2 | Custom std passes 18/18 device cases; rebuilt CLI session supports pane I/O and reattach | Installed with exact hash/version verified; detailed iPad session and resize acceptance pending |
| Herdr v0.9.0 | Exact upstream commit and complete compatibility patch stack are locked; native build and CLI pane I/O/reattach pass | CLI resize fails; original-iPad scratch transfer/acceptance pending |

2026-09-08 host result: hako v0.2.3 builds with both Alpine GCC 10.3 and Zig
0.15.2, and both static binaries pass `--version` inside the iSH command-line
emulator at commit `d189985e5cc6d0e70629efeb31505b51a9ce78af`, using Alpine 3.24.1
x86. `/bin/sh`, `uname` and reading the Alpine version also pass there. This is
an emulator CLI result, not App Store iSH or authenticated agent acceptance.

[hako report](https://github.com/ish-app/ish/discussions/2801),
[Pi downloader](https://github.com/badlogic/pi-mono/blob/v0.73.1/packages/coding-agent/src/utils/tools-manager.ts),
[Gemini dependencies](https://github.com/google-gemini/gemini-cli/blob/v0.58.0/packages/core/package.json),
[Herdr build](https://github.com/herdrdev/herdr/blob/v0.8.2/build.rs).

The [Node 20.8.1 workaround](https://github.com/ish-app/ish/issues/2335#issuecomment-2264331674)
has a later [ada-libs correction](https://github.com/ish-app/ish/issues/2335#issuecomment-4034378900).
It does not satisfy the investigated agents' Undici 7.x Node floor of 20.18.1.
A [fork report](https://github.com/ish-app/ish/issues/2604#issuecomment-3448630596)
says adding `cvtdq2pd` lets Node run, without verifying a complete Gemini session.
[Tokio failures](https://github.com/ish-app/ish/issues/2447) affect reported i586
and i686 binaries; changing the target alone is insufficient.

Only a tool with a reproducible installation artifact and full device acceptance
may enter `--with hako,pi,gemini,herdr`; until then iSH installation is rejected.
Future assets must lock version, URL, architecture, size and SHA-256 together.
Working installed versions remain install-only.

Additional CLI findings: hako reaches its first-run provider selector, but has
not completed an authenticated turn. Node 24.18.1 passes the version probe yet
fails minimal JavaScript in the tested CLI builds (SIGSEGV in release; timeout
in debug). The `cvtdq2pd` patch does not resolve this case. Pi/Gemini remain gated
on a functioning runtime. Herdr's libghostty-vt cross-build for i586 succeeds;
the full Rust/runtime acceptance is separate.

Initial Herdr build result: the i586 executable links successfully with Rust's
bundled linker and self-contained libraries. It passes `--version` in both CLI
guest releases. Named-session startup fails with `failed to spawn herdr server:
Invalid argument (os error 22)`. Rust 1.96.1's Linux `pre_exec` path needs
`SOCK_SEQPACKET`, which the investigated iSH does not support. Session/PTY and
actual-device acceptance remain pending; no Herdr installer is enabled.

## User-reported iPad results (2026-09-08)

Finder file sharing was accessed successfully with
`mount -t real "$(cat /proc/ish/documents)" /mnt/finder`. The user reports that
the transferred hako binary opens normally. Authentication, a model turn and
read/edit/shell tools have not yet been reported as passing. The initially
transferred stock-std Herdr binary failed with `herdr: failed to spawn herdr
server: Invalid argument (os error 22)`, matching the CLI symptom above. The
later compatibility build was transferred in full, promoted atomically to
`~/.local/bin/herdr`, and verified as 21,556,492 bytes with SHA-256
`3ede5a4aed39470a67a66453b305f086bf51275c03d7bd0c16c513beb3dd9809`.
The user reports that it runs; a detailed pane/resize/agent transcript is pending.

SSH setup installed OpenRC 0.43.3-r3 from the iSH Alpine 3.14 snapshot, then
stopped at `SSH prerequisite missing: /sbin/rc-status`. The installer and its
fixture had the wrong path: the Alpine package installs `/bin/rc-status`.
After the path correction, the user reran setup successfully: the Ed25519 host
key was generated, config validation passed, and `dotfiles-sshd` was added to
the default runlevel. Setup requested a complete app restart. The user confirmed
one complete app restart and password-authenticated `ssh localhost -p 22000`,
then password login from the Mac. Direct maintainer public-key login and shell
commands also succeeded, identifying iSH 1.3.2 (494), Alpine 3.14.3 and i686.
Some later connections timed out before receiving the SSH banner; the user
reopened iSH and direct testing continued. The repeated-restart gate and exact
iPadOS version remain pending.

[Finder mounting](finder-files.md) is now a separate default-on setup option,
with a dynamic-path OpenRC helper. Its installation, mount, default-runlevel
registration and explicit service start now pass on the iPad. One full app
restart without manual mounting also passed, with remote service/mount and
binary-hash checks. Further repetitions remain unrecorded.

hako's [initialization order](https://github.com/mithraeums/hako-code/blob/452291112f8a639aac5059070fb933e2d5bbb28b/hako.c#L11218)
loads and saves user state before parsing `--version`. Version probes therefore
use an empty scratch HOME/project and cleared auth environment. This verifies
startup without touching the user's hako configuration or authenticating a model.

## Direct runtime results (2026-09-08)

| Check | Device result |
|---|---|
| SSH key authentication and remote commands | Passed |
| SSH PTY input/output and terminal sizing | Passed |
| SSH archive/binary transfer with SHA-256 verification | Passed |
| Legacy SCP (`scp -O`) upload/download | Byte comparison passed |
| Internal and external SFTP | Failed; missing `PR_SET_DUMPABLE` startup protection support |
| Finder helper installation and OpenRC start | Passed, including one full app restart without manual mounting |
| Transferred hako and Herdr hashes | Match the build artifacts |
| hako v0.2.3 isolated version probe | Passed; authenticated workflow pending |
| Rust ordinary process spawning | Passed |
| Original Rust `pre_exec` / SEQPACKET | Error 22, matching the original Herdr blocker |
| Custom Rust process/sleep std | 18/18 passed on the original App; full Herdr session remains pending |
| Raw flagged STREAM socketpair | Error 93; plain STREAM works |

SFTP's failure is separate from pre-authentication banner stalls; see
[SSH file transfer](ssh-server.md). Rust diagnostics were freshly built from the
checked-in sources with Rust 1.96.1, verified after transfer, and run with bounded
timeouts. No patched iSH kernel or replacement system libraries were installed.

## Chezmoi manager check

The device currently records `manager=sh`, with no chezmoi executable installed.
That explains `-ash: chezmoi: not found`: sh deployment and the SSH/Finder
preparation paths do not install it, and reloading `.profile` cannot fix absence.

The locked chezmoi v2.72.1 i386 candidate passed archive/binary SHA-256 checks in
a scratch directory. Its version command exited 0, but the source-layout template
printed `supported` without completing. The device's 15-second SIGKILL wrapper
did not return before the Mac's 120-second deadline. SSH subsequently refused
connections. The user reported an App crash and reopened iSH; SSH then recovered
with manager=sh and SSH/Finder selections intact. The exact crash mechanism is
not established.

The CLI comparison also failed: seven cases ended with emulator SIGSEGV and one
timed out with Go runtime errors. Limiting Go to one processor or disabling
asynchronous preemption did not yield a passing process. No candidate was
installed, no runtime setting was persisted, and the working sh manager was
retained. See `experiments/chezmoi/results.json` and the
[timeout pitfall](https://github.com/daviddwlee84/dotfiles-iSH/blob/main/pitfalls/chezmoi-probe-waits-past-timeout.md).
Full setup should only migrate after the locked candidate can complete its checks;
printed output alone is insufficient.

Older packages do not provide a safe fallback. Official i386 releases 2.9.1,
2.20.0 and 2.40.0 failed with signal-stack/GC errors, timeouts or SIGSEGV.
Alpine 3.14's packaged 2.0.16-r3 occasionally completed a version command with
single-processor or asynchronous-preemption settings, but repeated version,
template and help commands still crashed. It also predates the
`.chezmoi.workingTree` capability introduced in 2.9.1.

An isolated CLI was rebuilt with iSH upstream's open SIGURG and futex-bitset
fixes ([PR 2744](https://github.com/ish-app/ish/pull/2744) and
[PR 2775](https://github.com/ish-app/ish/pull/2775)). Both 2.72.1 and Alpine
2.0.16 remained non-deterministic. `apk add chezmoi` can therefore install a
file, but it does not establish a usable manager on this App. Keep `manager=sh`;
the complete matrix is in `experiments/chezmoi/version-matrix.json`.

## Experimental iSH Rust standard library

The private Rust 1.96.1 build now covers the process-spawn and relative-sleep
gaps. The expanded variant passed **18/18 cases on the original iPad App**
(iSH 1.3.2 (494), Alpine 3.14.3), including interrupted sleep and concurrent
spawning, with a 30-second deadline per case and SSH exit 0. The same native
macOS compiler artifact passed all 18 in the CLI. Device controls still show
stock std failing `pre_exec` with EINVAL and relative sleep with `Bad system call`.
The earlier 14-case process-only result remains a separate historical revision.
Full Herdr session acceptance is still pending; see `experiments/rust-std/results.json`.

Two patches live in `experiments/patches/`:

- `rust-1.96.1-ish-process-pipe.patch` selects the existing CLOEXEC pipe error
  channel only under `ish_compat`; all child callbacks remain intact. Explicit
  pidfd requests return `Unsupported`. This is intentionally stricter than the
  upstream advisory pidfd option.
- `rust-1.96.1-ish-thread-sleep.patch` selects the existing relative `nanosleep`
  fallback because iSH lacks `clock_nanosleep`. The test accepts oversleep and
  does not claim that iSH fully implements interrupted-nanosleep semantics.

Use a separate Rust 1.96.1 sysroot with the matching verified rust-src component;
never replace the host toolchain or device libraries. The component SHA-256 is
`b343b6553bc772225f6a2b5be5055017f29794dcf4e08020366b27a0a40fc1c2`.
Apply both patches from the source root (`lib/rustlib/src/rust`). The iSH cfg
requires 32-bit x86 Linux musl and leaves other builds inactive. The maintainer
container build uses Rust's bundled linker and the existing i586 Herdr port:

```sh
export PATH=/toolchain/bin:$PATH
export RUSTC_BOOTSTRAP=1
export RUSTFLAGS='--cfg ish_compat --check-cfg=cfg(ish_compat) -C linker-flavor=ld.lld -C linker=/toolchain/lib/rustlib/aarch64-unknown-linux-gnu/bin/rust-lld -C link-self-contained=yes'
cargo build -Z build-std=std,panic_unwind --locked --offline --release \
  --target-dir /target --target i586-unknown-linux-musl --bin herdr -j1
```

`/target` must be an empty directory created on the host before mounting it.
Reusing an earlier Cargo target after editing rust-src linked stale std artifacts
in this experiment; rebuild in a fresh directory for each std patch revision.
The command keeps the release profile and uses one build job to limit memory
pressure during the large Herdr compilation.

A native macOS maintainer build can use a separate Rust 1.96.1
`aarch64-apple-darwin` compiler/host-std with the same i586 target and source
patches. Select its bundled `aarch64-apple-darwin/bin/rust-lld` instead of the
Linux-host linker shown above, and use the macOS Zig 0.15.2 binary. This avoids
the memory ceiling of a small Docker VM; the output is still a Linux ELF32
executable. Component provenance and runtime results are recorded in
`experiments/rust-std/results.json`.

For the historical macOS build, Zig 0.15.2's build runner could not link system
symbols. `herdr-i586-prebuilt-ghostty.patch` therefore adds an explicit,
target/size/SHA-256-checked `HERDR_ISH_GHOSTTY_ARCHIVE` option after the i586
port. The first 1,224,644-byte archive (`2420a175…e9196`) is retained only as
provenance: it has the broken i386 by-value ABI and is not an installation
candidate. The current guard accepts only the separate iSH-compatible archive:
1,237,632 bytes, SHA-256
`a8c7123d6e8e6df0cab93cd54f21d060953fa628b0474b74a510463167ea2222`.
Default builds still invoke Zig; the archive path is maintainer-explicit.

`RUSTC_BOOTSTRAP` enables an unstable build feature only for this experiment;
this is not an upstream-supported replacement toolchain. Cargo's
[build-std documentation](https://doc.rust-lang.org/cargo/reference/unstable.html#build-std)
describes the feature and normally requires nightly. Herdr's original lockfile,
32-bit FFI assertions, vendored PTY initialization and scalar libghostty build
remain in place. No automatic installer is enabled.

`experiments/rust-process-compat-probe.rs` supplies `--list` and `--case NAME`.
Compile it with the rebuilt std and `--cfg ish_pidfd_probe` to add the two custom
pidfd rejection checks; run each case under an outer 30-second kill deadline.
Stock-std builds omit that cfg, because upstream has a different pidfd contract.

## Herdr ABI and PTY checks

The minimal C/Zig reduction confirms that Zig 0.15.2 mis-lowers five i386
by-value aggregate APIs even though their memory-layout assertions match. The C
wrapper preserves the public prototypes and passes all 127 assertions in Linux.
With only Ghostty's normal libc allocator enabled, the five terminal suites time
out in iSH. `ghostty-vt-libc-option.patch` adds an x86 Linux musl-only iSH flag
that also moves terminal page backing to page-aligned libc allocations and
explicitly clears them. That archive passes all 127 assertions in both Linux
binfmt and the iSH CLI. See `experiments/zig-i386-abi/` and
`experiments/ghostty-allocator/results.json`.

Herdr then required a separate local-socket compatibility path. On iSH it uses
Rust UnixListener/UnixStream and treats unsupported/invalid socket receive-timeout
configuration as best-effort; other builds retain `interprocess`. The final
CLI binary (`3ede5a4a…d9809`) starts its server and pane, completes the client
handshake, passes shell input/output, detaches, and reattaches to the same pane
and shell PID. Its host PTY resize did not propagate: the pane remained 43x105
after the host changed from 44x132 to 55x172. The owned server still stopped
cleanly. The full binary is now installed on the original iPad and passes its
hash/version checks; detailed session and resize acceptance are still pending.
See `experiments/herdr/results.json`.

The same port has been updated to Herdr v0.9.0 commit
`b99002ac99b09e00b4ca692436cb15a6b0d676f1`. The 24,286,088-byte ELF32 binary
(`fe35d658…672af`) builds successfully and reports `herdr 0.9.0` in the CLI
guest. Its named-session, pane I/O, detach, same-PID reattach and owned-server
stop checks pass. Host resize remains stale at 43x105, matching the v0.8.2 CLI
limitation. The original-iPad scratch transfer is pending because SSH timed out
during banner exchange; v0.8.2 remains installed. See
`experiments/herdr/v0.9.0-results.json`.

The actual vendored `portable-pty` and matching custom std were also tested in a
fresh Alpine 3.14.10 CLI guest. `experiments/portable-pty-probe.rs` receives the
expected output and terminal size, then its default blocking EOF read times out
at 30 seconds. `--wait-after-output` instead waits/reaps after the known completion
marker and passes in 24 ms. PTY opening, spawning, output and child waiting pass
without changing library initialization. Herdr uses nonblocking PTY reads, so
this blocking-EOF limitation does not explain its startup failure; final-output
draining and pane cleanup still require acceptance.

## Parallel SEQPACKET kernel prototype

`experiments/patches/ish-seqpacket.patch` implements an in-memory AF_UNIX record
transport instead of forwarding an unsupported Darwin socket type. Apply it to
iSH `d189985e5cc6d0e70629efeb31505b51a9ce78af` after the existing
`ish-socketpair-host-args.patch`. It includes socketpair and listener paths,
record boundaries, EOF/shutdown, nonblocking readiness, timeouts, and ordinary
file/pipe descriptor transfer. The C probe and machine-readable results are in
`experiments/seqpacket/`.

The native Linux reference passes 46/46 cases; the patched macOS CLI passes
45/46. The remaining case is socket-descriptor transfer through SCM_RIGHTS,
which deliberately returns EOPNOTSUPP until Unix socket-reference cycle
collection exists. Original Rust std process tests pass on this kernel, so the
initial spawn dependency is resolved independently of the custom std route.
That stock-std Herdr attempt then reached missing `clock_nanosleep`; the custom
std sleep patch above covers this separate gap without a device kernel change.

This is **not complete Linux support**. Shared-descriptor concurrent-close
lifetime handling, complete autobind/credential rules, remaining options/ioctls
and edge-triggered epoll behavior still need work. Passing these bounded tests
does not prove those paths. Xcode source entries exist, but no Xcode build,
signing, sideload or iPad kernel replacement was performed. Keep this prototype
in the CLI lab; the standard-library experiment runs on the original App.
