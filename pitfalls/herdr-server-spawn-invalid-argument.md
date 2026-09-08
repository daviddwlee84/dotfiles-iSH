# `herdr: failed to spawn herdr server: Invalid argument (os error 22)`

**Symptoms:** the cross-built `herdr --version` succeeds, but starting a named
session fails immediately with the title's error.
**First seen:** 2026-09-08.
**Affects:** Herdr v0.8.2 built with Rust 1.96.1 for i586 musl, tested in the
macOS ARM64 iSH CLI at `d189985e5cc6d0e70629efeb31505b51a9ce78af`.
**Status:** IPC compatibility blocks session acceptance. The user reproduced the
server-spawn error on iPad; the maintainer then ran the minimal diagnostics on
iSH 1.3.2 (494), Alpine 3.14.3, i686. The iPadOS build remains unrecorded.

## Symptom and reduction

The version probe returns `herdr 0.8.2`. A normal named-session launch returns:

```text
herdr: failed to spawn herdr server: Invalid argument (os error 22)
```

The minimal Rust diagnostic in `experiments/rust-spawn-probe.rs` distinguishes
two standard-library paths. Running `/bin/sh` without a hook succeeds. Adding
an otherwise empty `pre_exec` closure produces:

```text
pre_exec=true error=Invalid argument (os error 22)
```

The same diagnostic compiled from the checked-in source with Rust 1.96.1 was
transferred with a verified SHA-256 and run on the iPad. Ordinary spawning
returns `pre_exec=false exit=Some(0) output=child-ok`; the hook case fails as
above. The raw socket diagnostic reports plain STREAM available, flagged STREAM
unavailable with error 93, and SEQPACKET unavailable with error 22. This confirms
both capability gaps on the actual device; no patched kernel was installed.

## Root cause

Rust 1.96.1's Linux fork/exec path creates a `SOCK_SEQPACKET` socket pair before
forking. Its ordinary `posix_spawn` fast path can avoid this. Herdr uses a
`pre_exec` closure for daemon detachment, and portable-pty also needs child setup.
See the [Rust implementation](https://github.com/rust-lang/rust/blob/1.96.1/library/std/src/sys/process/unix/unix.rs)
and [Herdr detachment](https://github.com/herdrdev/herdr/blob/v0.8.2/src/platform/mod.rs).

The investigated iSH [socket type translator](https://github.com/ish-app/ish/blob/d189985e5cc6d0e70629efeb31505b51a9ce78af/fs/sock.h)
accepts stream, datagram and selected raw sockets; SEQPACKET is absent. The
socketpair syscall consequently returns EINVAL. Native macOS AF_UNIX SEQPACKET
also reports protocol-not-supported, so forwarding the type to Darwin alone
would not provide the missing semantics.

This does **not** show that iSH cannot fork/exec. It identifies a dependency of
this particular Rust standard-library execution path.

## Current workaround and next investigation

Use the direct SSH test channel while local Herdr remains unaccepted. A complete
fix needs either proper iSH SEQPACKET support or a reviewed standard-library
compatibility path, retaining message boundaries, EOF and descriptor behavior.
Do not blindly substitute stream/datagram sockets or disable child setup.

A separate `sys_socketpair` bug passed raw Linux flags to the host despite
calculating translated arguments. `experiments/patches/ish-socketpair-host-args.patch`
addresses that conversion only; **it does not implement SEQPACKET or fix this
Herdr launch failure**. Keep those results separate.

### Concrete standard-library fallback precedent

[Rust issue #129654](https://github.com/rust-lang/rust/issues/129654) reports the
same class of missing-SEQPACKET compatibility problem on ESXi. The reporter
[published a local pipe-based revert](https://github.com/rust-lang/rust/issues/129654#issuecomment-2313274834)
and reported that their process example worked again. This is an ESXi result,
not a validated iSH/Herdr fix. The revert was not merged as a general Rust fix.
The original Linux pidfd transport change was
[merged in August 2023](https://github.com/rust-lang/rust/pull/113939).

An iSH-specific standard-library build using the existing Unix pipe error
channel is a candidate for further work. It must retain the pre_exec callbacks,
exec-error reporting and close-on-exec behavior. Unsupported explicit pidfd
requests should fail clearly rather than silently lose their contract. Test
callback failure, missing executables, successful exec/EOF, descriptor handling,
and a real PTY before claiming Herdr support. No such custom std build has been
implemented or tested in this repository yet.

Simply downgrading the compiler is not a direct solution: the locked Herdr
dependency graph includes time 0.3.47 (Rust 1.88 minimum), while Rust 1.88 already
uses SEQPACKET in this path. The checked stable source still does so. Removing
only Herdr's daemon pre_exec would also leave the vendored portable-pty
pre_exec callback, which establishes the session and controlling terminal.

## Prevention

Retain version, server-spawn, PTY and full workflow as distinct acceptance gates.
Do not enable the iSH Herdr installer based on a successful cross-build or version
probe. The original 64-bit FFI assumptions were another independent build issue;
the port regenerates and retains layout assertions rather than removing them.

See [experiment state](../backlog/validate-local-agents-and-herdr-on-ish.md) and
[device workflow](../docs/experiments.md).

The raw-kernel diagnostic `experiments/socketpair-probe.rs` distinguishes the
second bug: the old CLI returns protocol-not-supported for flagged STREAM
socketpairs, while the translated-argument CLI passes CLOEXEC, NONBLOCK and
nonblocking-read checks. Both reject SEQPACKET with EINVAL. A libc-level probe
can hide the first bug because musl retries the call without flags and uses
fcntl afterwards; the diagnostic deliberately uses the i386 socketcall entry.
