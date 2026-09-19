// "The Digital Solution"'s six menu entries and the SNDH files behind them —
// split out of apps/digital_solution_headless.mjs so that harness stays inside
// the 200-line rule. The screen is part of the B.I.G. Demo's cart, so the table
// lives in apps/zig/scenes/big/digital.zig.
//
// The table is READ FROM THE SCENE, never duplicated here: if anyone re-points
// an entry at another tune or another subtune, the harness sees it on the next
// run rather than agreeing with itself.
import { readFileSync, readdirSync } from "node:fs";
import { sndhPlay } from "./big_demo_machine.mjs";

const SCENE = "apps/zig/scenes/big/digital.zig";
const SUBDIR = "digital"; // what a `song` is relative to: the host fetches "music/" + name
const MUSIC_DIR = `docs/music/${SUBDIR}`;
export const ENTRIES = 6; // "DARE TO PRESS:" 1..6, read off the capture

/// The scene's TUNES as { label, song, tune }.
///
/// --break tune shifts ONE entry's subtune by one — the PHANTOMS pair is the
/// whole reason this screen has six entries and five files, so getting a
/// subtune wrong there is the mistake most worth proving we catch.
/// --break songs points an entry at a file that is not on disk.
export function readTunes(brk) {
    const list = [...readFileSync(SCENE, "utf8")
        .matchAll(/\.\{ \.label = "(.*?)", \.song = "(.*?)", \.tune = (\d+) \}/g)]
        .map(([, label, song, tune]) => ({ label, song, tune: +tune }));
    if (brk === "tune") {
        const i = list.findIndex((e) => /PHANTOMS 2/.test(e.label));
        list[i] = { ...list[i], tune: list[i].tune + 1 };
    }
    if (brk === "songs") {
        const i = list.findLastIndex((e) => e.song);
        list[i] = { ...list[i], song: `${SUBDIR}/Not_A_Real_Tune.sndh` };
    }
    return list;
}

/// Every song the table names must BE in docs/music/digital/.
///
/// A tune the player cannot load plays SILENCE, and silence from a typo is
/// indistinguishable from a key that does nothing — it would ship looking like
/// a design choice. This screen has no deliberately-silent entry at all: all
/// six are meant to sound, so any missing file is unambiguously a bug.
export function checkSongs(list) {
    const errors = [];
    const named = new Set(list.map((e) => e.song));
    const onDisk = new Set(readdirSync(MUSIC_DIR).filter((f) => f.endsWith(".sndh")).map((f) => `${SUBDIR}/${f}`));
    for (const song of [...named].sort()) {
        if (onDisk.has(song)) continue;
        const who = list.filter((e) => e.song === song).map((e) => e.label);
        errors.push(`${song} is named by "${who[0]}" but is not in ${MUSIC_DIR}/: that key would play SILENCE`);
    }
    return { errors, orphans: [...onDisk].filter((f) => !named.has(f)).sort(), named: named.size, onDisk: onDisk.size };
}

/// Render all six on the sealed audio machine. Every one is FLAG ~ay — STE DMA,
/// which the player does not emulate and which USUALLY means a clean load and
/// SILENCE — so whether they sound is measured, never assumed. `missing` names
/// the ones checkSongs already failed on; there is no file to render for those.
export async function measurePeaks(list, missing, errors) {
    const peaks = [];
    for (const e of list) {
        if (missing.has(e.song)) continue;
        const r = await sndhPlay(e.song, e.tune);
        if (r.why) { errors.push(`${e.song} #${e.tune}: ${r.why}`); continue; }
        peaks.push(`${e.label.split(". ")[1]} ${r.peak.toFixed(3)}`);
        if (r.peak <= 0.01 || r.stuckPc)
            errors.push(`"${e.label}" (${e.song} #${e.tune}): peak ${r.peak.toFixed(4)}, stuck PC ${r.stuckPc} — it would ship SILENT`);
    }
    return peaks;
}
