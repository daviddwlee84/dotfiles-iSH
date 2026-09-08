# Local coding-agent experiments

**No local agent is accepted for automatic installation yet.** A host build,
container run, command-line emulator test and authenticated iPhone/iPad workflow
are separate verification levels. SSH setup provides the test channel.

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
| Herdr v0.8.2 | i586 port builds; user reproduces server spawn error 22 on iPad | Blocked at server startup |

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

Final Herdr build result: the i586 executable links successfully with Rust's
bundled linker and self-contained libraries. It passes `--version` in both CLI
guest releases. Named-session startup fails with `failed to spawn herdr server:
Invalid argument (os error 22)`. Rust 1.96.1's Linux `pre_exec` path needs
`SOCK_SEQPACKET`, which the investigated iSH does not support. Session/PTY and
actual-device acceptance remain pending; no Herdr installer is enabled.

## User-reported iPad results (2026-09-08)

Finder file sharing was accessed successfully with
`mount -t real "$(cat /proc/ish/documents)" /mnt/finder`. The user reports that
the transferred hako binary opens normally. Authentication, a model turn and
read/edit/shell tools have not yet been reported as passing. The transferred
Herdr binary fails with `herdr: failed to spawn herdr server: Invalid argument
(os error 22)`, matching the CLI symptom above; no session starts.

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
| Rust `pre_exec` / SEQPACKET | Error 22, matching the Herdr blocker |
| Raw flagged STREAM socketpair | Error 93; plain STREAM works |

SFTP's failure is separate from pre-authentication banner stalls; see
[SSH file transfer](ssh-server.md). Rust diagnostics were freshly built from the
checked-in sources with Rust 1.96.1, verified after transfer, and run with bounded
timeouts. No patched iSH kernel or replacement system libraries were installed.
