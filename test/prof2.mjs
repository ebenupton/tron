// each tick's phases as frame lines (0 = W0's first line), over a few seconds of play
import { readdirSync, existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import path from "node:path";
function findJsbeeb() { const npx = path.join(homedir(), ".npm", "_npx"); for (const d of readdirSync(npx)) { const p = path.join(npx, d, "node_modules", "jsbeeb", "src", "machine-session.js"); if (existsSync(p)) return p; } }
const { MachineSession } = await import(findJsbeeb());
const s = new MachineSession("Master", {}); await s.initialise(); await s.boot(30);
s.loadDisc(path.resolve("build/tron.ssd"));
const utils = await import(path.join(path.dirname(findJsbeeb()), "utils.js"));
s.keyDown(utils.keyCodes.SHIFT); s.reset(false); await s.runFor(1e6); s.keyUp(utils.keyCodes.SHIFT);
const L = {}; for (const m of readFileSync("build/labels.txt", "utf8").matchAll(/^al ([0-9A-F]+) \.(\w+)$/gm)) L[m[2]] = parseInt(m[1], 16);
const cpu = s._machine.processor, v = s._video;
await s.runFor(24e6);
s.keyDown(process.argv[2] === "1" ? 49 : 50); await s.runFor(2e5); s.keyUp(49); s.keyUp(50);
await s.runFor(9e6);
const cyc = () => cpu.currentCycles + cpu.cycleSeconds * 2e6;
let vsyncCyc = 0;
const marks = { crit_window: "c", tk_c0: "C0", tk_c1: "C1", tk_lg: "LG", tk_end: "END" };
const pcs = new Map(Object.entries(marks).map(([k, m]) => [L[k], m]));
let row = [], rows = [], lastVs = -1;
cpu.debugInstruction.add((pc) => {
  const m = pcs.get(pc); if (!m) return false;
  // frame line: from the CRTC's own counters, made absolute by the section
  const sec = cpu.readmem(L.SECCUR);
  const tag = `${m}@${sec === 248 ? "vb" : sec / 8}`;
  if (row[row.length - 1] !== tag) row.push(tag);
  if (m === "END") { rows.push(row.join(" ")); row = []; }
  return false;
});
await s.runFor(40000 * 2 * Number(process.argv[3] || 60));
console.log(rows.join("\n"));
