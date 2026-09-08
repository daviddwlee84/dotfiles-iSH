# SSH server and direct device testing

iSH can run an SSH server. This repository defaults to preparing OpenSSH and
OpenRC on iSH, using a separate `dotfiles-sshd` service on **port 22000**.
OpenWrt's SSH service is never changed by this option.

## First setup

Work in an imported copy of your iSH filesystem first; keep the original as a
recovery point. Run the current source's bootstrap on the device:

```sh
sh bootstrap.sh --prepare-sshd
passwd
```

`--prepare-sshd` only prepares SSH and does not need a working chezmoi. Normal
bootstrap also prepares SSH before probing chezmoi. `passwd` is a separate,
interactive operation: enter the password on your device, never in a script,
chat, shell argument or dotfiles config. An empty or locked root password is
reported as pending login setup; the installer never changes it.

If OpenRC was just installed, completely close and reopen iSH. The installer
registers the service in the **explicit `default` runlevel**, and waits for that
runlevel before starting it. It does not call `openrc default`, alter the app's
boot/login commands, or enable other services. A custom boot command needs manual
review if it does not start OpenRC.

In iSH, check:

```sh
rc-status
rc-service dotfiles-sshd status
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
```

Keep iSH in the foreground for the first tests. On the Mac, use the iPhone/iPad's
Wi-Fi IPv4 address from iOS Settings; allow iSH Local Network access if requested:

```sh
ssh -p 22000 root@DEVICE_IP
ssh-copy-id -p 22000 root@DEVICE_IP
ssh -p 22000 root@DEVICE_IP
sftp -P 22000 root@DEVICE_IP
```

Compare the first connection's host-key fingerprint with the one printed on the
device. `ssh-copy-id` copies your **public key** after password authentication;
the private key stays on the Mac. A copied filesystem may initially share its
original's host keys, so use a separate known-hosts entry when testing different
filesystem identities. Do not automatically replace a changed known-hosts entry.

## Options and ownership

Interactive `chezmoi init --apply` asks **Enable iSH SSH server**, initially yes.
For noninteractive initialization, use `chezmoi init --promptDefaults --apply`
or `--promptBool 'Enable iSH SSH server=false'`. Re-running init can explicitly
change the choice. Normal apply/update reads the saved preference without asking.

```sh
sh bootstrap.sh --sshd off
sh bootstrap.sh --sshd on
sh bootstrap.sh --prepare-sshd --sshd off
sh bootstrap.sh --prepare-sshd --dry-run
```

The nonsecret choice is stored in `~/.local/state/dotfiles-lite/sshd` and shared
by both managers. An explicit `--sshd` choice or `DOTFILES_SSHD` overrides it;
initial chezmoi data is used only when no state exists. The SSH-only entrypoint
saves this choice even when a later chezmoi probe fails. `--config-only` saves
preferences and applies home files, but performs no SSH system operations.

The setup owns these separate, create-once seeds:

- `/etc/ssh/dotfiles-lite/sshd_config`
- `/etc/init.d/dotfiles-sshd`

It preserves `/etc/ssh/sshd_config`, existing host keys, authorized keys and all
existing servers. It generates only the missing Ed25519 key used by its own
config; unused RSA/DSA generation is avoided on the emulator. New config permits
root public-key and password login, refuses
empty passwords, and declares `internal-sftp` (unsupported on the tested device;
see file transfer below). It binds IPv4 port 22000; it does not
configure routing or firewall forwarding. Seed edits are retained; review the
config yourself before applying manual port/authentication changes.

Each preparation validates config before activation. An already-running service
is not restarted. `--sshd off` removes only this service's autostart registration;
it does not stop the current server or sessions, uninstall packages, or erase
configs/keys. To stop it intentionally, use `rc-service dotfiles-sshd stop`.

## Troubleshooting and verification

To find the address for a Mac connection, open **iPad Settings → Wi-Fi**, then
tap the **Info** button beside the connected network; see the
[Apple network settings guide](https://support.apple.com/guide/ipad/connect-to-the-internet-ipad2db29c3a/ipados).
Read **IP Address** in the IPv4 section, then use `ssh -p 22000 root@DEVICE_IP`
from the Mac on the same network. The router address is a separate field.

The user's iSH build reports these errors from `ifconfig`:

```text
ifconfig: /proc/net/dev: No such file or directory
ifconfig: ioctl 0x8912 failed: Not a tty
```

These interface-query failures do not prevent SSH sockets from working; use
iPadOS network settings for the device address. A successful connection to
`localhost:22000` checks the server locally; Mac-to-iPad access needs its Wi-Fi IP.

If a later connection stalls at `Connection timed out during banner exchange`,
keep iSH in the foreground with the iPad screen unlocked and retry. This occurs
before SSH authentication or SFTP negotiation; do not label it an SFTP failure
or change authentication settings based on that message alone. The first direct
Mac test authenticated successfully with a public key, but subsequent connections
stalled at this stage. The user reopened iSH and commands worked again, but the
exact cause of those intermittent stalls remains unconfirmed. iSH's **Keep
Screen Turned On** setting prevents foreground dimming; it does not keep a
background app running.

### File transfer on the tested iSH build

SSH commands and PTY input/output work, but both SFTP server modes close after
authentication. Direct startup reports `unable to make the process undumpable`:
iSH lacks the `PR_SET_DUMPABLE` operation required by OpenSSH's startup guard.
See [the recorded diagnosis](https://github.com/daviddwlee84/dotfiles-iSH/blob/main/pitfalls/sftp-connection-closed.md)
and [upstream report](https://github.com/ish-app/ish/issues/2153).

Use [SCP's `-O` option](https://man.openbsd.org/scp#O) for an SSH-enabled account:

```sh
ssh -p 22000 root@DEVICE_IP 'mkdir -p /root/ish-lab'
scp -O -P 22000 ./local-file root@DEVICE_IP:/root/ish-lab/
scp -O -P 22000 root@DEVICE_IP:/root/ish-lab/local-file ./returned-file
```

Legacy SCP upload/download passed byte comparison. SSH stdin streaming also
transferred the setup archive and binaries with SHA-256 verification. SFTP is
recorded as unsupported on this build; the server protection remains intact.

### Setup failures

If an early transfer bundle stops at `SSH prerequisite missing: /sbin/rc-status`,
it has the wrong path for Alpine's OpenRC package. The executable is
`/bin/rc-status`; this failure occurs before creating the service or registering
autostart, so restarting iSH alone does not complete setup. Update the bundle or
repair its extracted copy and rerun:

```sh
cd ~/ish-ssh-setup
sed -i 's|/sbin/rc-status|/bin/rc-status|g' scripts/sshd.sh
sh setup-sshd.sh
```

A password already set with `passwd` remains valid. After successful preparation,
follow the reopen instruction if printed, then check `rc-service dotfiles-sshd status`.

For a start failure, inspect `/var/log/dotfiles-sshd.log`. A port conflict never
causes another server to be stopped. Invalid seed config or a conflicting service
name stops SSH setup with a diagnostic. Normal bootstrap can still preserve the
home baseline and report the SSH failure separately.

Check account state, home ownership and `.ssh` permissions if public-key login
fails. Do not apply blanket ownership changes or an automatic password-hash
workaround. The [official SSH guide](https://github.com/ish-app/ish/wiki/Running-an-SSH-server)
documents those symptoms; this installer leaves account changes to the user.

Autostart means starting when iSH boots, not continuous execution while iOS
suspends the app. The [background guide](https://github.com/ish-app/ish/wiki/Running-in-background)
describes location-based keepalive; it is not enabled here. The
[OpenRC guide](https://github.com/ish-app/ish/wiki/How-To-Enable-OpenRC-%26-Start-Services-When-iSH-App-Starts)
explains first-boot runlevels and limitations of hardware-related services.

After establishing key authentication and known-hosts trust, run the maintainer
probe from the Mac:

```sh
sh scripts/ish-probe.sh --host DEVICE_IP
sh scripts/ish-probe.sh --host DEVICE_IP --case node --output /tmp/ish-node-report.txt
```

The probe uses one explicit host, verified host keys, key authentication,
connection deadlines and bounded runtime checks. It rejects a target without
`/proc/ish`. Reports are private local artifacts; review them before sharing.
It neither installs tools nor authenticates an agent. See [experiments](experiments.md).

Device acceptance requires three complete iSH restarts followed by successful
SSH reconnections, plus public-key/password login, PTY input and SFTP. Host
fixtures do not establish this acceptance.
