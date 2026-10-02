"""Find the Mad Max replay signature in each binary."""
from load import files

sig = b'~a6J@g$"z'
for k, d in files().items():
    i = d.find(sig)
    print(k, hex(i), d.count(sig), len(d))
    print('   ', d[i - 0x40:i + 0x20].hex())
