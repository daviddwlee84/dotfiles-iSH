# iOS terminals

This companion owns iSH setup. The full Unix repository is not an iSH deployment
target. iSH supplies an emulated 32-bit x86 Alpine userspace; a Linux ARM64 asset
cannot run merely because the iPhone itself has an ARM processor.

## Local versus remote

Use iSH for Git, SSH, small edits and Files/Obsidian sync. Use SSH to a Unix host
for Herdr, SpecStory and coding agents. Those tools' supported release assets and
the emulator's behavior, rather than a blanket statement about every iOS app,
define this repository's local support boundary.

Herdr and SpecStory currently publish 64-bit Linux assets; they have no selected
iSH/i386 installer here. Node/Rust/Go workloads have historical SIGILL, deadlock
and syscall reports. These are version-dependent observations, not proof that
every binary in those languages is impossible. chezmoi publishes an i386 asset;
this repository offers it experimentally and retains sh as the reliable default.

The earlier source investigation noted that CPUID can advertise SSE2 while an
individual instruction still hits an unimplemented emulator gadget. Do not infer
runnability from CPU feature names. Preserve the opcode/error plus exact versions
when investigating. The two migrated historical reports are linked from the
[repository pitfalls index](https://github.com/daviddwlee84/dotfiles-iSH/tree/main/pitfalls).

## Terminal behavior

The minimal tmux seed uses the standard Ctrl+b prefix followed by 1..9. It does
not request extended-key support or mouse capture. Historical iSH/hterm reports
showed Ctrl+2/6 arriving as legacy control bytes and touch events not reaching
tmux; `TERM=xterm-256color` alone does not prove keyboard capabilities.
Clipboard uses tmux's OSC 52 support; verify it on your actual iSH build.

iOS can suspend iSH when it leaves the foreground. Keep persistent sessions on
the remote host; local keepalives detect a lost connection but cannot prevent
suspension. Mounts must be recreated after app restart. For fonts, test a Nerd
Font Mono variant with your actual terminal rather than assuming glyph width.

For mobile terminal alternatives, Blink is a candidate for SSH/mosh, while
Working Copy is a candidate for a dedicated Git/Files workflow. Their keyboard,
subscription and integration capabilities change; compare the current app before
switching. mosh from inside iSH has historical socket/suspension failures; it is
not installed or claimed supported here. Claude Remote Control is another remote
agent option; custom API base URLs/proxy settings can affect its availability.

## Alpine and migration

The supplied 2026-09-07 device transcript confirmed the old bootstrap completed
on the iSH v3.14 snapshot. It did not test this new bootstrap or chezmoi. The new
branch diagnostic recognizes that snapshot URL. No branch migration occurs.
The old suggestion to move to v3.18 is historical, not a current security or
compatibility recommendation; old Alpine branches can be end-of-life. Back up
the iSH filesystem and test branch changes separately on a disposable filesystem.

The old Unix bootstrap URL and playbook have been removed. Use this repository's
[setup](setup.md); keep existing inline helpers until you intentionally migrate
them as described in [tools](tools.md). The original research is preserved at
[Unix source commit 4073f220](https://github.com/daviddwlee84/dotfiles/blob/4073f2207afb0c865b58321f46c2edfb16c7819c/docs/playbooks/ios-terminals.md).

Sources: [iSH](https://github.com/ish-app/ish), [historical Go report](https://github.com/ish-app/ish/issues/1230),
[historical Node report](https://github.com/ish-app/ish/issues/1564),
[chezmoi releases](https://github.com/twpayne/chezmoi/releases).
