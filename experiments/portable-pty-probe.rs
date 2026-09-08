// Link against Herdr's actual vendored portable-pty rlib and matching std rlibs.
// Run under an outer 30-second deadline. Every blocking stage is named before
// entry; this leaves all portable-pty signal/session/fd initialization intact.
use portable_pty::{native_pty_system, Child, CommandBuilder, PtySize};
use std::io::{Read, Write};
use std::time::Instant;

struct OwnedChild(Box<dyn Child + Send + Sync>);
impl Drop for OwnedChild {
    fn drop(&mut self) {
        let _ = self.0.kill();
        let _ = self.0.wait();
    }
}

fn stage(start: Instant, name: &str) {
    eprintln!("STAGE elapsed_ms={} {name}", start.elapsed().as_millis());
    let _ = std::io::stderr().flush();
}

fn run(wait_after_output: bool) -> Result<(), String> {
    let start = Instant::now();
    stage(start, "native_pty_system.before");
    let system = native_pty_system();
    stage(start, "native_pty_system.after");

    stage(start, "openpty.before rows=40 cols=120");
    let pair = system
        .openpty(PtySize {
            rows: 40,
            cols: 120,
            pixel_width: 0,
            pixel_height: 0,
        })
        .map_err(|error| format!("openpty: {error:#}"))?;
    stage(start, "openpty.after");

    stage(start, "reader_clone.before");
    let mut reader = pair
        .master
        .try_clone_reader()
        .map_err(|error| format!("reader_clone: {error:#}"))?;
    stage(start, "reader_clone.after");

    stage(start, "command_builder.before");
    let mut command = CommandBuilder::new("/bin/sh");
    command.env_clear();
    command.env("PATH", "/usr/bin:/bin");
    command.env("HOME", "/tmp");
    command.env("TERM", "dumb");
    command.cwd("/");
    command.args([
        "-c",
        "printf 'PTY_READY\\n'; stty size; printf 'PTY_DONE\\n'",
    ]);
    stage(start, "command_builder.after");

    stage(start, "spawn_command.before");
    let mut child = OwnedChild(
        pair.slave
            .spawn_command(command)
            .map_err(|error| format!("spawn_command: {error:#}"))?,
    );
    stage(start, "spawn_command.after");
    // The parent must close its slave copy so master EOF can follow child exit.
    drop(pair.slave);
    stage(start, "parent_slave.dropped");

    let mut output = Vec::new();
    let mut bytes = [0; 256];
    loop {
        stage(start, "read.before");
        match reader.read(&mut bytes) {
            Ok(0) => {
                stage(start, "read.eof");
                break;
            }
            Ok(count) => {
                stage(start, &format!("read.after bytes={count}"));
                eprintln!("READ {:?}", String::from_utf8_lossy(&bytes[..count]));
                output.extend_from_slice(&bytes[..count]);
                if output.len() > 4096 {
                    return Err("unexpectedly large PTY output".into());
                }
                if wait_after_output
                    && (output.ends_with(b"PTY_DONE\r\n") || output.ends_with(b"PTY_DONE\n"))
                {
                    // Diagnostic separation: the script's final marker lets us
                    // verify wait/reaping without assuming the PTY reports EOF.
                    stage(start, "read.command_completion_observed");
                    break;
                }
            }
            Err(error) if error.kind() == std::io::ErrorKind::Interrupted => {
                stage(start, "read.interrupted");
            }
            // Linux PTY masters can report EIO after the final slave closes.
            Err(error) if error.raw_os_error() == Some(5) => {
                stage(start, "read.eio_after_slave_close");
                break;
            }
            Err(error) => return Err(format!("read: {error}")),
        }
    }
    stage(start, "wait.before");
    let status = child.0.wait().map_err(|error| format!("wait: {error}"))?;
    stage(start, "wait.after");
    let text = String::from_utf8_lossy(&output).replace("\r\n", "\n");
    eprintln!("OUTPUT {text:?}");
    if !status.success() {
        return Err(format!("child exit: {status:?}"));
    }
    if text != "PTY_READY\n40 120\nPTY_DONE\n" {
        return Err("PTY output or reported terminal size differed".into());
    }
    stage(start, "PASS");
    Ok(())
}

fn main() {
    let arguments: Vec<_> = std::env::args().skip(1).collect();
    let wait_after_output = arguments == ["--wait-after-output"];
    if !arguments.is_empty() && !wait_after_output {
        eprintln!("usage: portable-pty-probe [--wait-after-output]");
        std::process::exit(2);
    }
    if let Err(error) = run(wait_after_output) {
        eprintln!("FAIL {error}");
        std::process::exit(1);
    }
}
