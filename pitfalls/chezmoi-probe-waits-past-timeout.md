# Chezmoi probe waits past its timeout

**First seen:** 2026-09-07  
**Affects:** iSH 1.3.2 / Alpine 3.14 snapshot, chezmoi 2.72.1 i386  
**Status:** timeout behavior fixed; actual Go runtime compatibility unresolved

## Symptom

The user waited more than five minutes, then interrupted:

```text
[dotfiles] chezmoi v2.72.1 (i386); checking storage before download
^C[dotfiles] chezmoi failed its bounded compatibility check; not installed
```

## Cause and limits

The old installer hid all download/hash/extract/probe stages behind one status
line. Its `timeout 15` sends TERM; that alone cannot guarantee termination.
This is an installer defect, not proof of the precise Go/emulator failure.
iSH has upstream Go-hang reports. A userspace timeout cannot recover a deadlocked
emulator. BusyBox 1.33 lacks GNU timeout's `-k`, so that is not a portable fix.

## Fix and recovery

Read-only probes use `timeout -s KILL 15`. Separate progress messages identify
network, SHA-256, extraction, version and template checks. Failed candidates are
never installed; checksums/capability checks are never skipped.

Use the already installed Bash/Starship through the explicit offline sh setup.
See [the upgrade/recovery guide](../docs/system-upgrade.md). Test Alpine changes
in another filesystem: updating userspace does not update iSH's emulated kernel.

## Prevention

A regression test verifies that a process ignoring TERM is still killed. Keep
BusyBox syntax compatibility and emulator acceptance distinct from host tests.

Sources: [BusyBox 1.33 timeout implementation](https://github.com/mirror/busybox/blob/1_33_stable/coreutils/timeout.c),
[iSH Go reports](https://github.com/ish-app/ish/issues/1230).
