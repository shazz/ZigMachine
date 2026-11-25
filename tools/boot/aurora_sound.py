"""The boot sound: the CC0 "Northern Lights soft" master -> signed 8-bit mono PCM for zg.samplePlay.

The machine's PCM is Paula's, 8-bit, and zg.samplePlay hands the whole sample to the audio side (the cheapest
path: nothing to feed per frame, the same in the browser and on the board). So: mono mix, an FFT resample to
RATE (an ideal low-pass at the new Nyquist), trimmed to the picture's length with a short closing ramp, the
peak lifted to PEAK (the master's peak is -9 dB: 8 bits must not waste its range), then TPDF dither from a
seeded generator (audio dither, unlike the image's, is what keeps a quiet pad free of quantisation
distortion) and rounding to int8. Deterministic.
"""
import wave

import numpy as np

RATE = 22050  # Hz; Paula-clean, keeps the pad's content (the master is a soft pad, nothing above ~9 kHz matters)
PEAK = 0.89  # -1 dBFS
RAMP = 0.05  # s: closing ramp, so trimming to the picture's length cannot click
SEED = 721140  # the Freesound id


class SoundError(ValueError):
    pass


def read_wav(path):
    """(mono float64 in -1..1, rate) of a 16-bit PCM WAV."""
    try:
        with wave.open(str(path), "rb") as w:
            ch, width, rate, n = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
            raw = w.readframes(n)
    except (OSError, wave.Error, EOFError) as e:
        raise SoundError(f"cannot read sound {path}: {e}") from e
    if width != 2:
        raise SoundError(f"{path}: need 16-bit PCM, got {8 * width}-bit")
    x = np.frombuffer(raw, dtype="<i2").astype(np.float64) / 32768
    return x.reshape(-1, ch).mean(axis=1), rate


def resample(x, rate_in, rate_out):
    n_out = int(round(len(x) * rate_out / rate_in))
    spec = np.fft.rfft(x)
    keep = min(len(spec), n_out // 2 + 1)
    out = np.zeros(n_out // 2 + 1, dtype=complex)
    out[:keep] = spec[:keep]
    return np.fft.irfft(out, n_out) * (n_out / len(x))


def convert(path, seconds, rate=RATE):
    """(pcm int8 array, rate): `seconds` of the sound as signed 8-bit mono."""
    x, rate_in = read_wav(path)
    y = resample(x, rate_in, rate)
    n = int(round(seconds * rate))
    if n > len(y):
        raise SoundError(f"sound is {len(y) / rate:.2f} s, the picture needs {seconds:.2f} s")
    y = y[:n].copy()
    r = int(RAMP * rate)
    y[-r:] *= np.linspace(1.0, 0.0, r)
    peak = float(np.abs(y).max())
    if peak == 0:
        raise SoundError("the sound is silent")
    y *= PEAK / peak * 127
    rng = np.random.Generator(np.random.PCG64(SEED))
    tpdf = rng.random(n) - rng.random(n)
    return np.clip(np.rint(y + tpdf), -128, 127).astype(np.int8), rate
