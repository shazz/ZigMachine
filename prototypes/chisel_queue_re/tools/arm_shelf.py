"""After boot_arm.py: build the arm's shelf in RAM (/tmp/zm = a bind mount of the card's shelf, with the
arm's own files bind-mounted over theirs; the card is never written) and run the rootfs glass on it, the way S99glass runs it on the card.

    uv run --with pyserial python arm_shelf.py [LOCAL NAME ...]   (NAME: a file name inside /tmp/zm)
"""
import sys
import time

sys.path.insert(0, "/home/matt/projects/ZigMachine/prototypes/chisel_queue_re/tools")
from put import put  # noqa: E402  (put.py adds fpga/tools to the path)
from linux_console import LinuxConsole  # noqa: E402

SETUP = (
    "touch /tmp/glass.stop /tmp/glass2.stop; killall glass; sleep 1; "
    "for m in $(grep -o ' /tmp/zm[^ ]*' /proc/mounts | sort -r); do umount $m; done; "
    "mkdir -p /tmp/zm /tmp/zf; mount --bind /mnt/sd/zigmachine /tmp/zm; ls /tmp/zm | wc -l"
)
START = (
    "rm -f /tmp/glass2.stop; (while [ ! -e /tmp/glass2.stop ]; do /usr/bin/glass run /tmp/zm "
    ">>/tmp/glass.log 2>&1; sleep 1; done) </dev/null >/dev/null 2>&1 & true"
)


def main() -> None:
    a = sys.argv[1:]
    c = LinuxConsole()
    c.login()
    print(c.run(SETUP, timeout=30)[1])
    for local, name in zip(a[::2], a[1::2]):
        put(c, local, f"/tmp/zf/{name}")
        print(c.run(f"mount --bind /tmp/zf/{name} /tmp/zm/{name} && md5sum /tmp/zm/{name}")[1])
    c.run(START)
    time.sleep(6)
    for cmd in ["ps | grep '[g]lass run'", "md5sum /tmp/zm/system.rv32", "tail -5 /tmp/glass.log", "glass ctl stats 1"]:
        print(f"$ {cmd}\n{c.run(cmd, timeout=20)[1]}")


if __name__ == "__main__":
    main()
