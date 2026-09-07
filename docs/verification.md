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

**Current status:** no iPhone or Raspberry Pi deployment was performed by this
repository's bootstrap during the extraction. Host/CI checks are recorded separately
from device acceptance. Pending experiments are indexed in the repository TODO.

The shared shell core/tests/assets lock are copied in the two lightweight repos;
changes to their shared behavior must be mirrored. Package feeds and user configs
are platform-specific. Maintainer commands and release assets never auto-upgrade.

chezmoi x86_64 uses the explicitly named `linux-musl_amd64` asset; upstream
`linux_amd64` aliases the glibc build and cannot be used as the router default.
