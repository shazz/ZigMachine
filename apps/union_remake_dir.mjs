// Where the untracked remakes are. prototypes/ is not in git: a worktree has no
// copy of its own and a fresh clone has none at all, so the checks that re-read
// a remake look in the main checkout, and SKIP (saying so) when there is none.
// They never fail for a missing remake: build.sh must pass on a fresh clone.
import { existsSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { dirname, join } from "node:path";

export const UNION_REMAKE = "prototypes/oldies/Union-Demo-HTML5-Remake-0.9.8";

/// The main checkout's root (the directory holding git's common dir; a worktree
/// shares it), or null outside a git checkout.
export function mainCheckoutRoot() {
    try {
        const common = execFileSync("git", ["rev-parse", "--path-format=absolute", "--git-common-dir"], { stdio: ["ignore", "pipe", "ignore"] });
        return dirname(common.toString().trim());
    } catch {
        return null;
    }
}

/// The Union Demo 0.9.8 remake: env UNION_REMAKE_DIR, else the main checkout's
/// copy, else null. A directory counts when `marker` exists in it. `tried` lists
/// every directory looked at, for the caller's SKIPPED line.
export function findUnionRemake(marker = "main.js") {
    const tried = [];
    const has = (d) => {
        tried.push(d);
        return existsSync(join(d, marker));
    };
    const env = process.env.UNION_REMAKE_DIR;
    if (env && has(env)) return { dir: env, tried };
    const root = mainCheckoutRoot();
    if (root && has(join(root, UNION_REMAKE))) return { dir: join(root, UNION_REMAKE), tried };
    return { dir: null, tried };
}
