// The memo's acceptance check, done on the running game: at points in a demo, stop
// where both windows have just been brought up to date (tk_c1), and compare every
// held character of both rings (main and shadow RAM, read from the emulator) with
// what the map and the tile set in sideways RAM say it should be.
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
const G = {}; for (const m of readFileSync("build/gen.inc", "utf8").matchAll(/^(\w+) = \$?([0-9A-F]+)$/gm)) G[m[1]] = /\$/.test(m[0]) ? parseInt(m[2], 16) : parseInt(m[2]);
const cpu = s._machine.processor, ram = cpu.ramRomOs;
const rd = (a) => cpu.readmem(a);
await s.runFor(20e6);
s.keyDown(50); await s.runFor(2e5); s.keyUp(50);     // two players: straight lines,
const turns = ["X", "Z", "X", "X", "Z", "Z", "X"];   // then some turns
let checks = 0, bad = 0;
for (let k = 0; k < Number(process.argv[2] || 12); k++) {
  await s.runFor(2e6 * 0.37);
  if (k > 2 && k % 2) { const c = turns[k % turns.length].charCodeAt(0); s.keyDown(c); await s.runFor(2e5); s.keyUp(c); }
  await s.runUntilAddress(L.tk_c1, 5);
  for (let w = 0; w < 2; w++) {
    const vcx = rd(L.vcxl + w) | (rd(L.vcxh + w) << 8), vcy = rd(L.vcy + w);
    let mism = 0;
    for (let r = 0; r < 17; r++) for (let c = 0; c < 80; c++) {
      const cx = vcx + c, cy = vcy + r;
      const id = rd(G.MAP + (cy >> 1) * G.MAPW + cx);
      const ring = 0x3000 + 8 * (((cy % 32) * 80 + cx) % 2560);
      for (let l = 0; l < 8; l++) {
        const want = rd(G.TILES + id * 16 + (cy & 1) * 8 + l);
        const got = ram[(ring + l) | (w ? 0x8000 : 0)];
        if (want !== got) mism++;
      }
    }
    checks++; if (mism) bad++;
    console.log(`t${k} window ${w}: camera (${vcx}, ${vcy}) f=${rd(L.wf + w)} state ${rd(L.state)}: ${mism} bytes differ`);
  }
}
console.log(`${checks - bad}/${checks} window checks exact`);
