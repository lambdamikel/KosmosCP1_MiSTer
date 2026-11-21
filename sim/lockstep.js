// Lockstep test, browser-emulator side (js/cp1.js): the same checkpoints as tb_lockstep.cpp.
const m = new KosmosCP1(cp1RomFromBase64(CP1_ROM_B64));
let steps = 0, h = 2166136261;
const fnv = (x, v) => Math.imul((x ^ (v & 255)) >>> 0, 16777619) >>> 0;
const hex = v => v.toString(16).padStart(8, '0');
function power() { m.reset(); m.pid.reset(); m.ext.reset(); m.p2 = 0xff; }
function step() {
  m.step(); steps++;
  for (const v of [m.a, m.pc & 255, m.pc >> 8, m.psw, m.dbf, m.f1, m.t, m.tf ? 1 : 0, m.timerIrq ? 1 : 0, m.tcntIrqEn ? 1 : 0,
                   m.timerRunning ? 1 : 0, m.inIrq ? 1 : 0, m.untilCount, m.p1, m.p2, m.bus]) h = fnv(h, v);
}
function check() {
  let hr = 2166136261, hp = 2166136261, he = 2166136261;
  for (let i = 0; i < 128; i++) hr = fnv(hr, m.ram[i]);
  for (let i = 0; i < 256; i++) { hp = fnv(hp, m.pid.ram[i]); he = fnv(he, m.ext.ram[i]); }
  for (const c of [m.pid, m.ext]) for (const v of [c.cmd, c.pa, c.pb, c.pc]) hp = fnv(hp, v);
  console.log(`chk ${steps} ${hex(h)} ${hex(hr)} ${hex(hp)} ${hex(he)}`);
}
power();
for (const line of SCENARIO.split('\n')) {
  const w = line.trim().split(/\s+/), op = w[0];
  if (op === 'run') { const n = +w[1], every = +(w[2] || 0); for (let i = 0; i < n; i++) { step(); if (every && steps % every === 0) check(); } }
  else if (op === 'down') m.keyDown(w[1]);
  else if (op === 'up') m.keyUp(w[1]);
  else if (op === 'p1') m.port1In = +w[1];
  else if (op === 'p3') m.port3In = +w[1];
  else if (op === 'cross') m.p2ToP1 = +w[1] ? [2, 3, 1, 0, 6, 7, 5, 4] : null;
  else if (op === 'load') { let a = +w[1]; for (const x of w.slice(2)) m.writeCell(a++, parseInt(x, 16)); }
  else if (op === 'reset') power();
  else if (op === 'check') check();
  else if (op === 'dump') console.log(`dump cells ${[0,1,2].map(n => m.readCell(n).toString(16).padStart(4,'0')).join(' ')} akku ${m.ram[0x36]},${m.ram[0x37]} vmpc ${m.ram[0x38]} p2 ${m.pid.pb}`);
}
check();
