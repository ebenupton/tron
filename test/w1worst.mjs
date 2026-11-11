// The worst W1 drawing ticks (crit_window, W1): lines from 256 to each phase.
// usage: node test/w1worst.mjs SECONDS   (demo mode; MODEL=B1770 for a B)
import { readdirSync, existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os"; import path from "node:path";
function findJsbeeb() { const npx = path.join(homedir(), ".npm", "_npx"); for (const d of readdirSync(npx)) { const p = path.join(npx, d, "node_modules", "jsbeeb", "src", "machine-session.js"); if (existsSync(p)) return p; } }
const { MachineSession } = await import(findJsbeeb());
const utils = await import(path.join(path.dirname(findJsbeeb()), "utils.js"));
const s = new MachineSession(process.env.MODEL || "Master", {}); await s.initialise(); await s.boot(30);
s.loadDisc(path.resolve("build/tron.ssd"));
s.keyDown(utils.keyCodes.SHIFT); s.reset(false); await s.runFor(1e6); s.keyUp(utils.keyCodes.SHIFT);
const L = {}; for (const m of readFileSync("build/labels.txt", "utf8").matchAll(/^al ([0-9A-F]+) \.(\w+)$/gm)) L[m[2]] = parseInt(m[1], 16);
const cpu = s._machine.processor, v = s._video;
const vline = () => ((280 + v.bitmapY / 2) % 312) | 0;
const names = ["commit", "draw_col", "draw_char", "draw_dirty", "glint_poke", "compose_copy", "fx_window", "tk_c1", "tk_c0"];
const marks = new Map(names.map((n) => [L[n], n]));
let cur = null, all = [];
cpu.debugInstruction.add((pc) => {
  if (pc === L.crit_window) { cur = { w: cpu.x, l0: vline(), t0: cpu.currentCycles, ev: [] }; return false; }
  const m = marks.get(pc); if (!m || !cur) return false;
  const ln = Math.round((cpu.currentCycles - cur.t0) / 128);
  cur.ev.push(`${m}+${ln}`);
  if (m === "tk_c1" || m === "tk_c0") { const end = (cur.l0 + ln - (cur.w ? 256 : 128) + 312) % 312; all.push({ w: cur.w, end, l0: cur.l0, txt: cur.ev.join(" "), st: cpu.readmem(L.state), wf: [cpu.readmem(L.wf), cpu.readmem(L.wf + 1)] }); cur = null; }
  return false;
});
await s.runFor(2e6 * Number(process.argv[2] || 60));
for (const w of [0, 1]) { const a = all.filter((r) => r.w === w).sort((x, y) => y.end - x.end).slice(0, 6); console.log(`W${w} worst (lines after ${w ? 256 : 128}):`); for (const r of a) console.log(`  ${r.end} start ${r.l0} st ${r.st} wf ${r.wf}  ${r.txt}`); }
