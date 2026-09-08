# Verification and maintenance

Run `just check` on a maintainer machine: ShellCheck, Bats and strict bilingual
MkDocs. Target setup does not require these tools. Tests isolate HOME, XDG dirs,
chezmoi config and fake package commands; real-device paths are never redirected
without the explicit fixture sentinel and matching temporary HOME.

The suite covers manager equivalence with actual chezmoi, repeated apply, existing
SSH/tmux/Git/profile content, legacy iSH helpers, target detection, apk/opkg,
branch parsing, offline setup, dry-run, checksum rejection and failed installers.
CI additionally probes locked Linux assets in disposable musl containers on
x86_64/ARM64. A version probe verifies executable startup, not agent authentication,
process isolation, emulator compatibility, low-memory stability or a real session.

## Device acceptance

Record date, device, OS/build, architecture, package manager, selected manager,
free RAM/storage and exact tool versions. Then check:

1. Fresh bootstrap; restart a login shell; `git --version`, `ssh -V`, `tmux -V`.
2. Reapply twice; preserve existing configs and your local overrides.
3. Connect to a known SSH host with normal host-key verification; create, detach
   and resume a tmux session. iSH must also test suspension and a cancelled Files picker.
4. If chosen, test chezmoi diff/apply; iSH needs repeated real emulator runs.
5. OpenWrt: verify routing, Wi-Fi and existing services remain operational, and
   measure resource use while a selected Herdr/SpecStory/Codex session runs.
6. Test agents manually with your own credentials. No authentication material or
   private prompts belong in logs or the public repository. Do not disable
   agent isolation to turn an unsupported runtime into a claimed success.

**Current status (2026-09-07):** the user confirmed the sh baseline on iSH's
v3.14 snapshot. New chezmoi and Starship paths still await iSH device acceptance.

The shared shell core/tests/assets lock are copied in the two lightweight repos;
changes to their shared behavior must be mirrored. Package feeds and user configs
are platform-specific. Maintainer commands and release assets never auto-upgrade.

chezmoi x86_64 uses the explicitly named `linux-musl_amd64` asset; upstream
`linux_amd64` aliases the glibc build and cannot be used as the router default.

Git integration fixtures additionally cover snapshot backups, tracking main, a real
upstream commit followed by plain chezmoi update/apply, offline failure, and
preserving existing/custom chezmoi configuration.

Startup probes now use SIGKILL after 15 seconds, with distinct download/hash/
extract/version/template stages. A regression test runs a process that ignores
TERM and verifies it is killed. This does not establish iSH emulator compatibility.

## SSH and local-agent work (2026-09-08)

The SSH fixture suite covers default selection, init/CLI precedence, independent
recovery, create-once ownership, missing keys, explicit default runlevel, startup
failure and preserving active sessions when autostart is disabled. Native Alpine
OpenSSH accepts the config. The iSH CLI guest also passes Ed25519 generation and
config validation. Actual-device observations are recorded separately below.

The first user-reported iPad run exposed an incorrect `/sbin/rc-status` path
after OpenRC installation, before service setup. The installer and fixture now
use Alpine's `/bin/rc-status`. The user then successfully reran preparation,
including key generation, config validation and default-runlevel registration.
The user then confirmed one complete app restart followed by successful
password-authenticated `ssh localhost -p 22000`. The user also logged in from
the Mac with a password; the maintainer then directly authenticated with a public
key and ran remote shell commands. The device reports iSH 1.3.2 (494), Alpine
3.14.3, i686 and OpenRC default, with SSH started. Some later connections stalled
before the banner; the user reopened iSH and connectivity returned. That
intermittent issue remains unconfirmed. iPadOS version is not yet recorded.
The user also confirms hako opens. The initial stock-std Herdr reproduced server
spawn error 22; the later compatibility binary was installed at
`~/.local/bin/herdr` with exact size/hash and version verified, and the user
reports that it runs. Detailed session/resize and authenticated agent-workflow
acceptance remain pending.

Subsequent direct checks passed SSH PTY input/output and terminal sizing, legacy
SCP upload/download byte comparison, and SHA-256-verified SSH archive/binary
transfers. Both SFTP server modes fail after authentication; direct startup
identified the missing `PR_SET_DUMPABLE` capability. SFTP remains unsupported;
the original full SSH/SFTP/restart acceptance gate is not claimed complete.

The Finder helper and service are now installed on the iPad. Mounting, OpenRC
registration and explicit service start passed; the hako/Herdr transfer hashes
match the build artifacts. After the user fully reopened iSH without manually
mounting, direct SSH checks confirmed Finder mounted, both services healthy,
the Finder OpenRC start marker updated, and the SSH startup log count increased
from two to three. The binary hashes still match. This is one verified Finder
app-restart cycle; further planned repetitions remain unrecorded.
hako's isolated version check returns v0.2.3. Fresh Rust diagnostics confirm
ordinary process spawning works, `pre_exec` fails with error 22, flagged STREAM
socketpairs fail with error 93, and SEQPACKET fails with error 22 on the device.

Version probes now isolate HOME, XDG paths, cwd and authentication environment.
hako v0.2.3 loads/saves state before parsing `--version`; a fixture checks that
a similarly behaving agent cannot change the caller's home/project state or
inherit auth variables, and that scratch files are removed on success and failure.

Finder fixtures cover setup/init defaults, saved opt-out, adoption of a correct
manual mount, repeated setup, hidden-file/symlink/foreign-mount preservation,
mount failures and a boot helper rereading a relocated Documents path without
the checkout. Manual mounting and one automatic mount after a full app restart
are now device-confirmed. See [Finder files](finder-files.md).

See [SSH server](ssh-server.md) and [experiments](experiments.md) for the separate
runtime and authenticated-workflow gates. New agent installers remain closed
until those gates pass on the actual device.
