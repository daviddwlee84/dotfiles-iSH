# Chezmoi probe waits past its timeout

**First seen:** 2026-09-07  
**Affects:** iSH 1.3.2 / Alpine 3.14 snapshot, chezmoi 2.72.1 i386  
**Status:** installer kill deadline fixed; locked binary still fails device acceptance

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

## Direct device recheck (2026-09-08)

`-ash: chezmoi: not found` was confirmed with `manager=sh` and no executable in
PATH or the standard install locations. The sh manager and SSH/Finder preparation
do not install chezmoi. Sourcing `.profile` cannot supply a missing binary.

The locked v2.72.1 i386 archive and extracted binary passed SHA-256 verification
in a scratch directory. `--version` exited 0. The source-layout template printed
`supported`, but its exit was never observed: the 15-second SIGKILL wrapper did
not finish, and the Mac stopped waiting after 120 seconds. A subsequent SSH
connection was refused; the exact device/app failure mechanism is unconfirmed.
The user reported an App crash and reopened it. SSH then recovered with manager=sh
and the SSH/Finder selections intact. The candidate was not installed.

An independent CLI check also failed. Seven version/template cases terminated
the emulator with SIGSEGV; one template case timed out after Go runtime errors:

```text
fatal error: markWorkerStop: unknown mark worker mode
fatal: morestack on gsignal
fatal error: unexpected signal during runtime execution
```

`GOMAXPROCS=1`, `GODEBUG=asyncpreemptoff=1`, and their combination did not produce
a passing CLI process. These settings were not persisted on the device. Full
results are in `experiments/chezmoi/results.json`. Keep the working sh deployment;
do not treat printed output as a successful probe or bypass the exit-status gate.
