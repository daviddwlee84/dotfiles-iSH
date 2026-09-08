# `Illegal instruction` despite a matching iSH architecture

**Symptoms:** `Illegal instruction`, `illegal hardware instruction`, `Bad system call`,
`nodejs and npm versions are not supported`; package installation succeeds but
startup or a later workload fails.
**First seen:** historical upstream reports, migrated from
`daviddwlee84/dotfiles@4073f2207afb0c865b58321f46c2edfb16c7819c`.
**Affects:** the specific iSH/tool/version combinations in the linked reports.
**Status:** historical claims corrected 2026-09-08; device acceptance pending.

## Correction to the migrated investigation

The previous text generalized individual failures to every Node, Rust and Go
binary, called the situation "WONTFIX-ish", declared no workaround, and recommended
stopping at Alpine 3.18. These unsupported conclusions have been removed, along
with unverified all-build scope and snapshot-specific decoder counts.

The assertion that native iOS restrictions make child processes impossible in
iSH was also wrong: iSH implements guest
[`fork`/`clone`](https://github.com/ish-app/ish/blob/master/kernel/fork.c) and
[`execve`](https://github.com/ish-app/ish/blob/master/kernel/exec.c). Compatibility
must be established for the emulator and workload, not inferred from native iOS.

## Symptoms with source context

[Issue #1507](https://github.com/ish-app/ish/issues/1507) reports iSH 1.2.2 (178),
Cargo 1.44.0: `cargo --version` succeeds but `cargo build` reports:

```text
illegal hardware instruction
```

[Issue #2335](https://github.com/ish-app/ish/issues/2335) concerns Node startup.
A [2024 workaround](https://github.com/ish-app/ish/issues/2335#issuecomment-2264331674)
uses Node 20.8.1 with matching ICU; a
[2026 correction](https://github.com/ish-app/ish/issues/2335#issuecomment-4034378900)
adds ada-libs. Neither establishes compatibility of modern agents.

[Issue #2447](https://github.com/ish-app/ish/issues/2447) reports iSH 1.3.2 with
both i586 and i686 musl Rust/Tokio binaries:

```text
attempt to calculate the remainder with a divisor of zero
Segmentation fault
```

## Cause and investigation

Matching 32-bit x86 and musl is necessary but insufficient. An advertised CPU
feature does not prove all its instructions work. The
[`cvtdq2pd` patch](https://github.com/ish-app/ish/commit/d0309a5ff4b36efad0a0f49fad1082516c08cf6d)
and [Node fork report](https://github.com/ish-app/ish/issues/2604#issuecomment-3448630596)
provide one instruction-related example. Other failures can involve threading,
syscalls, libraries or dependency versions; similarly named errors can differ.

## Workaround and prevention

- Record exact iSH/iOS/Alpine and tool versions, binary hashes and the failing
  command. Retain relevant error/opcode output without private data.
- Separate installation, startup, emulator CLI and device workflow results.
  A version probe does not certify compilation, PTYs or an agent session.
- Test alternate releases in separate filesystems. Do not mix feeds or force past
  dependency/checksum failures. Old Alpine 3.18 is not a current upgrade policy.
- Follow the [agent experiment sequence](../docs/experiments.md). SSH supports
  direct iSH testing as well as workloads running on another host.

Related: [iOS terminals](../docs/ios-terminals.md),
[SSH setup](../docs/ssh-server.md),
[chezmoi timeout](chezmoi-probe-waits-past-timeout.md).
