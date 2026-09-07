# iSH upgrades and stalled chezmoi checks

## The reported stall

The 2026-09-07 device report uses App Store iSH 1.3.2 and the pinned
`v3.14-2023-05-19` package snapshot. Bash 5.1.16 and Starship 0.54.0 installed;
the chezmoi 2.72.1 i386 probe waited over five minutes until Ctrl+C. Chezmoi was
not installed, and home configuration had not reached the apply stage.

The old `timeout 15` sends TERM, which does not guarantee the program exits.
The installer now uses `timeout -s KILL 15` for each read-only version/template
probe, compatible with stock BusyBox 1.33 (which lacks GNU timeout's `-k`).
Download, SHA-256 verification, extraction, version check and source-layout check
have separate progress messages. Each execution check has its own 15-second
signal deadline; download can take up to 180 seconds, while hashing/extraction
are separate stages. An emulator-wide deadlock can also stop the timeout process;
a userspace watchdog cannot guarantee recovery of the entire iSH app.

This fixes our timeout behavior, not a demonstrated Go runtime bug. Upstream
[iSH Go reports](https://github.com/ish-app/ish/issues/1230) describe hangs and
version/build-dependent workarounds. Matching i386 architecture does not establish
compatibility. Changing Alpine does not update iSH's syscall/CPU emulation.

## Use the already-installed shell tools

The current source snapshot can configure the home offline, without retrying
chezmoi or installing more packages:

```sh
sh ~/.local/share/dotfiles-iSH/bootstrap.sh --manager sh --config-only --with starship
. ~/.profile
bash
```

This is an explicit temporary sh selection; the repository still defaults to
chezmoi. Once a compatible chezmoi is available, default bootstrap migrates the
source to Git for ordinary `chezmoi update`.

For another controlled attempt, download the current bootstrap and rerun it.
Do not keep waiting five minutes at a version/template check. A reported upstream
experiment is `GOMAXPROCS=1 sh bootstrap.sh --with starship`; it is not a guaranteed
fix, and some reports also require a differently linked binary. No such runtime
workaround is applied globally by this repository. If it helps, ordinary
chezmoi apply/update still need separate acceptance with the same environment.

## What can be upgraded?

| Layer | Update mechanism | What changes |
|---|---|---|
| iSH app | App Store / available official TestFlight build | Emulated CPU/syscalls and iOS integration |
| Alpine userspace | Native apk within a branch, or a release/filesystem migration | musl, BusyBox, Git and other packages |
| Personal dotfiles | chezmoi update after installation | Source/configuration and missing selected packages |

The [Alpine release table](https://alpinelinux.org/releases/) lists 3.14 support
ending on 2023-05-01. As checked on 2026-09-07, current stable is 3.24.1.
Current Alpine support does not mean that branch is accepted on iSH 1.3.2.
The [iSH compatibility notes](https://github.com/ish-app/ish/wiki/iSH-Alpine-Release-Issues)
list older 3.19/3.20 problems with sudo, procps, coreutils and Vim. Their old 3.18
recommendation is not a current security recommendation; that branch is also EOL.

`apk update` refreshes the index. `apk upgrade` upgrades packages available from
configured feeds. Your iSH feed is a dated snapshot, so these commands alone do
not move 3.14 to a newer release. The iSH project's
[repository explanation](https://ish.app/blog/default-repository-update) describes
why this package set is pinned.

## Recommended: a separate filesystem first

1. In iSH's gear menu, open **Filesystems**, select the current filesystem and
   export it to Files as a backup. Keep the original filesystem entry too.
2. From [Alpine downloads](https://alpinelinux.org/downloads/), choose **Mini Root
   Filesystem → x86**. A current stable release is an experiment here, not a
   promised compatible replacement for your working environment.
3. Use **Filesystems → Import**, select the archive, give it a distinct name,
   then choose **Boot From This Filesystem** and reopen iSH.
4. Check `cat /etc/alpine-release`, `uname -m`, package downloads, Git, Bash and
   Starship before migrating personal files. Try native `apk add chezmoi` in
   this test filesystem, then run `timeout -s KILL 15 chezmoi --version` and
   test the actual init/diff/apply/update workflow. A version probe is insufficient.
5. If boot or essential tools fail, select the original filesystem and boot it
   again. Do not remove that working environment until the replacement is accepted.

This follows iSH's
[alternate-filesystem guide](https://github.com/ish-app/ish/wiki/Install-%26-Activate-Alternate-Filesystems).
That guide also notes that some images cannot boot due to init/login compatibility.
No filesystem or package-feed migration is performed by dotfiles bootstrap.

## In-place release upgrades

The [iSH upgrade guide](https://github.com/ish-app/ish/wiki/Upgrading-to-a-new-release)
also describes an in-place path: back up, stop services when appropriate, select
matching official Alpine main/community feeds, upgrade/fix packages and reopen
the environment. Follow it first in an imported copy of your current filesystem.
There is no simple package downgrade that restores the old environment.

The companion [repository guide](https://github.com/ish-app/ish/wiki/Using-Alpine-Linux-repositories)
explains iSH's automatic feed-file replacement and `/ish` metadata. Understand that
mechanism before changing feeds; this dotfiles repo does not delete `/ish`, mix
release branches or choose a new system release on your behalf.
