// Rust std fork/exec compatibility checks. No crates, network, or credentials.
// Compile with --edition=2021. For the iSH-specific pidfd rejection contract,
// also use RUSTC_BOOTSTRAP=1 and --cfg ish_pidfd_probe (feature linux_pidfd).
// A broken spawn can block inside std: run each --case under an outer timeout,
// for example: timeout -s KILL 30 ./rust-process-compat-probe --case exec-channel-eof
// Use --list to enumerate cases. With no arguments, all compiled cases run.
#![cfg_attr(all(target_os = "linux", ish_pidfd_probe), feature(linux_pidfd))]

use std::error::Error;
use std::fs::{self, DirBuilder, File};
use std::io::{self, Read, Write};
use std::os::fd::{AsRawFd, FromRawFd, OwnedFd};
use std::os::unix::fs::DirBuilderExt;
use std::os::unix::process::{CommandExt, ExitStatusExt};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, ExitStatus, Stdio};
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

type TestResult = Result<(), Box<dyn Error>>;

// These constants agree on the intended Linux target and the macOS build host.
const EACCES: i32 = 13;
const ENOENT: i32 = 2;
const EBADF: i32 = 9;
const ECHILD: i32 = 10;
const WNOHANG: i32 = 1;
const F_DUPFD: i32 = 0;
const F_GETFD: i32 = 1;
const F_SETFD: i32 = 2;
const FD_CLOEXEC: i32 = 1;

#[cfg(target_os = "linux")]
const SIGUSR1: i32 = 10;
#[cfg(target_os = "macos")]
const SIGUSR1: i32 = 30;
#[cfg(target_os = "linux")]
const SIG_UNBLOCK: i32 = 1;
#[cfg(target_os = "macos")]
const SIG_UNBLOCK: i32 = 2;
#[cfg(target_os = "linux")]
const SIG_SETMASK: i32 = 2;
#[cfg(target_os = "macos")]
const SIG_SETMASK: i32 = 3;

// Opaque, over-aligned storage for the Linux musl/macOS sigaction and sigset_t
// structures. libc alone reads/writes their fields; their sizes are <= 256 bytes
// and alignments <= 16 on these two supported probe platforms.
#[repr(C, align(16))]
struct SignalStorage([u8; 256]);

unsafe extern "C" {
    fn getpid() -> i32;
    fn getsid(pid: i32) -> i32;
    fn setsid() -> i32;
    fn waitpid(pid: i32, status: *mut i32, options: i32) -> i32;
    fn fcntl(fd: i32, command: i32, ...) -> i32;
    fn signal(signum: i32, handler: usize) -> usize;
    fn sigaction(signum: i32, action: *const SignalStorage, old: *mut SignalStorage) -> i32;
    fn sigemptyset(set: *mut SignalStorage) -> i32;
    fn sigaddset(set: *mut SignalStorage, signum: i32) -> i32;
    fn pthread_sigmask(how: i32, set: *const SignalStorage, old: *mut SignalStorage) -> i32;
    // pthread_t is a pointer-sized integer or opaque pointer on these platforms.
    fn pthread_self() -> usize;
    fn pthread_kill(thread: usize, signum: i32) -> i32;
}

const BASE_CASES: &[&str] = &[
    "normal-spawn",
    "pre-exec-success",
    "pre-exec-error",
    "missing-executable",
    "exec-channel-eof",
    "stdio-roundtrip",
    "wait-and-reap",
    "kill-and-reap",
    "session-and-hook-order",
    "descriptor-cloexec",
    "descriptor-pre-exec",
    "repeat-resource-cleanup",
    "sleep-zero",
    "sleep-relative",
    "sleep-interrupted",
    "parallel-pre-exec",
];

fn check(condition: bool, detail: impl Into<String>) -> TestResult {
    if condition {
        Ok(())
    } else {
        Err(detail.into().into())
    }
}

fn no_children() -> TestResult {
    let mut status = 0;
    let result = unsafe { waitpid(-1, &mut status, WNOHANG) };
    let error = io::Error::last_os_error();
    check(
        result == -1 && error.raw_os_error() == Some(ECHILD),
        format!("child was not reaped: waitpid={result}, status={status}, error={error}"),
    )
}

// Keeps failure paths from leaving the probe's own successfully spawned child.
struct ManagedChild(Child);
impl Drop for ManagedChild {
    fn drop(&mut self) {
        let _ = self.0.kill();
        let _ = self.0.wait();
    }
}

struct JoinedThread<T>(Option<thread::JoinHandle<T>>);
impl<T> Drop for JoinedThread<T> {
    fn drop(&mut self) {
        if let Some(handle) = self.0.take() {
            let _ = handle.join();
        }
    }
}

static SLEEP_ACTIVE: AtomicBool = AtomicBool::new(false);
static SLEEP_SIGNALS: AtomicUsize = AtomicUsize::new(0);
static ALL_SIGNALS: AtomicUsize = AtomicUsize::new(0);

extern "C" fn sleep_signal_handler(_: i32) {
    // Pointer-sized atomics are lock-free on x86 and the macOS build host.
    ALL_SIGNALS.fetch_add(1, Ordering::Relaxed);
    if SLEEP_ACTIVE.load(Ordering::Relaxed) {
        SLEEP_SIGNALS.fetch_add(1, Ordering::Relaxed);
    }
}

struct SleepSignalState {
    action: SignalStorage,
    mask: SignalStorage,
    action_saved: bool,
    mask_saved: bool,
}
impl SleepSignalState {
    fn install() -> Result<Self, Box<dyn Error>> {
        let mut saved = Self {
            action: SignalStorage([0; 256]),
            mask: SignalStorage([0; 256]),
            action_saved: false,
            mask_saved: false,
        };
        if unsafe { sigaction(SIGUSR1, std::ptr::null(), &mut saved.action) } == -1 {
            return Err(io::Error::last_os_error().into());
        }
        saved.action_saved = true;
        // Preserve the complete previous disposition (including flags and mask)
        // for restoration, while libc installs our temporary handler.
        if unsafe { signal(SIGUSR1, sleep_signal_handler as *const () as usize) } == usize::MAX {
            return Err(io::Error::last_os_error().into());
        }
        let mut unblock = SignalStorage([0; 256]);
        if unsafe { sigemptyset(&mut unblock) } == -1
            || unsafe { sigaddset(&mut unblock, SIGUSR1) } == -1
        {
            return Err(io::Error::last_os_error().into());
        }
        let code = unsafe { pthread_sigmask(SIG_UNBLOCK, &unblock, &mut saved.mask) };
        if code != 0 {
            return Err(io::Error::from_raw_os_error(code).into());
        }
        saved.mask_saved = true;
        Ok(saved)
    }
}
impl Drop for SleepSignalState {
    fn drop(&mut self) {
        SLEEP_ACTIVE.store(false, Ordering::Relaxed);
        if self.mask_saved {
            unsafe {
                pthread_sigmask(SIG_SETMASK, &self.mask, std::ptr::null_mut());
            }
        }
        if self.action_saved {
            unsafe {
                sigaction(SIGUSR1, &self.action, std::ptr::null_mut());
            }
        }
    }
}

fn interrupted_sleep() -> TestResult {
    let _signal_state = SleepSignalState::install()?;
    ALL_SIGNALS.store(0, Ordering::Relaxed);
    SLEEP_SIGNALS.store(0, Ordering::Relaxed);
    let sleeper = unsafe { pthread_self() };
    // Declare the join guard after the signal guard: even during unwinding the
    // sender finishes before the previous signal disposition is restored.
    let mut sender = JoinedThread(Some(thread::Builder::new().spawn(move || {
        thread::sleep(Duration::from_millis(20));
        unsafe { pthread_kill(sleeper, SIGUSR1) }
    })?));
    let requested = Duration::from_millis(100);
    let start = Instant::now();
    SLEEP_ACTIVE.store(true, Ordering::Relaxed);
    thread::sleep(requested);
    SLEEP_ACTIVE.store(false, Ordering::Relaxed);
    let elapsed = start.elapsed();
    let sent = sender
        .0
        .take()
        .ok_or("missing signal sender")?
        .join()
        .map_err(|_| "signal sender panicked")?;
    check(sent == 0, format!("pthread_kill returned errno {sent}"))?;
    check(
        ALL_SIGNALS.load(Ordering::Relaxed) > 0,
        "SIGUSR1 was not delivered",
    )?;
    check(
        SLEEP_SIGNALS.load(Ordering::Relaxed) > 0,
        "SIGUSR1 did not arrive during sleep",
    )?;
    // iSH's current nanosleep may restart the entire interval after EINTR.
    // Oversleep is permitted here; this does not assert full syscall conformance.
    check(
        elapsed >= requested,
        format!("interrupted sleep returned early: {elapsed:?}"),
    )
}

fn parallel_pre_exec(executable: &Path) -> TestResult {
    let outcomes = thread::scope(|scope| {
        let workers: Vec<_> = (0..2)
            .map(|_| {
                scope.spawn(|| -> Result<(), String> {
                    for _ in 0..2 {
                        let output = command(executable, "emit", true)
                            .output()
                            .map_err(|error| error.to_string())?;
                        if !output.status.success()
                            || output.stdout != b"child-ok\n"
                            || output.stderr != b"child-stderr\n"
                        {
                            return Err(format!(
                                "parallel child result differed: {:?}",
                                output.status
                            ));
                        }
                    }
                    Ok(())
                })
            })
            .collect();
        // Join every worker before examining failures. waitpid(-1) must never
        // inspect or reap another worker's child while spawning is in progress.
        workers
            .into_iter()
            .map(|worker| worker.join())
            .collect::<Vec<_>>()
    });
    for outcome in outcomes {
        outcome.map_err(|_| "parallel spawn worker panicked")??;
    }
    no_children()
}

struct Scratch(PathBuf);
impl Scratch {
    fn new() -> Result<Self, Box<dyn Error>> {
        let stamp = SystemTime::now().duration_since(UNIX_EPOCH)?.as_nanos();
        let path = std::env::temp_dir().join(format!(
            "dotfiles-rust-process-probe-{}-{stamp}",
            std::process::id()
        ));
        DirBuilder::new().mode(0o700).create(&path)?;
        Ok(Self(path))
    }
    fn missing_executable(&self) -> PathBuf {
        self.0.join("does-not-exist")
    }
}
impl Drop for Scratch {
    fn drop(&mut self) {
        // This probe never writes files here; do not recursively remove anything.
        let _ = fs::remove_dir(&self.0);
    }
}

fn command(executable: &Path, mode: &str, pre_exec: bool) -> Command {
    let mut command = Command::new(executable);
    command.args(["--child", mode]);
    if pre_exec {
        // No allocation or locks in a post-fork callback.
        unsafe {
            command.pre_exec(|| Ok(()));
        }
    }
    command
}

fn expect_errno(mut command: Command, errno: i32) -> TestResult {
    match command.spawn() {
        Err(error) => check(
            error.raw_os_error() == Some(errno),
            format!("expected errno {errno}, received {error:?}"),
        )?,
        Ok(child) => {
            drop(ManagedChild(child));
            return Err(format!("spawn succeeded; expected errno {errno}").into());
        }
    }
    no_children()
}

fn exited(status: ExitStatus, code: i32) -> TestResult {
    check(
        status.code() == Some(code),
        format!("expected exit {code}, received {status}"),
    )
}

fn open_fd_count() -> usize {
    // A bounded scan avoids depending on iSH's /proc/self/fd implementation.
    (0..256)
        .filter(|&fd| unsafe { fcntl(fd, F_GETFD) } >= 0)
        .count()
}

fn high_cloexec_fd() -> Result<OwnedFd, Box<dyn Error>> {
    let file = File::open("/dev/null")?;
    let fd = unsafe { fcntl(file.as_raw_fd(), F_DUPFD, 128) };
    if fd == -1 {
        return Err(io::Error::last_os_error().into());
    }
    let owned = unsafe { OwnedFd::from_raw_fd(fd) };
    if unsafe { fcntl(fd, F_SETFD, FD_CLOEXEC) } == -1 {
        return Err(io::Error::last_os_error().into());
    }
    Ok(owned)
}

fn run_case(name: &str, executable: &Path) -> TestResult {
    match name {
        "normal-spawn" | "pre-exec-success" => {
            let output = command(executable, "emit", name == "pre-exec-success").output()?;
            exited(output.status, 0)?;
            check(output.stdout == b"child-ok\n", "unexpected stdout")?;
            check(output.stderr == b"child-stderr\n", "unexpected stderr")?;
        }
        "pre-exec-error" => {
            let scratch = Scratch::new()?;
            let mut command = Command::new(scratch.missing_executable());
            unsafe {
                command.pre_exec(|| Err(io::Error::from_raw_os_error(EACCES)));
            }
            // If the callback is skipped, exec returns ENOENT instead of EACCES.
            expect_errno(command, EACCES)?;
        }
        "missing-executable" => {
            let scratch = Scratch::new()?;
            let mut command = Command::new(scratch.missing_executable());
            unsafe {
                command.pre_exec(|| Ok(()));
            }
            expect_errno(command, ENOENT)?;
        }
        "exec-channel-eof" | "stdio-roundtrip" => {
            let mut command = command(executable, "echo-until-eof", true);
            command
                .stdin(Stdio::piped())
                .stdout(Stdio::piped())
                .stderr(Stdio::piped());
            // The child cannot exit until the parent closes stdin. If the error
            // channel leaks across exec, spawn blocks here; the outer timeout
            // detects it and the child's stdin reaches EOF when the parent dies.
            let mut child = ManagedChild(command.spawn()?);
            let payload: &[u8] = if name == "stdio-roundtrip" {
                b"input from parent\n"
            } else {
                b""
            };
            let mut stdin = child.0.stdin.take().ok_or("missing piped stdin")?;
            stdin.write_all(payload)?;
            drop(stdin);
            exited(child.0.wait()?, 0)?;
            let mut stdout = Vec::new();
            let mut stderr = Vec::new();
            child
                .0
                .stdout
                .take()
                .ok_or("missing stdout")?
                .read_to_end(&mut stdout)?;
            child
                .0
                .stderr
                .take()
                .ok_or("missing stderr")?
                .read_to_end(&mut stderr)?;
            check(stdout == payload, "stdin/stdout byte roundtrip changed")?;
            check(
                stderr == b"eof-observed\n",
                "child did not report stdin EOF",
            )?;
        }
        "wait-and-reap" => {
            let mut child = ManagedChild(command(executable, "exit-23", true).spawn()?);
            if let Some(status) = child.0.try_wait()? {
                exited(status, 23)?;
            }
            exited(child.0.wait()?, 23)?;
            exited(child.0.wait()?, 23)?;
        }
        "kill-and-reap" => {
            let mut command = command(executable, "ready-until-eof", true);
            command
                .stdin(Stdio::piped())
                .stdout(Stdio::piped())
                .stderr(Stdio::null());
            let mut child = ManagedChild(command.spawn()?);
            let mut ready = [0; 6];
            child
                .0
                .stdout
                .as_mut()
                .ok_or("missing stdout")?
                .read_exact(&mut ready)?;
            check(&ready == b"ready\n", "child did not reach exec")?;
            child.0.kill()?;
            let status = child.0.wait()?;
            check(
                status.signal() == Some(9),
                format!("expected SIGKILL, received {status}"),
            )?;
        }
        "session-and-hook-order" => {
            let parent_session = unsafe { getsid(0) };
            if parent_session == -1 {
                return Err(io::Error::last_os_error().into());
            }
            let mut command = command(executable, "check-session", false);
            unsafe {
                command.pre_exec(|| {
                    if setsid() == -1 {
                        Err(io::Error::last_os_error())
                    } else {
                        Ok(())
                    }
                });
                command.pre_exec(|| {
                    if getsid(0) == getpid() {
                        Ok(())
                    } else {
                        Err(io::Error::from_raw_os_error(EACCES))
                    }
                });
            }
            let output = command.output()?;
            exited(output.status, 0)?;
            check(
                output.stdout == b"session-ok\n",
                "session did not survive exec",
            )?;
            check(
                unsafe { getsid(0) } == parent_session,
                "child callback changed parent session",
            )?;
        }
        "descriptor-cloexec" | "descriptor-pre-exec" => {
            let owned = high_cloexec_fd()?;
            let fd = owned.as_raw_fd();
            let inherit = name == "descriptor-pre-exec";
            let mut command = command(
                executable,
                if inherit { "fd-open" } else { "fd-closed" },
                true,
            );
            command.arg(fd.to_string());
            if inherit {
                unsafe {
                    command.pre_exec(move || {
                        if fcntl(fd, F_SETFD, 0) == -1 {
                            Err(io::Error::last_os_error())
                        } else {
                            Ok(())
                        }
                    });
                }
            }
            let output = command.output()?;
            exited(output.status, 0)?;
            check(output.stdout == b"fd-ok\n", "unexpected descriptor result")?;
            check(
                unsafe { fcntl(fd, F_GETFD) } & FD_CLOEXEC != 0,
                "child changed parent's descriptor flags",
            )?;
        }
        "repeat-resource-cleanup" => {
            let before = open_fd_count();
            for _ in 0..4 {
                run_case("pre-exec-success", executable)?;
                run_case("pre-exec-error", executable)?;
                run_case("missing-executable", executable)?;
            }
            let after = open_fd_count();
            check(
                before == after,
                format!("open descriptors changed: {before} -> {after}"),
            )?;
        }
        "sleep-zero" => thread::sleep(Duration::ZERO),
        "sleep-relative" => {
            let requested = Duration::from_millis(20);
            let start = Instant::now();
            thread::sleep(requested);
            let elapsed = start.elapsed();
            check(
                elapsed >= requested,
                format!("relative sleep returned early: {elapsed:?}"),
            )?;
        }
        "sleep-interrupted" => interrupted_sleep()?,
        "parallel-pre-exec" => parallel_pre_exec(executable)?,
        #[cfg(all(target_os = "linux", ish_pidfd_probe))]
        "pidfd-rejected-posix" | "pidfd-rejected-pre-exec" => {
            let mut command = command(executable, "emit", name == "pidfd-rejected-pre-exec");
            std::os::linux::process::CommandExt::create_pidfd(&mut command, true);
            match command.spawn() {
                Err(error) => check(
                    error.kind() == io::ErrorKind::Unsupported,
                    format!("expected explicit Unsupported pidfd error, received {error:?}"),
                )?,
                Ok(child) => {
                    drop(ManagedChild(child));
                    return Err(
                        "explicit pidfd request was accepted by the iSH-specific std".into(),
                    );
                }
            }
        }
        _ => return Err(format!("unknown case: {name}").into()),
    }
    no_children()
}

fn child_mode(mode: &str, argument: Option<&str>) -> TestResult {
    match mode {
        "emit" => {
            io::stdout().write_all(b"child-ok\n")?;
            io::stderr().write_all(b"child-stderr\n")?;
        }
        "echo-until-eof" | "ready-until-eof" => {
            if mode == "ready-until-eof" {
                io::stdout().write_all(b"ready\n")?;
                io::stdout().flush()?;
            }
            let mut bytes = Vec::new();
            io::stdin().read_to_end(&mut bytes)?;
            io::stdout().write_all(&bytes)?;
            io::stderr().write_all(b"eof-observed\n")?;
        }
        "exit-23" => std::process::exit(23),
        "check-session" => {
            check(
                unsafe { getsid(0) == getpid() },
                "child is not its session leader",
            )?;
            io::stdout().write_all(b"session-ok\n")?;
        }
        "fd-open" | "fd-closed" => {
            let fd: i32 = argument.ok_or("missing fd argument")?.parse()?;
            let flags = unsafe { fcntl(fd, F_GETFD) };
            let error = io::Error::last_os_error();
            if mode == "fd-open" {
                check(
                    flags >= 0 && flags & FD_CLOEXEC == 0,
                    "expected inherited descriptor",
                )?;
            } else {
                check(
                    flags == -1 && error.raw_os_error() == Some(EBADF),
                    "CLOEXEC descriptor survived exec",
                )?;
            }
            io::stdout().write_all(b"fd-ok\n")?;
        }
        _ => return Err(format!("unknown child mode: {mode}").into()),
    }
    Ok(())
}

fn main() {
    let arguments: Vec<String> = std::env::args().collect();
    if arguments.get(1).map(String::as_str) == Some("--child") {
        let result = child_mode(
            arguments.get(2).map(String::as_str).unwrap_or(""),
            arguments.get(3).map(String::as_str),
        );
        if let Err(error) = result {
            eprintln!("CHILD FAIL: {error}");
            std::process::exit(1);
        }
        return;
    }
    let mut cases = BASE_CASES.to_vec();
    #[cfg(all(target_os = "linux", ish_pidfd_probe))]
    cases.extend(["pidfd-rejected-posix", "pidfd-rejected-pre-exec"]);
    if arguments.get(1).map(String::as_str) == Some("--list") {
        for case in cases {
            println!("{case}");
        }
        return;
    }
    if arguments.len() == 3 && arguments[1] == "--case" {
        if !cases.contains(&arguments[2].as_str()) {
            eprintln!("unknown case: {}", arguments[2]);
            std::process::exit(2);
        }
        cases = vec![arguments[2].as_str()];
    } else if arguments.len() != 1 {
        eprintln!("usage: rust-process-compat-probe [--list | --case NAME]");
        std::process::exit(2);
    }
    let executable = std::env::current_exe().or_else(|_| fs::canonicalize(&arguments[0]));
    let executable = match executable {
        Ok(path) => path,
        Err(error) => {
            eprintln!("cannot resolve probe executable: {error}");
            std::process::exit(2);
        }
    };
    let mut failed = 0;
    for case in &cases {
        println!("RUN {case}");
        let _ = io::stdout().flush();
        match run_case(case, &executable) {
            Ok(()) => println!("PASS {case}"),
            Err(error) => {
                println!("FAIL {case}: {error}");
                failed += 1;
            }
        }
    }
    println!("RESULT passed={} failed={failed}", cases.len() - failed);
    if failed != 0 {
        std::process::exit(1);
    }
}
