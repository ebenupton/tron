// Where the time goes: cycles by routine (the nearest label below the PC, main RAM
// and the code bank) over some seconds of one-player play.  MODEL=B1770 for a B.
// usage: node test/pcprof.mjs [seconds]
import { readdirSync, existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os"; import path from "node:path";
function findJsbeeb() { const npx = path.join(homedir(), ".npm", "_npx"); for (const d of readdirSync(npx)) { const p = path.join(npx, d, "node_modules", "jsbeeb", "src", "machine-session.js"); if (existsSync(p)) return p; } }
const { MachineSession } = await import(findJsbeeb());
const utils = await import(path.join(path.dirname(findJsbeeb()), "utils.js"));
const s = new MachineSession(process.env.MODEL || "Master", {}); await s.initialise(); await s.boot(30);
s.loadDisc(path.resolve("build/tron.ssd"));
s.keyDown(utils.keyCodes.SHIFT); s.reset(false); await s.runFor(1e6); s.keyUp(utils.keyCodes.SHIFT);
const labs = []; for (const m of readFileSync("build/labels.txt", "utf8").matchAll(/^al ([0-9A-F]+) \.(\w+)$/gm)) labs.push([parseInt(m[1], 16), m[2]]);
labs.sort((a, b) => a[0] - b[0]);
const name = new Map();
const lookup = (pc) => { let lo = 0, hi = labs.length - 1, r = "?"; while (lo <= hi) { const m = (lo + hi) >> 1; if (labs[m][0] <= pc) { r = labs[m][1]; lo = m + 1; } else hi = m - 1; } return r; };
await s.runFor(16e6);
s.keyDown(49); await s.runFor(2e5); s.keyUp(49);
await s.runFor(8e6);
const cpu = s._machine.processor;
const acc = new Map(); let last = cpu.currentCycles, lastPc = 0, total = 0;
const h = cpu.debugInstruction.add((pc) => {
  const c = cpu.currentCycles; const d = c - last; last = c;
  if (d > 0 && d < 100) { let n = name.get(lastPc); if (!n) { n = lastPc >= 0xC000 ? "MOS" : lookup(lastPc); name.set(lastPc, n); } acc.set(n, (acc.get(n) || 0) + d); total += d; }
  lastPc = pc; return false;
});
await s.runFor(2e6 * Number(process.argv[2] || 5));
h.remove();
const rows = [...acc.entries()].sort((a, b) => b[1] - a[1]).slice(0, 30);
for (const [n, c] of rows) console.log(n.padEnd(16), (100 * c / total).toFixed(1).padStart(5) + "%", Math.round(c / (Number(process.argv[2] || 5) * 25)), "cyc/tick");
