// Drive the game under jsbeeb: boot the disc on a Master, run, press keys,
// screenshot.  usage: node test/run.mjs out.png script
// script: comma-separated steps: "w<seconds>" wait, "k<KEY>" tap a key (held 0.1 s),
//         "s<name>" screenshot to build/<name>.png, "d<KEY>"/"u<KEY>" down/up
import { readdirSync, existsSync, writeFileSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import path from "node:path";
function findJsbeeb() {
  const npx = path.join(homedir(), ".npm", "_npx");
  for (const d of readdirSync(npx)) {
    const p = path.join(npx, d, "node_modules", "jsbeeb", "src", "machine-session.js");
    if (existsSync(p)) return p;
  }
  throw new Error("jsbeeb not found");
}
const { MachineSession } = await import(findJsbeeb());
const utils = await import(path.join(path.dirname(findJsbeeb()), "utils.js"));
const disc = path.resolve("build/tron.ssd");
const s = new MachineSession(process.env.MODEL || "Master", {});
await s.initialise();
await s.boot(30);
s.loadDisc(disc);
const KC = utils.keyCodes;
const key = (k) => (k.length === 1 ? k.toUpperCase().charCodeAt(0) : KC[k]);
s.keyDown(KC.SHIFT); s.reset(false); 
await s.runFor(2_000_000 * 0.5);
s.keyUp(KC.SHIFT);
const CPS = 2_000_000;
const labels = {};
for (const m of readFileSync("build/labels.txt", "utf8").matchAll(/^al ([0-9A-F]+) \.(\w+)$/gm)) labels[m[2]] = parseInt(m[1], 16);
const steps = (process.argv[2] || "w8,sshot").split(",");
for (const st of steps) {
  const c = st[0], a = st.slice(1);
  if (c === "w") await s.runFor(Math.round(parseFloat(a) * CPS));
  else if (c === "k") { s.keyDown(key(a)); await s.runFor(CPS / 10); s.keyUp(key(a)); }
  else if (c === "d") s.keyDown(key(a));
  else if (c === "u") s.keyUp(key(a));
  else if (c === "s") { writeFileSync(`build/${a}.png`, await s.screenshotActive({ scale: 2 })); console.log("shot", a); }
  else if (c === "x") { const ad = labels[a] ?? parseInt(a, 16); await s.runUntilAddress(ad, 20); console.log("at", a, JSON.stringify(s.registers())); }
  else if (c === "p") { let o = []; for (let i = 0; i < 80; i++) { await s.runFor(1000); o.push(s.readMemory(labels[a], 1)[0]); } console.log(a, o.join(" ")); }
  else if (c === "t") { const cpu = s._machine.processor; let n = 0, out = []; const h = cpu.debugInstruction.add((pc) => { out.push(`${pc.toString(16)} a${cpu.a.toString(16)} x${cpu.x} y${cpu.y}`); return ++n >= parseInt(a); }); await s.runFor(20000); h.remove(); console.log(out.join("\n")); }
  else if (c === "M") { const cpu = s._machine.processor; const a0 = parseInt(a, 16); console.log(a, Array.from(cpu.ramRomOs.slice(a0, a0 + 24)).join(",")); }
  else if (c === "W") { const [n, v] = a.split(":"); s.writeMemory(labels[n] ?? parseInt(n, 16), v.split("/").map(Number)); }
  else if (c === "r") { const r = s.registers(); console.log(JSON.stringify(r)); }
  else if (c === "m") { const [n, len] = a.split(":"); const ad = labels[n] ?? parseInt(n, 16); console.log(n, s.readMemory(ad, parseInt(len || "8"))); }
}
