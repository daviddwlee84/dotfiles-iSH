# Finder file sharing

Files dragged into **Finder → iPad/iPhone → Files → iSH** live in the iSH app's
iOS Documents directory. Setup mounts it at `/mnt/finder` by default. This is a
live view: edits and deletions there affect the same files shown in Finder.

## Setup and selection

Bootstrap prepares the mount before the chezmoi runtime probe. Interactive
`chezmoi init --apply` asks **Mount iSH Finder files**, initially yes.
Unattended init uses `--promptDefaults`, or
`--promptBool 'Mount iSH Finder files=false'` to decline this option.

From the current source checkout, without requiring chezmoi:

```sh
sh bootstrap.sh --prepare-finder
ls -lh /mnt/finder
sh bootstrap.sh --prepare-finder --finder off
sh bootstrap.sh --prepare-finder --finder on
```

`--finder on|off` also works with normal bootstrap. The choice is saved in
`~/.local/state/dotfiles-lite/finder`; explicit CLI or `DOTFILES_FINDER` takes
precedence, and apply/update retains saved choices. SSH and Finder are independent;
`--prepare-sshd` remains SSH-only. `--dry-run` writes nothing. `--config-only`
saves the choice but does not mount, install OpenRC or register services.
The option is iSH-only.

## Startup and existing data

Setup installs missing OpenRC, seeds `/usr/local/libexec/dotfiles-finder` and
`/etc/init.d/dotfiles-finder`, mounts immediately and registers the service in
the default runlevel. Each iSH startup rereads `/proc/ish/documents`; no iOS
container path is hardcoded. Boot does not need a checkout, chezmoi or login shell.

The helper inspects `/proc/mounts`. A correct existing manual mount is retained.
Foreign or nested mounts, symlinks and nonempty unmounted directories are preserved
and reported as conflicts. Other Files-provider mounts remain unchanged.
The helper and service are create-once seeds; personal edits are retained.

`--finder off` removes only future autostart registration. Current mounts, files
and work remain intact. Stopping the service also does not unmount. To unmount
intentionally, leave the directory, finish work using it, then run
`umount /mnt/finder` yourself.

## Manual access and verification

On an empty mountpoint, the manual equivalent is:

```sh
mkdir -p /mnt/finder
mount -t real "$(cat /proc/ish/documents)" /mnt/finder
ls -lh /mnt/finder
```

Copy experimental binaries or extract archives into the Linux home directory:

```sh
mkdir -p ~/ish-lab
tar -xzf /mnt/finder/ish-ssh-setup.tar.gz -C ~/ish-lab
```

After fully reopening iSH, check the installed helper and service:

```sh
/usr/local/libexec/dotfiles-finder status
rc-service dotfiles-finder status
ls -lh /mnt/finder
```

Manual mounting is user-confirmed on iPad. The maintainer subsequently installed
the helper/service over SSH, verified the archive SHA-256, mounted the directory
and successfully ran the OpenRC start entrypoint. The transferred hako and Herdr
hashes match their build artifacts. The user then fully reopened iSH without a
manual mount. Remote checks confirmed the mount and both services, an updated
Finder OpenRC start marker, and unchanged binary hashes. One complete Finder
app-restart check has passed; further repetitions in the three-restart plan are
not yet recorded. Autostart does not prevent iOS background suspension.

Sources: iSH's [theme UI instructions](https://github.com/ish-app/ish/blob/d189985e5cc6d0e70629efeb31505b51a9ce78af/app/ThemesViewController.m#L139)
and [OpenRC guide](https://github.com/ish-app/ish/wiki/How-To-Enable-OpenRC-%26-Start-Services-When-iSH-App-Starts).
The separate Files picker uses `mount -t ios . DIRECTORY`; those mounts have
their own [bookmark restoration](https://github.com/ish-app/ish/blob/d189985e5cc6d0e70629efeb31505b51a9ce78af/app/iOSFS.m).
