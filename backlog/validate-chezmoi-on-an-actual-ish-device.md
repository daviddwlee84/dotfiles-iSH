# Validate chezmoi on an actual iSH device

Status: pending device acceptance

## Context and evidence

The user transcript of 2026-09-07 confirms the original minimal bootstrap ran on
iSH's Alpine v3.14-2023-05-19 snapshot. It does not test this new source or chezmoi.
The official chezmoi v2.72.1 release has a linux_i386 tarball, locked with SHA-256
in config/assets.lock. Historical iSH Go reports describe emulator deadlocks;
a matching architecture and a passing --version probe cannot prove apply stability.

## Original first-version behavior (superseded below)

Default sh, optional explicit --manager chezmoi, no Alpine migration, no on-device
source compilation. Source files are shared between managers and parity-tested
with real chezmoi on a host. Existing old helper blocks remain authoritative.

## Resume / acceptance

Follow docs/verification.md on an actual backed-up iSH filesystem. Record iSH
build, iOS version, Alpine branch, binary version, shell startup and repeated
chezmoi diff/apply/update duration. Test suspend/restart and Files mount. Keep
explicit sh recovery available if the requested default fails on the emulator. A host Alpine
container is not this emulator. No remote credentials are recorded here.

## 2026-09-07 follow-up

User confirmed sh baseline completion and branch diagnostics. Alpine v3.14 has
chezmoi 2.0.16 and Starship 0.54.0; the former predates this source's workingTree
capability and is rejected by the new capability check. Explicit chezmoi uses
the locked i386 binary. Starship selection uses native apk + Bash, while ash
now has a builtin-only prompt. Actual iSH optional-tool execution remains pending.

2026-09-07 preference update: chezmoi is now the requested default with a Git source.
Actual iSH emulator acceptance remains pending; explicit `--manager sh` is the
recovery path if the locked binary fails its capability probe.
