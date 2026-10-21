"""Copy local files into the board's RAM (/tmp, never the SD card) over the Linux serial console.

    uv run --with pyserial python put.py LOCAL REMOTE [LOCAL REMOTE ...]

base64 in heredoc chunks; each chunk's md5 is checked on the board and the chunk resent on a
mismatch (the console has no flow control), then the parts are joined and the whole md5 checked.
"""
import base64
import hashlib
import sys
import time

sys.path.insert(0, "/home/matt/projects/ZigMachine/.claude/worktrees/chisel-queue-v2/fpga/tools")
from linux_console import LinuxConsole  # noqa: E402

CHUNK = 24 * 1024  # raw bytes a heredoc
LINE = 76


def send_chunk(c: LinuxConsole, data: bytes, part: str) -> bool:
    b64 = base64.b64encode(data).decode()
    lines = [b64[i : i + LINE] for i in range(0, len(b64), LINE)]
    c.port.reset_input_buffer()
    c.port.write(f"base64 -d > {part} << 'ZMEOF'\r".encode())
    for i in range(0, len(lines), 32):
        c.port.write(("\r".join(lines[i : i + 32]) + "\r").encode())
        time.sleep(0.004)
    c.port.write(b"ZMEOF\r")
    rc, out = c.run(f"md5sum {part}", timeout=30)
    return rc == 0 and hashlib.md5(data).hexdigest() in out


def put(c: LinuxConsole, local: str, remote: str) -> None:
    data = open(local, "rb").read()
    t0 = time.monotonic()
    c.run(f"rm -f {remote}.part*", timeout=10)
    parts = []
    for n, off in enumerate(range(0, len(data), CHUNK)):
        part = f"{remote}.part{n:04d}"
        for attempt in range(6):
            if send_chunk(c, data[off : off + CHUNK], part):
                break
            print(f"  {part}: md5 mismatch, resend ({attempt + 1})", flush=True)
        else:
            raise SystemExit(f"put: {part} failed 6 times")
        parts.append(part)
    c.run(f"cat {remote}.part* > {remote} && rm -f {remote}.part*", timeout=60)
    rc, out = c.run(f"md5sum {remote}", timeout=30)
    want = hashlib.md5(data).hexdigest()
    if want not in out:
        raise SystemExit(f"put: {remote} md5 mismatch: {out}")
    dt = time.monotonic() - t0
    print(f"put {local} -> {remote}: {len(data)} B, md5 {want}, {dt:.0f} s ({len(data) / dt / 1024:.0f} KiB/s)")


def main() -> None:
    a = sys.argv[1:]
    if not a or len(a) % 2:
        raise SystemExit(__doc__)
    c = LinuxConsole()
    c.login()
    for local, remote in zip(a[::2], a[1::2]):
        put(c, local, remote)


if __name__ == "__main__":
    main()
