"""Put local files into board RAM and bind-mount each over its namesake in the running shelf
(/tmp/zm, itself a bind of the card's shelf). RAM only: the SD card is not written.
    uv run --with pyserial python bind_put.py LOCAL NAME [LOCAL NAME ...]"""
import sys
sys.path.insert(0, "/home/matt/projects/ZigMachine/prototypes/chisel_queue_re/tools")
from put import put  # noqa: E402
from linux_console import LinuxConsole  # noqa: E402
a = sys.argv[1:]
c = LinuxConsole()
c.login()
c.run("mkdir -p /tmp/zf")
for local, name in zip(a[::2], a[1::2]):
    print(c.run(f"md5sum /tmp/zm/{name}")[1], "(before)")
    put(c, local, f"/tmp/zf/{name}")
    print(c.run(f"mount --bind /tmp/zf/{name} /tmp/zm/{name} && md5sum /tmp/zm/{name}")[1], "(now)")
