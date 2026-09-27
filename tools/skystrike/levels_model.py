"""SKYSTRIKE's level data as the game reads it, and the rules a level must keep.

MISSIONS.DAT is 301-byte records, read at listing lines 1663-1665:
    field #1,289 as md$,12 as db$ : get #1,lvl+1
    md$  8 briefing lines x 36 characters (+1 byte, always a space)
    db$  tgtx (word), strtx (word), mission, misf, mfin, bonus (word), msb, meb
         (+1 byte, always a space); every word big-endian.
SCRNDATA.DAT is 51 bytes, one screen type per screen of the world strip,
BLOADed into bank 6 at line 2500 (sc9 = start(6) + 32033).

Everything here raises LevelError with a location; nothing is clamped.
"""
from dataclasses import dataclass

REC = 301
MD_LEN = 289
LINES = 8
LINE_W = 36
WORLD_LEN = 51
PAD = 0x20
MAX_RECORDS = 64  # apps/zig/scenes/skystrike/levels.zig MAX_RECORDS

# Screen types the program draws (1004: ON type+1 GOSUB with 18 targets for
# 0-17; 1005: 20-35 through bank 8's scene table). 18, 19 and 36+ draw nothing
# and set no ground zone, so the plane could never land or crash there.
# Names from the tiles the game draws (render_tileset.mjs); the line draws it.
SCREEN_TYPES: dict[int, str] = {
    0: 'grass; on screens 2-50 a random scene at each new game (2530)',
    1: 'airfield (1060)', 2: 'battleship, west half (1090)', 3: 'battleship, east half (1100)',
    4: 'grass, never randomised (1050)', 5: 'grass, never randomised (1050)',
    6: 'grass, never randomised (1050)', 7: 'grass, never randomised (1050)',
    8: 'bridge over a river (1300)', 9: 'sea (1150)', 10: 'sea, beach to the west (1160)',
    11: 'sea, beach to the east (1170)', 12: 'aircraft carrier, west half (1180)',
    13: 'aircraft carrier, east half (1190)', 14: 'cliff, sea to the east (1200)',
    15: 'cliff, sea to the west (1210)', 16: 'hill, rising (1220)', 17: 'hill, falling (1230)',
    20: 'houses', 21: 'inn', 22: 'gun and bunker', 23: 'manor', 24: 'factory', 25: 'orchard',
    26: 'gun post', 27: 'filling station', 28: 'barracks', 29: 'silos', 30: 'church',
    31: 'stream', 32: 'fort', 33: 'gun tower', 34: 'coastal gun on a cliff', 35: 'bunker in a hill',
}
for _t in range(20, 36):  # 1070: scene t - 20 of bank 8 (SKYSCRNS.MBK)
    SCREEN_TYPES[_t] += f' (scene {_t - 20}, 1070)'
# 530-531 / 1073 ...: the mission type is an index into mif(30).
MISSION_MAX = 30
BONUS_MAX = 16  # msb / meb index bns(1..16); 0 = none


class LevelError(ValueError):
    """An invalid level: the message says which map, layer and position."""


@dataclass
class Mission:
    """One MISSIONS.DAT record, fields named as the listing names them."""
    briefing: list[str]
    tgtx: int
    strtx: int
    mission: int
    misf: int
    mfin: int
    bonus: int
    msb: int
    meb: int


def decode_missions(raw: bytes) -> list[Mission]:
    if len(raw) == 0 or len(raw) % REC:
        raise LevelError(f'MISSIONS.DAT: {len(raw)} bytes is not a whole number of {REC}-byte records')
    out = []
    for n in range(len(raw) // REC):
        r = raw[n * REC:(n + 1) * REC]
        if r[MD_LEN - 1] != PAD or r[REC - 1] != PAD:
            raise LevelError(f'MISSIONS.DAT record {n + 1}: a pad byte is not a space')
        md, db = r[:MD_LEN], r[MD_LEN:]
        lines = [md[i * LINE_W:(i + 1) * LINE_W].decode('ascii').rstrip(' ') for i in range(LINES)]
        out.append(Mission(lines, db[0] << 8 | db[1], db[2] << 8 | db[3], db[4], db[5], db[6],
                           db[7] << 8 | db[8], db[9], db[10]))
    return out


def encode_missions(missions: list[Mission]) -> bytes:
    out = bytearray()
    for m in missions:
        md = b''.join(line.encode('ascii').ljust(LINE_W, b' ') for line in m.briefing)
        md = md.ljust(LINES * LINE_W, b' ') + bytes([PAD])
        db = bytes([m.tgtx >> 8, m.tgtx & 255, m.strtx >> 8, m.strtx & 255, m.mission, m.misf,
                    m.mfin, m.bonus >> 8, m.bonus & 255, m.msb, m.meb, PAD])
        out += md + db
    return bytes(out)


def check_briefing(text: str, where: str) -> list[str]:
    """The briefing property -> 8 lines. CRLF counts as a line break."""
    lines = text.replace('\r\n', '\n').split('\n')
    while len(lines) > LINES and lines[-1] == '':
        lines.pop()
    if len(lines) > LINES:
        raise LevelError(f'{where}: briefing has {len(lines)} lines, at most {LINES}')
    for i, line in enumerate(lines):
        bad = [c for c in line if not ' ' <= c <= '~']
        if bad:
            raise LevelError(f'{where}: briefing line {i + 1}: {bad[0]!r} is not printable ASCII')
        if len(line.rstrip(' ')) > LINE_W:
            raise LevelError(f'{where}: briefing line {i + 1} is {len(line.rstrip(" "))} characters, '
                             f'at most {LINE_W}: {line!r}')
    return [line.rstrip(' ') for line in lines] + [''] * (LINES - len(lines))


def check_field(value: object, lo: int, hi: int, where: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise LevelError(f'{where}: {value!r} is not an integer')
    if not lo <= value <= hi:
        raise LevelError(f'{where}: {value} is outside {lo}..{hi}')
    return value


def check_mission(m: Mission, where: str) -> None:
    check_field(m.tgtx, 0, WORLD_LEN - 1, f'{where}: tgtx (target screen)')
    check_field(m.strtx, 0, WORLD_LEN - 1, f'{where}: strtx (start screen)')
    check_field(m.mission, 0, MISSION_MAX, f'{where}: property "mission"')
    check_field(m.misf, 0, 255, f'{where}: property "misf"')
    check_field(m.mfin, 0, 255, f'{where}: property "mfin"')
    check_field(m.bonus, 0, 65535, f'{where}: property "bonus"')
    check_field(m.msb, 0, BONUS_MAX, f'{where}: property "msb"')
    check_field(m.meb, 0, BONUS_MAX, f'{where}: property "meb"')


def check_set(missions: list[Mission]) -> None:
    """Rules over the whole set: the game must be able to end."""
    if not 1 <= len(missions) <= MAX_RECORDS:
        raise LevelError(f'{len(missions)} missions: a set has 1..{MAX_RECORDS}')
    if not any(m.mission == 8 for m in missions):
        raise LevelError('no mission has "mission" = 8 (the victory newspaper, 1690): '
                         'the briefing chain would run off the end of MISSIONS.DAT')


def check_world(world: list[int], where: str) -> bytes:
    if len(world) != WORLD_LEN:
        raise LevelError(f'{where}: {len(world)} screens, the world is {WORLD_LEN}')
    for sx, t in enumerate(world):
        at = f'{where}, screen {sx}'
        if t not in SCREEN_TYPES:
            raise LevelError(f'{at}: type {t} is not a screen the game draws (0-17, 20-35)')
        if t == 1 and sx % 10:
            raise LevelError(f'{at}: an airfield must be on a screen divisible by 10 '
                             f'(bases are bse(sx / 10), 2520)')
    if world[0] != 1:
        raise LevelError(f'{where}, screen 0: must be the airfield (type 1): '
                         f'the game pokes it to 1 at every briefing (2352)')
    if world[2] not in (0, 8):
        raise LevelError(f'{where}, screen 2: type {world[2]} would be replaced by the bridge '
                         f'(2525 pokes sc9 + 2 = 8): use 0 or 8')
    return bytes(world)
