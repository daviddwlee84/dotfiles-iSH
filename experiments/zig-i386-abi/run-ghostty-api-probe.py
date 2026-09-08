#!/usr/bin/env python3
"""Run an already-built, hash-checked Ghostty ABI probe in isolated processes.

Maintainer-only Python; this is never installed by target bootstrap. The Linux
run uses the existing Docker binfmt configuration and is not native i386 proof.
The iSH run imports a fresh, hash-checked Alpine rootfs with only this probe.
"""
import argparse
import hashlib
import io
import json
from pathlib import Path
import subprocess
import tarfile
import uuid


SUITES = ("terminal-small", "terminal-large", "grid", "viewport", "formatter", "mouse")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify(path, expected):
    actual = digest(path)
    if actual != expected:
        raise SystemExit(f"SHA256 mismatch: {path.name}: {actual}")
    return actual


def execute(command, timeout, log):
    try:
        proc = subprocess.run(command, capture_output=True, timeout=timeout, check=False)
        data = proc.stdout + proc.stderr
        status = {"exit": proc.returncode, "timeout": False}
    except subprocess.TimeoutExpired as exc:
        data = (exc.stdout or b"") + (exc.stderr or b"")
        status = {"exit": None, "timeout": True}
    log.write_bytes(data)
    lines = data.decode("utf-8", errors="replace").splitlines()
    status["passed"] = sum(line.startswith("ok ") for line in lines)
    status["failed"] = sum(line.startswith("not ok ") for line in lines)
    status["complete"] = any(line.startswith("# passed ") for line in lines)
    print(log.name, json.dumps(status), flush=True)
    return status


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, required=True)
    parser.add_argument("--sha256", required=True)
    parser.add_argument("--ish", type=Path, required=True)
    parser.add_argument("--fakefsify", type=Path, required=True)
    parser.add_argument("--rootfs", type=Path, required=True)
    parser.add_argument("--rootfs-sha256", required=True)
    parser.add_argument("--docker-image", required=True,
                        help="Existing pinned local image ID or digest; never pulled")
    parser.add_argument("--output", type=Path, required=True,
                        help="New, private run directory; must not already exist")
    parser.add_argument("--timeout", type=int, default=45)
    args = parser.parse_args()
    if args.timeout < 1 or args.timeout > 120:
        parser.error("timeout must be in 1..120 seconds")
    binary = args.binary.resolve(strict=True)
    verify(binary, args.sha256)
    verify(args.rootfs, args.rootfs_sha256)
    args.output.mkdir(parents=True, exist_ok=False)
    run = args.output.resolve()
    archive, guest = run / "guest.tar", run / "guest"
    with tarfile.open(args.rootfs, "r:gz") as src, tarfile.open(archive, "w") as dst:
        for member in src:
            dst.addfile(member, src.extractfile(member) if member.isfile() else None)
        data = binary.read_bytes()
        entry = tarfile.TarInfo("ghostty-api-probe")
        entry.size, entry.mode, entry.uid, entry.gid = len(data), 0o755, 0, 0
        dst.addfile(entry, io.BytesIO(data))
    subprocess.run([str(args.fakefsify.resolve()), str(archive), str(guest)],
                   check=True, timeout=60, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    report = {
        "binary_sha256": args.sha256,
        "probe_source_sha256": digest(Path(__file__).with_name("ghostty-api-probe.c")),
        "rootfs_sha256": args.rootfs_sha256,
        "ish_binary_sha256": digest(args.ish),
        "linux_execution": "Existing Docker i386 binfmt, not native i386 hardware",
        "docker_image": args.docker_image,
        "scope": "Six finite public C API suites; no iPad app or Herdr execution",
        "results": {"linux_docker": {}, "ish_cli": {}},
    }
    failed = False
    for suite in SUITES:
        container = "ghostty-abi-" + uuid.uuid4().hex
        docker = ["docker", "run", "--rm", "--pull=never", "--network=none",
                  "--platform=linux/arm64", "--name", container,
                  "--mount", f"type=bind,source={binary},target=/probe,readonly",
                  args.docker_image, "timeout", "-s", "KILL", str(args.timeout),
                  "/probe", suite]
        status = execute(docker, args.timeout + 10, run / f"linux-{suite}.log")
        if status["timeout"]:
            subprocess.run(["docker", "rm", "-f", container], check=False,
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
        report["results"]["linux_docker"][suite] = status
        status = execute([str(args.ish.resolve()), "-f", str(guest),
                          "/ghostty-api-probe", suite], args.timeout,
                         run / f"ish-{suite}.log")
        report["results"]["ish_cli"][suite] = status
    for environment in report["results"].values():
        for status in environment.values():
            failed |= (status["exit"] != 0 or status["timeout"] or
                       status["failed"] != 0 or not status["complete"])
    (run / "results.json").write_text(json.dumps(report, indent=2) + "\n")
    return int(failed)


if __name__ == "__main__":
    raise SystemExit(main())
