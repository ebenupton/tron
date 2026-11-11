// Screenshots of the countdown and the score screen, taken when the game reaches
// them: node test/shots.mjs PREFIX  (MODEL=B1770 for a Model B) -> build/PREFIX2.png, PREFIX8.png
import { readdirSync, existsSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os"; import path from "node:path";
function findJsbeeb() { const npx = path.join(homedir(), ".npm", "_npx"); for (const d of readdirSync(npx)) { const p = path.join(npx, d, "node_modules", "jsbeeb", "src", "machine-session.js"); if (existsSync(p)) return p; } }
const { MachineSession } = await import(findJsbeeb());
const utils = await import(path.join(path.dirname(findJsbeeb()), "utils.js"));
const s = new MachineSession(process.env.MODEL || "Master", {}); await s.initialise(); await s.boot(30);
s.loadDisc(path.resolve("build/tron.ssd"));
s.keyDown(utils.keyCodes.SHIFT); s.reset(false); await s.runFor(1e6); s.keyUp(utils.keyCodes.SHIFT);
const L = {}; for (const m of readFileSync("build/labels.txt", "utf8").matchAll(/^al ([0-9A-F]+) \.(\w+)$/gm)) L[m[2]] = parseInt(m[1], 16);
const cpu = s._machine.processor; const rd = a => cpu.readmem(a);
const want = { 2: 1.5, 8: 1.0 }; const got = {}; const pre = process.argv[2] || "s";
for (let t = 0; t < 3000 && Object.keys(got).length < 2; t++) {
  await s.runFor(1e5); const st = rd(L.state);
  if (want[st] !== undefined && !got[st]) { await s.runFor(want[st] * 2e6); writeFileSync(`build/${pre}${st}.png`, await s.screenshotActive({ scale: 2 })); got[st] = 1; console.log("shot", st); }
}
