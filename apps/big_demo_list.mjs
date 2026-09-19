// The B.I.G. Demo's jukebox list, and the SNDH files behind it — split out of
// apps/big_demo_headless.mjs so that harness stays inside the 200-line rule.
//
// The screen's own data is read from the scene, never duplicated here: if
// anyone ever wires a substitute tune into one of the four entries the archive
// has no SNDH for, the harness sees it on the next run.
import { readFileSync, readdirSync } from "node:fs";

const LIST_ZIG = "apps/zig/scenes/big/list_data.zig"; // the GENERATED rows; list.zig is the provenance
const SUBDIR = "big"; // what a `song` is relative to: the host fetches "music/" + name
const MUSIC_DIR = `docs/music/${SUBDIR}`;
// TEX's OWN table, ripped out of the running demo's memory: 118 rows, of which
// 113 are tunes. The CODEF remake's 116 are a renamed, re-sorted, incomplete
// copy of it (see big/list.zig's header) and are no longer what we ship.
export const ENTRIES = 118;
export const CURSOR = [2, 115]; // curent's range: 2 .. mylist.length-3
export const DIGITAL = ENTRIES - 3; // the row that opens the Digital Solution

/// TEX's 116 entries as { label, song, tune }. `--break songs` points the LAST
/// mapped entry at a file that is not on disk — an entry the other checks do
/// not touch, so only the songs check should notice.
export function readList(brk) {
    const list = [...readFileSync(LIST_ZIG, "utf8")
        .matchAll(/\.\{ \.label = "(.*?)", \.song = "(.*?)", \.tune = (\d+) \}/g)]
        .map(([, label, song, tune]) => ({ label, song, tune: +tune }));
    if (brk !== "songs") return list;
    const i = list.findLastIndex((e) => e.song);
    list[i] = { ...list[i], song: "big/Not_A_Real_Tune.sndh" };
    return list;
}

/// Every song the list names must BE in docs/music/big/.
///
/// This is the no-silent-substitution rule by another route: a tune the player
/// cannot load plays SILENCE, and silence is indistinguishable from the four
/// entries that have no SNDH at all. Deliberate silence is fine; accidental
/// silence from a typo'd or forgotten file is a bug, and without this check it
/// would ship looking exactly like the deliberate kind.
///
/// The other direction — a file shipped that no entry names — is NOT a failure
/// (it may be staged on purpose), but it is reported: it means either dead
/// weight in docs/music/ or an entry someone forgot to wire up.
export function checkSongs(list) {
    const errors = [];
    const named = new Set(list.filter((e) => e.song).map((e) => e.song));
    const onDisk = new Set(readdirSync(MUSIC_DIR).filter((f) => f.endsWith(".sndh")).map((f) => `${SUBDIR}/${f}`));
    for (const song of [...named].sort()) {
        if (onDisk.has(song)) continue;
        const who = list.filter((e) => e.song === song).map((e) => e.label.trim());
        errors.push(`${song} is named by ${who.length} entr${who.length === 1 ? "y" : "ies"} ("${who[0]}") ` +
            `but is not in ${MUSIC_DIR}/: it would play SILENCE, like the entries that have no SNDH at all`);
    }
    return { errors, orphans: [...onDisk].filter((f) => !named.has(f)).sort(), named: named.size, onDisk: onDisk.size };
}
