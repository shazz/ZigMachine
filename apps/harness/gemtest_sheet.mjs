// gemtest_shots.mjs's contact sheet: one row a component, its low, medium and desk shots side by side;
// with --assets each shot has that mode's TOS 4 reference under it (st_low, st_medium, st_high), and a
// last column holds the references common to the three (fonts, icons, the alert glyphs).
import path from "node:path";

const imgs = (list) => list.map((r) => `<img class=ref src="${r}" title="${r}"><br><small>${path.basename(r)}</small>`).join("<br>");
const NONE = "<i>no matching reference</i>";

function cell(sheet, refs, name, m) {
    const f = sheet[name][m], r = refs?.[name];
    const shot = f ? `<img src="${f}"><br><small>${f}</small>` : "-";
    return `<td>${shot}${r ? `<hr>${r[m].length ? imgs(r[m]) : NONE}` : ""}</td>`;
}

function common(refs, name) {
    if (!refs) return "";
    const r = refs[name];
    return `<td>${r[3].length ? imgs(r[3]) : r.slice(0, 3).some((l) => l.length) ? "" : NONE}</td>`;
}

/** The sheet: {component: [low, medium, desk] file names}, refs from gemtest_refs.mjs or null. */
export function sheetHtml(sheet, refs, rom) {
    const rows = Object.keys(sheet).map((n) => `<tr><th>${n}</th>${[0, 1, 2].map((m) => cell(sheet, refs, n, m)).join("")}${common(refs, n)}</tr>`);
    return `<!doctype html><meta charset="utf-8"><title>GEMTEST shots</title>
<style>body{background:#222;color:#ddd;font:13px sans-serif}td,th{vertical-align:top;padding:6px;border-bottom:1px solid #444}
img{image-rendering:pixelated;max-width:640px}img.ref{max-width:400px;background:#fff}th{text-align:left}</style>
<h1>GEMTEST: every component in low, medium and the desk${refs ? ", the TOS 4 references under each" : ""}</h1>
<p>ROM: ${rom}. Low and medium as on the screen (rows doubled); the 1:1 PNGs are beside them in the directory.
${refs ? "References: st_low under low, st_medium under medium, st_high under the desk." : ""}</p>
<table><tr><th>component</th><th>low</th><th>medium</th><th>desk</th>${refs ? "<th>references (all modes)</th>" : ""}</tr>
${rows.join("\n")}</table>`;
}
