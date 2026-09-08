// Diagnostic: compare the standard-library fast path with a pre_exec hook.
use std::os::unix::process::CommandExt;
use std::process::Command;

fn main() {
    for fallback in [false, true] {
        let mut command = Command::new("/bin/sh");
        command.args(["-c", "printf child-ok"]);
        if fallback {
            // This deliberately does no work; it selects the fork/exec path.
            unsafe { command.pre_exec(|| Ok(())); }
        }
        match command.output() {
            Ok(output) => println!(
                "pre_exec={fallback} exit={:?} output={}",
                output.status.code(), String::from_utf8_lossy(&output.stdout)
            ),
            Err(error) => println!("pre_exec={fallback} error={error}"),
        }
    }
}
