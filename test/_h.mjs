

import { readdirSync, existsSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os"; import path from "node:path";
function findJsbeeb() { const npx = path.join(homedir(), ".npm", "_npx"); for (const d of readdirSync(npx)) { const p = path.join(npx, d, "node_modules", "jsbeeb", "src", "machine-session.js"); if (existsSync(p)) return p; } }
const { MachineSession } = await import(findJsbeeb());
const utils = await import(path.join(path.dirname(findJsbeeb()), "utils.js"));
const s = new MachineSession(process.env.MODEL || "Master", {}); await s.initialise(); await s.boot(30);
s.loadDisc(path.resolve("build/tron.ssd"));
s.keyDown(utils.keyCodes.SHIFT); s.reset(false); await s.runFor(1e6); s.keyUp(utils.keyCodes.SHIFT);
const L = {}; for (const m of readFileSync("build/labels.txt", "utf8").matchAll(/^al ([0-9A-F]+) \.(\w+)$/gm)) L[m[2]] = parseInt(m[1], 16);
const rd = a => s._machine.processor.readmem(a);
await s.runFor(30e6); let n=0;
for (let i=0;i<3000 && n<3;i++){ await s.runFor(1e5);
  const hx = rd(L.hbxl)|(rd(L.hbxh)<<8), wx = rd(L.wcxl+1)|(rd(L.wcxh+1)<<8), ht=rd(L.htopl)|(rd(L.htoph)<<8), wy=rd(L.wcy+1)*8;
  if (rd(L.state)===2 && !rd(L.bdead) && hx>wx+8 && hx<wx+72 && ht>wy+16 && ht<wy+110){ writeFileSync(`build/head${n}.png`, await s.screenshotActive({scale:2})); console.log('shot',n,i); n++; await s.runFor(4e6);} }
