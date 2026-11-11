// a flat profiler: cycles by routine (the nearest label below the PC) over N ticks of play
import { readdirSync, existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import path from "node:path";
function findJsbeeb() { const npx = path.join(homedir(), ".npm", "_npx"); for (const d of readdirSync(npx)) { const p = path.join(npx, d, "node_modules", "jsbeeb", "src", "machine-session.js"); if (existsSync(p)) return p; } }
const { MachineSession } = await import(findJsbeeb());
const s = new MachineSession("Master", {}); await s.initialise(); await s.boot(30);
s.loadDisc(path.resolve("build/tron.ssd"));
const utils = await import(path.join(path.dirname(findJsbeeb()), "utils.js"));
s.keyDown(utils.keyCodes.SHIFT); s.reset(false); await s.runFor(1e6); s.keyUp(utils.keyCodes.SHIFT);
const L = {}; for (const m of readFileSync("build/labels.txt", "utf8").matchAll(/^al ([0-9A-F]+) \.(\w+)$/gm)) { const a = parseInt(m[1], 16); if (a >= 0xe00 && a < 0x3000 && !/^__/.test(m[2])) L[a] = m[2]; }
const addrs = Object.keys(L).map(Number).sort((a, b) => a - b);
const owner = new Array(0x3000).fill("?");
for (let i = 0; i < addrs.length; i++) for (let a = addrs[i]; a < (addrs[i + 1] || 0x3000); a++) owner[a] = L[addrs[i]];
const cpu = s._machine.processor;
await s.runFor(24e6);
s.keyDown(50); await s.runFor(2e5); s.keyUp(50);
await s.runFor(9e6);
const cyc = () => cpu.currentCycles + cpu.cycleSeconds * 2e6;
const tot = {}; let lastC = cyc(), lastO = "?";
cpu.debugInstruction.add((pc) => {
  const c = cyc(); tot[lastO] = (tot[lastO] || 0) + (c - lastC); lastC = c;
  lastO = pc < 0x3000 && pc >= 0xe00 ? owner[pc] : (pc >= 0xc000 ? "MOS" : "other");
  return false;
});
const ticks = Number(process.argv[2] || 50);
await s.runFor(80000 * ticks);
const all = Object.values(tot).reduce((a, b) => a + b, 0);
for (const [k, v] of Object.entries(tot).sort((a, b) => b[1] - a[1]).slice(0, 25)) console.log(k.padEnd(16), (v / ticks).toFixed(0).padStart(7), "cyc/tick", (100 * v / all).toFixed(1) + "%");
