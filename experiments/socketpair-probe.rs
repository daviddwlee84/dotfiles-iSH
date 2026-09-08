// Checks descriptor flags and reports SEQPACKET capability without opening a server.
fn main() {
    let cases = [
        ("stream", libc::SOCK_STREAM),
        ("stream-cloexec", libc::SOCK_STREAM | libc::SOCK_CLOEXEC),
        ("stream-flags", libc::SOCK_STREAM | libc::SOCK_CLOEXEC | libc::SOCK_NONBLOCK),
        ("seqpacket", libc::SOCK_SEQPACKET | libc::SOCK_CLOEXEC),
    ];
    let mut failed = false;
    for (name, kind) in cases {
        let mut pair = [-1; 2];
        // Use the i386 kernel entry directly: musl's fallback can mask a broken
        // flagged socketpair by retrying without flags and applying fcntl.
        let arguments = [libc::AF_UNIX as usize, kind as usize, 0, pair.as_mut_ptr() as usize];
        if unsafe { libc::syscall(libc::SYS_socketcall, 8, arguments.as_ptr()) } != 0 {
            println!("{name}: unavailable {}", std::io::Error::last_os_error());
            if name != "seqpacket" { failed = true; }
            continue;
        }
        let mut flags_ok = true;
        for fd in pair {
            if kind & libc::SOCK_CLOEXEC != 0
                && unsafe { libc::fcntl(fd, libc::F_GETFD) } & libc::FD_CLOEXEC == 0 {
                flags_ok = false;
            }
            if kind & libc::SOCK_NONBLOCK != 0
                && unsafe { libc::fcntl(fd, libc::F_GETFL) } & libc::O_NONBLOCK == 0 {
                flags_ok = false;
            }
        }
        if kind & libc::SOCK_NONBLOCK != 0 {
            let mut byte = 0u8;
            let result = unsafe { libc::read(pair[0], (&mut byte as *mut u8).cast(), 1) };
            let error = std::io::Error::last_os_error();
            if result != -1 || error.kind() != std::io::ErrorKind::WouldBlock {
                flags_ok = false;
            }
        }
        println!("{name}: available flags={}", if flags_ok { "passed" } else { "FAILED" });
        failed |= !flags_ok;
        for fd in pair { unsafe { libc::close(fd); } }
    }
    if failed { std::process::exit(1); }
}
