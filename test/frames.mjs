// Soak against the reference model: run the game under jsbeeb, drive it, and stream
// every displayed field and every tick's logical state to tools/model.py, which
// checks each window of each field against its own rendering of the arena.
//
// usage: node test/frames.mjs [seconds] [mode] [seed] [-- model args]
//   mode: 1 (one player, random steering), 2 (two players, random), demo
import { readdirSync, existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { spawn } from "node:child_process";
import path from "node:path";
function findJsbeeb() { const npx = path.join(homedir(), ".npm", "_npx"); for (const d of readdirSync(npx)) { const p = path.join(npx, d, "node_modules", "jsbeeb", "src", "machine-session.js"); if (existsSync(p)) return p; } }
const { MachineSession } = await import(findJsbeeb());
const utils = await import(path.join(path.dirname(findJsbeeb()), "utils.js"));
const argv = process.argv.slice(2);
const dd = argv.indexOf("--");
const margs = dd >= 0 ? argv.slice(dd + 1) : [];
const [secs = "60", mode = "1", seedArg = "1"] = dd >= 0 ? argv.slice(0, dd) : argv;
const py = spawn("python3", ["tools/model.py", ...margs], { stdio: ["pipe", "inherit", "inherit"] });
const done = new Promise((r) => py.on("close", r));

const s = new MachineSession(process.env.MODEL || "Master", {}); await s.initialise(); await s.boot(30);
s.loadDisc(path.resolve("build/tron.ssd"));
s.keyDown(utils.keyCodes.SHIFT); s.reset(false); await s.runFor(1e6); s.keyUp(utils.keyCodes.SHIFT);
const L = {}; for (const m of readFileSync("build/labels.txt", "utf8").matchAll(/^al ([0-9A-F]+) \.(\w+)$/gm)) L[m[2]] = parseInt(m[1], 16);
const cpu = s._machine.processor, v = s._video, fb = s._fb32;
const rd = (a) => cpu.readmem(a);
const pair = (n) => [rd(L[n]), rd(L[n] + 1)];
const w16 = (lo, hi, i) => rd(L[lo] + i) | (rd(L[hi] + i) << 8);

let out = []; let fxSkips = 0, fxDrawn = 0, fxRuns = 0, gameOn = false, oddFrames = 0, maxW0 = 0, maxW1 = 0, maxCommit1 = 0; const bline = () => ((280 + v.bitmapY / 2) % 312) | 0; let xdone = [false, false], sdone = false, rdone = false; const EVLOG = []; let fieldNo = 0; const vline = () => ((280 + v.bitmapY / 2) % 312) | 0;
const rec = (t, buf) => { const h = Buffer.alloc(5); h.write(t, 0); h.writeUInt32LE(buf.length, 1); out.push(h, buf); };
let leadMax = 0; let wild = 0, brk = 0, firstWild = null, hist = [], ticks = 0;
// the glint's lower row: where its CRTC writes land (R10, R11 in the upper row's last
// line; the address after the beam has passed the cursor's column, before it comes back)
const G = { n: 0, bad: 0, early: 99, late: 99, first: null }; let gcol = 0;
const findUser = () => { for (let a = L.irq_handler; a < L.irq_handler + 400; a++) if (rd(a) === 0x2c && rd(a + 1) === 0x6d && rd(a + 2) === 0xfe) { L.irq_user = a; break; } };
let GW = null; // the four sta CRTC_DAT after irq_user, found once the code is loaded
const findGW = () => { const o = []; for (let a = L.irq_user; a < L.irq_user + 80 && o.length < 4; a++) if (rd(a) === 0x8d && rd(a + 1) === 0x01 && rd(a + 2) === 0xfe) o.push(a - L.irq_user); GW = { r10: o[0], r11: o[1], r14: o[2], r15: o[3] }; };
cpu.debugInstruction.add((pc, op) => {
  if (!L.irq_user && pc === L.irq_handler) findUser();
  if (pc === L.irq_handler && gameOn && (rd(0xfe4d) & 0x40)) { const ln = bline(); if (ln === 127 || ln === 255) leadMax = Math.max(leadMax, v.horizCounter); }
  if (process.env.GDBG && pc === L.irq_handler && fieldNo === Number(process.env.GDBG)) { const ln = bline(); if (ln === 255 && v.horizCounter > 70) console.log('LATE hist', hist.map(x => x.toString(16)).join(' ')); }
  if (process.env.GDBG && false && Math.abs(fieldNo - Number(process.env.GDBG)) <= 1 && (pc === L.irq_handler || pc === L.irq_user || pc === L.irq_user + 46)) console.log('irq f', fieldNo, 'pc', (pc - L.irq_handler), 'line', bline(), 'h', v.horizCounter, 'sc', v.scanlineCounter, 'sysifr', rd(0xfe4d).toString(16), 'uifr', rd(0xfe6d).toString(16), 'secidx', rd(L.SECIDX), 'c2', rd(L.c2idx), 'prevpc', hist.slice(-3).map(x=>x.toString(16)).join(' '));
  if (L.irq_user && !GW) findGW();
  if (GW && pc >= L.irq_user && pc <= L.irq_user + GW.r15) {
    const o = pc - L.irq_user, sc = v.scanlineCounter, h = v.horizCounter;
    const p = sc === 7 ? h : sc === 0 ? 128 + h : -999;
    if (o === GW.r10) { G.n++; gcol = (v.cursorPos - v.lineStartAddr) & 0x3fff; if (p < 0 || p >= 128 || gcol >= 80) { G.bad++; if (!G.first) console.log('GLINTBAD c2', rd(L.c2idx), 'cur', v.cursorPos.toString(16), 'line', v.lineStartAddr.toString(16), 'vc', v.vertCounter, 'sc', sc, 'SECIDX', rd(L.SECIDX), 'CURS1', Array.from({length:9},(_, i)=>rd(L.CURS+16+i).toString(16)).join(' '), 'SEC', Array.from({length:48},(_, i)=>rd(L.SECTAB+i).toString(16)).join(' '), 'wk', rd(L.wk), rd(L.wk+1)); G.first ??= { o, sc, h, gcol, f: fieldNo }; } }
    if (o === GW.r11 && (p < 0 || p >= 128)) { G.bad++; G.first ??= { o, sc, h, gcol, f: fieldNo }; }
    if (o === GW.r14) { G.early = Math.min(G.early, p - gcol); if (p <= gcol) { G.bad++; G.first ??= { o, sc, h, gcol, f: fieldNo }; } }
    if (o === GW.r15) { G.late = Math.min(G.late, 128 + gcol - p); if (p + 4 >= 128 + gcol) { G.bad++; G.first ??= { o, sc, h, gcol, f: fieldNo }; } }
  }
  hist.push(pc); if (hist.length > 48) hist.shift();
  if ((pc >= 0x3000 && pc < 0x8000) || (op === 0 && pc < 0x8000)) { wild++; if (!firstWild) firstWild = { pc, hist: hist.map((x) => x.toString(16)).join(" ") }; }
  if (process.env.EVLOG && [L.crit_window, L.commit, L.tk_c1, L.tk_lg, L.fx_square, L.draw_col, L.draw_dirty, L.compose_copy, L.fx_window, L.prep_window, L.run_state].includes(pc)) EVLOG.push(`f${fieldNo} @${vline()} ${Object.keys(L).find(k => L[k] === pc && /^[a-z]/.test(k))} x${cpu.x} fxt${rd(L.fxt)} k${rd(L.glph)}`);
  if ((pc === L.new_round || pc === L.new_round + 3) && !rdone) { rdone = true; rec("R", Buffer.alloc(0)); }
  if (pc === L.fx_time && rd(L.fxt) !== 255) fxRuns++;
  if (pc === L.cc_done && rd(L.win) === 0) { const l = bline(); if (l < 128 || l > 300) console.log('W0 COMPOSE LATE line', l, 'field', fieldNo, 'state', rd(L.state), 'wf', rd(L.wf)); }
  if (pc === L.crit_window && cpu.x === 0) { const l = bline(); if (l < 128 || l > 150) console.log('W0 START line', l, 'field', fieldNo, 'state', rd(L.state)); }
  if (pc === L.fx_window + 0 && false) {}
  if (pc === L.fx_frag && rd(L.glph) === 0) fxDrawn++;
  if (pc === L.fx_time + 0x14 && false) {}
  // (a hook can miss an instruction an interrupt lands on: each record has two triggers)
  const xw = (pc === L.tk_w1 || pc === L.tk_w1 + 2) ? 0 : (pc === L.tk_c1 || pc === L.run_state) ? 1 : -1;
  if (xw === 0 && !xdone[0]) maxW0 = Math.max(maxW0, (bline() - 128 + 312) % 312);
  if (xw === 1 && !xdone[1]) { const v1 = (bline() - 256 + 312) % 312; if (v1 > maxW1) { maxW1 = v1; if (v1 > 175) console.log('W1MAX', v1, 'field', fieldNo, 'state', rd(L.state), 'fxt', rd(L.fxt), 'wf', rd(L.wf), rd(L.wf+1)); } }
  if (pc === L.commit && cpu.x === 1 && rd(L.state) === 4) maxCommit1 = Math.max(maxCommit1, (bline() - 256 + 312) % 312);
  if (xw === 0) sdone = false;
  if (xw >= 0 && !xdone[xw]) { xdone[xw] = true; rec("X", Buffer.from(JSON.stringify({ w: xw, exfrm: Array.from({ length: 16 }, (_, i) => rd(L.EXFRM + i)) }))); }

  if ((pc === L.tk_lg || pc === L.tk_lg + 2) && !sdone) {
    sdone = true; xdone = [false, false]; rdone = false; gameOn = true;
    ticks++;
    const snap = {
      state: rd(L.state), players: rd(L.players), fxt: rd(L.fxt), fxmask: rd(L.fxmask), fxteam: pair("fxteam"),
      bi: pair("bi"), bj: pair("bj"), bd: pair("bd"), bq: pair("bq"), bdead: pair("bdead"),
      wx: [w16("wxl", "wxh", 0), w16("wxl", "wxh", 1)], wy: [w16("wyl", "wyh", 0), w16("wyl", "wyh", 1)],
      glr: [pair("glr14"), pair("glr15"), pair("glr10"), pair("glr11")], htop: [w16("htopl", "htoph", 0), w16("htopl", "htoph", 1)], hbot: [w16("hbotl", "hboth", 0), w16("hbotl", "hboth", 1)], hbx: [w16("hbxl", "hbxh", 0), w16("hbxl", "hbxh", 1)],
      fxox: [rd(L.fxox) | (rd(L.fxox + 1) << 8), rd(L.fxox + 2) | (rd(L.fxox + 3) << 8)],
      fxoy: [rd(L.fxoy) | (rd(L.fxoy + 1) << 8), rd(L.fxoy + 2) | (rd(L.fxoy + 3) << 8)],
    };
    rec("S", Buffer.from(JSON.stringify(snap)));
  }
  return false;
});
// every field, as jsbeeb paints it: lines 0..255 of the picture, physical colours
const FW = 328, X0 = 192, Y0 = 64;
const origPaint = v.paint_ext;
v.paint_ext = (...a) => {
  const buf = Buffer.alloc(2 + 264 * FW);
  let cy = 0, cm = 0, wh = 0;
  for (const c of v.ulaPal) { const p = ((c & 0xff) > 127 ? 1 : 0) | (((c >> 8) & 0xff) > 127 ? 2 : 0) | (((c >> 16) & 0xff) > 127 ? 4 : 0); if (p === 6) cy++; if (p === 5) cm++; if (p === 7) wh++; }
  buf[0] = cy && cm && !wh ? 1 : 0;
  buf[1] = rd(L.state);
  let o = 2;
  for (let y = 0; y < 264; y++) {
    const row = (Y0 + 2 * y) * 1024 + X0;
    for (let x = 0; x < FW; x++) {
      const c = fb[row + 2 * x];
      buf[o++] = ((c & 0xff) > 127 ? 1 : 0) | (((c >> 8) & 0xff) > 127 ? 2 : 0) | (((c >> 16) & 0xff) > 127 ? 4 : 0);
    }
  }
  if (gameOn) { if (v.bitmapY !== 624) { oddFrames++; if (oddFrames < 12 || oddFrames % 40 == 0) console.log("odd frame", fieldNo, v.bitmapY, "state", rd(L.state), "vs", rd(L.vsyncs)); } }
  rec("F", buf); fieldNo++; if (process.env.EVLOG) EVLOG.push(`PAINT field ${fieldNo} by ${v.bitmapY} vs${rd(L.vsyncs)}`);
  origPaint(...a);
};
const flush = async () => { for (const b of out) if (!py.stdin.write(b)) await new Promise((r) => py.stdin.once("drain", r)); out = []; };

let seed = Number(seedArg); const rnd = () => (seed = (seed * 1103515245 + 12345) & 0x7fffffff) / 0x7fffffff;
const KEYS = { "1": 49, "2": 50, SPACE: 32, Z: 90, X: 88, COMMA: 188, PERIOD: 190 };
const held = new Map();
const press = (k, n) => { s.keyDown(k); held.set(k, n); };
await s.runFor(5e6); await flush();
const begin = () => { if (mode === "1") press(KEYS["1"], 2); else if (mode === "2") press(KEYS["2"], 2); };
begin();
let vsPrev = rd(L.vsyncs), vs = 0;
const steps = Number(secs) * 20;
for (let t = 0; t < steps; t++) {
  await s.runFor(1e5);
  for (const [k, n] of held) { if (n <= 1) { s.keyUp(k); held.delete(k); } else held.set(k, n - 1); }
  const st = rd(L.state);
  if (mode !== "demo") {
    if (st === 4) {
      if (rnd() < 0.06) press(rnd() < 0.5 ? KEYS.Z : KEYS.X, 2);
      if (mode === "2" && rnd() < 0.06) press(rnd() < 0.5 ? KEYS.COMMA : KEYS.PERIOD, 2);
    }
    if (st === 8 && rnd() < 0.1) press(KEYS.SPACE, 2);
    if (st === 0 && rnd() < 0.1) begin();
  }
  const vv = rd(L.vsyncs); vs += (vv - vsPrev) & 255; vsPrev = vv;
  await flush();
  if (firstWild) break;
}
console.log(JSON.stringify({ secs: Number(secs), mode, fxRuns, fxDrawn, oddFrames, w0DoneBy: `line 128+${maxW0} (W1's wait; W0 commits before 280)`, w1DoneBy: `line 256+${maxW1} (deadline 256+184)`, w1CommitBy: `256+${maxCommit1} (before 256+58)`, vsyncs: vs, expected: Number(secs) * 50, ticks, wild, brk }));
console.log("glint", JSON.stringify(G), "(early/late: characters of margin); LEAD steps entered by character", leadMax, "(normally ~60; 92 leaked)");
if (firstWild) console.log("WILD", firstWild.pc.toString(16), firstWild.hist);
py.stdin.end();
if (process.env.EVLOG) { const [a, b] = process.env.EVLOG.split(':').map(Number); console.log(EVLOG.filter(e => { const m = e.match(/(?:field |^f)(\d+)/); return m && +m[1] >= a && +m[1] <= b; }).join('\n')); }
await done;
