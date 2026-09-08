# SFTP closes while SSH commands work

**Symptoms:** `Connection closed`, SFTP exit 255 after successful authentication;
direct server startup reports `unable to make the process undumpable`.
**First seen:** 2026-09-08.
**Affects:** tested iSH 1.3.2 (494), Alpine 3.14.3 x86, native OpenSSH.
**Status:** missing kernel capability; SSH streams and legacy SCP work.

## Symptom

Both `internal-sftp` and the installed `/usr/lib/ssh/sftp-server` close before
the SFTP version exchange. The same authenticated multiplexed SSH connection
can execute ordinary shell commands. A direct startup check exposes the reason:

```sh
timeout -s KILL 15 /usr/lib/ssh/sftp-server -e -l DEBUG3 </dev/null
```

```text
unable to make the process undumpable
```

The server exits 255. Its `-Q requests` query works, because that query returns
before the startup protection is applied.

## Root cause

OpenSSH's [SFTP startup](https://github.com/openssh/openssh-portable/blob/V_8_6_P1/sftp-server.c)
calls `platform_disable_tracing(1)`. On Linux, the
[platform implementation](https://github.com/openssh/openssh-portable/blob/V_8_6_P1/platform-tracing.c)
requires `prctl(PR_SET_DUMPABLE, 0)` to succeed. This protects restricted SFTP
sessions from process-memory access. The investigated
[iSH prctl implementation](https://github.com/ish-app/ish/blob/d189985e5cc6d0e70629efeb31505b51a9ce78af/kernel/misc.c)
does not implement that operation, so the startup guard fails.

This matches the symptoms in [issue #2153](https://github.com/ish-app/ish/issues/2153)
and [issue #1408](https://github.com/ish-app/ish/issues/1408); the specific guard
failure above was observed directly on this device. This is distinct from
intermittent `Connection timed out during banner exchange` before authentication.

## Workaround

For an account already authorized for SSH shell access, use the
[legacy SCP protocol](https://man.openbsd.org/scp#O) with `-O`:

```sh
ssh -p 22000 root@DEVICE_IP 'mkdir -p /root/ish-lab'
scp -O -P 22000 ./local-file root@DEVICE_IP:/root/ish-lab/
scp -O -P 22000 root@DEVICE_IP:/root/ish-lab/local-file ./returned-file
```

Use your own filenames and preserve existing files. A private test file passed
upload/download byte comparison. SSH stdin streaming also transferred and
SHA-256-verified the setup archive and diagnostic binaries successfully.

## Prevention

Test file transfer separately from SSH login and config validation. A valid
`Subsystem sftp internal-sftp` line does not prove the emulator supports startup.
Keep OpenSSH's protection intact; proper kernel support is needed for SFTP.
Do not change auth settings or restart active servers to address this failure.
