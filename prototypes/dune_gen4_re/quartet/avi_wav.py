"""avi_wav.py IN.avi OUT.wav: the sound of a Hatari AVI (its '01wb' chunks, 16-bit PCM) as a WAV.

Hatari writes the audio stream's format in the second 'strf'.
"""
import struct
import sys
import wave


def main() -> None:
    d = open(sys.argv[1], 'rb').read()
    fmts = []
    i = d.find(b'strf')
    while i >= 0:
        n = struct.unpack('<I', d[i + 4:i + 8])[0]
        fmts.append(d[i + 8:i + 8 + n])
        i = d.find(b'strf', i + 8)
    tag, ch, rate, _, _, bits = struct.unpack('<HHIIHH', fmts[1][:16])
    assert tag == 1 and bits == 16, (tag, bits)
    # Hatari's chunk sizes for the PNG frames do not walk (a frame's size field is not its
    # length), so find each audio chunk by its id and take the ones whose size lands on the
    # next chunk's id.
    pcm = bytearray()
    p = d.find(b'movi')
    while True:
        p = d.find(b'01wb', p + 4)
        if p < 0:
            break
        n = struct.unpack('<I', d[p + 4:p + 8])[0]
        nxt = d[p + 8 + n + (n & 1):p + 12 + n + (n & 1)]
        if nxt in (b'00dc', b'01wb', b'idx1', b'LIST', b'JUNK', b''):
            pcm += d[p + 8:p + 8 + n]
    w = wave.open(sys.argv[2], 'wb')
    w.setnchannels(ch)
    w.setsampwidth(2)
    w.setframerate(rate)
    w.writeframes(bytes(pcm))
    w.close()
    print(sys.argv[2], ch, 'ch', rate, 'Hz', len(pcm) // (2 * ch) / rate, 's')


if __name__ == '__main__':
    main()
