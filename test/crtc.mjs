// Where every chain step's writes land, over a stretch of play: the ACCCON D write
// (it must fall in the horizontal blanking of the last line before its section:
// h >= 80 on the line before, never in the section's first line), and the first CRTC
// write (R9) and the address write (R13), which must come after the section began.
// usage: node test/crtc.mjs [seconds of play]
import { readdirSync, existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import path from "node:path";
function findJsbeeb() { const npx = path.join(homedir(), ".npm", "_npx"); for (const d of readdirSync(npx)) { const p = path.join(npx, d, "node_modules", "jsbeeb", "src", "machine-session.js"); if (existsSync(p)) return p; } }
const { MachineSession } = await import(findJsbeeb());
const s = new MachineSession(process.env.MODEL || "Master", {}); await s.initialise(); await s.boot(30);
s.loadDisc(path.resolve("build/tron.ssd"));
const utils = await import(path.join(path.dirname(findJsbeeb()), "utils.js"));
s.keyDown(utils.keyCodes.SHIFT); s.reset(false); await s.runFor(1e6); s.keyUp(utils.keyCodes.SHIFT);
const L = {}; for (const m of readFileSync("build/labels.txt", "utf8").matchAll(/^al ([0-9A-F]+) \.(\w+)$/gm)) L[m[2]] = parseInt(m[1], 16);
const cpu = s._machine.processor, v = s._video;
await s.runFor(24e6);
s.keyDown(50); await s.runFor(2e5); s.keyUp(50); await s.runFor(8e6);
// find the handler's writes: sta ACCCON (8D 34 FE), the first sta CRTC_DAT after it, and R13's
const code = (a) => cpu.readmem(a);
let DW = 0; for (let a = L.irq_handler; a < L.irq_handler + 64; a++) if (code(a) === 0x8D && ((code(a + 1) === 0x34 && code(a + 2) === 0xFE) || (code(a + 1) === (L.dummyacc & 255) && code(a + 2) === (L.dummyacc >> 8)))) { DW = a; break; } // (the Model B's: patch_b's RAM byte)
let R9 = 0; for (let a = DW + 3; a < DW + 64; a++) if (code(a) === 0x8D && code(a + 1) === 0x01 && code(a + 2) === 0xFE) { R9 = a; break; }
R9 += 3; for (let a = R9; a < R9 + 64; a++) if (code(a) === 0x8D && code(a + 1) === 0x01 && code(a + 2) === 0xFE) { R9 = a; break; } // (the first is the cursor clear)
let R13 = 0; for (let a = L.irq_handler; a < L.irq_handler + 200; a++) if (code(a) === 0xBD && code(a + 1) === (L.SECTAB + 1 & 255) && code(a + 2) === (L.SECTAB + 1 >> 8)) { R13 = a + 3; break; }
const stats = {}, bad = [];
let sec = 0, newSec = false;
const ent = []; let hist = []; let dumped = false;
cpu.debugInstruction.add((pc) => {
  hist.push(pc); if (hist.length > 400) hist.shift();
  if (pc === L.irq_handler) { ent.push(`irq at vc${v.vertCounter} sc${v.scanlineCounter} h${v.horizCounter} sec${cpu.readmem(L.SECIDX)} prev ${hist.slice(-4,-1).map(x=>x.toString(16)).join(' ')}`); if (ent.length > 12) ent.shift(); }
  if (pc === DW) { sec = cpu.x / 8; const lineEnd = v.horizCounter >= 80; const d = cpu.a & 1;
    const prevD = 1 - d; const k = `D sec${sec}`; stats[k] = stats[k] || { n: 0, firstLine: 0 };
    stats[k].n++;
    // a D change must not land after its section's first line has started
    if ((sec === 2 || sec === 4) && v.scanlineCounter === 0 && v.vertCounter === 0 && v.horizCounter < 80) { stats[k].firstLine++; if (bad.length < 5) bad.push(`D for sec${sec} at vc${v.vertCounter} sc${v.scanlineCounter} h${v.horizCounter}`); }
  }
  if (pc === R9 || pc === R13) { const k = `${pc === R9 ? "R9" : "R13"} sec${sec}`; stats[k] = stats[k] || { n: 0, late: 0, where: {} };
    stats[k].n++; const w = `vc${v.vertCounter} sc${v.scanlineCounter}`; stats[k].where[w] = (stats[k].where[w] || 0) + 1;
    // R9 (the section's shape) in its first line; R13 (the next address) by the end of its
    // second, the shortest section's last
    const ok = v.vertCounter === 0 && (pc === R9 ? v.scanlineCounter === 0 : v.scanlineCounter <= 1);
    if (!ok) { if (!dumped) { dumped = true; console.log(ent.join('\n')); console.log('hist', hist.slice(-400, -300).map(x=>x.toString(16)).join(' ')); } stats[k].late++; if (bad.length < 10) bad.push(`${k} at vc${v.vertCounter} sc${v.scanlineCounter} h${v.horizCounter} (state ${cpu.readmem(L.state)}, wf ${cpu.readmem(L.wf)}, sec ${cpu.readmem(L.SECCUR)}, t ${(cpu.currentCycles / 2e6).toFixed(2)} s)`); } }
  return false;
});
await s.runFor(Number(process.argv[2] || 20) * 2e6);
console.log(JSON.stringify(stats, null, 0));
console.log(bad.join("\n") || "all on time: D before its section, R9 in its first line, R13 by the end of its second");
