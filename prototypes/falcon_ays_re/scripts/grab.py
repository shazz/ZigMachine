# Grab exact frames from the lossless Hatari capture (video/ays_rgb50.avi, PNG codec, 640x480 =
# the Falcon screen doubled) at SONG times (song 0 = video 28.0 s), halved back to 320x240.
# usage: grab.py <avi> <outdir> <prefix> t1 [t2 ...]     (times in seconds, floats)
import os
import subprocess
import sys

from PIL import Image

OFF = 28.0
avi, outdir, prefix = sys.argv[1], sys.argv[2], sys.argv[3]
os.makedirs(outdir, exist_ok=True)
for t in sys.argv[4:]:
    out = os.path.join(outdir, '%s_s%07.2f.png' % (prefix, float(t)))
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-ss', '%.3f' % (OFF + float(t) - 1.0), '-i', avi,
                    '-ss', '1.0', '-frames:v', '1', out], check=True)
    Image.open(out).convert('RGB').resize((320, 240), Image.NEAREST).save(out)
    print(out)
