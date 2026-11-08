# Print the menu's state variables across consecutive frame dumps, and the changed regions.
import struct, sys
dumps = [open(p, 'rb').read() for p in sys.argv[1:]]
VARS = {
    'frame 14074': (0x14074, 'h'), 'screen 313c6': (0x313C6, 'I'), 'back 313ca': (0x313CA, 'I'),
    'pos 5b2e4': (0x5B2E4, 'i'), 'tgt 5b2e8': (0x5B2E8, 'i'), 'vel 5b2ec': (0x5B2EC, 'h'),
    'top 64c6c': (0x64C6C, 'i'), 'bot 64c70': (0x64C70, 'i'), 'mid 64c74': (0x64C74, 'i'),
    'vtop 64c80': (0x64C80, 'h'), 'vbot 64c82': (0x64C82, 'h'), 'vmid 64c84': (0x64C84, 'h'),
    'hop 64c8a': (0x64C8A, 'h'), 'drumtop 4ebb8': (0x4EBB8, 'h'), 'cfg 40ed2': (0x40ED2, 'h'),
    'cfgB 40ede': (0x40EDE, 'h'), 'phase 4eb96': (0x4EB96, 'h'), 'acc 4eb94': (0x4EB94, 'h'),
    'col 4eb8e': (0x4EB8E, 'h'), 'glint 62544': (0x62544, 'h'), 'spark 620be': (0x620BE, 'h'),
    'sparkT 620bc': (0x620BC, 'h'), 'ebd0': (0x4EBD0, 'h'), 'ebd4': (0x4EBD4, 'h'), 'ebd6': (0x4EBD6, 'h'),
    'ebca': (0x4EBCA, 'h'), 'ebc8': (0x4EBC8, 'h'),
}
for name, (a, f) in VARS.items():
    sz = struct.calcsize('>' + f)
    print('%-16s' % name, ' '.join('%10s' % struct.unpack('>' + f, d[a:a + sz])[0] for d in dumps))
a, b = dumps[0], dumps[1]
runs, s = [], None
for i in range(0x10000, 0x80000):
    if a[i] != b[i]:
        if s is None:
            s = i
        e = i
    elif s is not None and i - e > 32:
        runs.append((s, e))
        s = None
print('changed regions 0->1 (outside screens):')
for s, e in runs:
    if 0x31400 <= s < 0x41000:
        continue
    print('  %06x-%06x %d' % (s, e, e - s + 1))
