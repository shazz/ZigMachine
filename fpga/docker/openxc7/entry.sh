#!/opt/openxc7/bin/bash
# Entrypoint: the pinned tools' environment (PATH, PRJXRAY_DB_DIR, PYTHONPATH,
# XILINX_GEN), then the command. Runs as the caller's uid, so HOME is /tmp.
set -euo pipefail
. /opt/openxc7/etc/openxc7.env
export HOME=/tmp
# prjxray's fasm2frames runs under prjxray's own python3 (its shebang), which
# lacks fasm: give it the site-packages of the env python (same 3.12).
PYTHONPATH="$PYTHONPATH:$(/opt/openxc7/bin/python3 -c 'import site; print(site.getsitepackages()[0])')"
export PYTHONPATH
exec "$@"
