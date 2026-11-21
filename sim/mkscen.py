#!/usr/bin/env python3
"""Write the lockstep scenarios (scen_<name>.txt) from the browser emulator's program library.
Usage: mkscen.py [names...]   (the emulator: $CP1_EMU, default ../../../emulator)"""
import json, os, re, sys
here = os.path.dirname(os.path.abspath(__file__))
EMU = os.environ.get('CP1_EMU', os.path.join(here, '..', '..', '..', 'emulator'))
src = open(os.path.join(EMU, 'js', 'programs.js'), encoding='utf-8').read()
LIB = {e['name']: e for e in json.loads(src[src.index('['):src.rindex(']') + 1])}
MN = dict(HLT=1, ANZ=2, VZG=3, AKO=4, LDA=5, ABS=6, ADD=7, SUB=8, SPU=9, VGL=10, SPB=11, VGR=12, VKL=13, NEG=14, UND=15,
          P1E=16, P1A=17, P2A=18, LIA=19, AIS=20, SIU=21, P3E=22, P4A=23, P5A=24)

def cells(text):                                  # js/ui.js parseProgram
    out, a = [], 0
    for line in re.split(r'\r?\n', text):
        line = re.sub(r'[#;].*$', '', line).strip()
        if not line: continue
        m = re.fullmatch(r'(?:\.ORG|@)\s*(\d{1,3})', line, re.I)
        if m: a = int(m.group(1)); continue
        m = re.fullmatch(r'(\d{3})\s+(?:[A-Za-z][A-Za-z0-9]*\s+)?(\d{2})[.,](\d{1,3})', line) or re.fullmatch(r'(\d{3})\s+(\d{2})(\d{3})', line)
        if m: a = int(m.group(1)); out.append((a, int(m.group(2)) << 8 | int(m.group(3)))); a += 1; continue
        m = re.fullmatch(r'(\d{2})[.,](\d{3})', line)
        if m: out.append((a, int(m.group(1)) << 8 | int(m.group(2)))); a += 1; continue
        m = re.fullmatch(r'([A-Za-z][A-Za-z0-9]{2})(?:\s+(\d{1,3}))?', line)
        if m and m.group(1).upper() in MN: out.append((a, MN[m.group(1).upper()] << 8 | int(m.group(2) or 0))); a += 1; continue
        m = re.fullmatch(r'(?:DATA|\.DB)\s+(\d{1,3})', line, re.I)
        if m: out.append((a, int(m.group(1)))); a += 1; continue
        raise ValueError(line)
    return out

HOLD = 30000                                      # instructions a key is held, and the gap after it
def keys(seq): return ''.join(f'down {k}\nrun {HOLD} 2000\nup {k}\nrun {HOLD} 2000\n' for k in seq.split())
def load(text): return ''.join(f'load {a} {w:04x}\n' for a, w in cells(text))
def prog(name, run=True):                         # load a library program and start it, as loadText does
    e = LIB[name]; c = cells(e['text']); start = e.get('start', c[0][0])
    return load(e['text']) + keys(' '.join(f'{start:03d}') + ' PC' + (' RUN' if run else ''))
BOOT = 'run 200000 2000\n'

S = {}
S['boot'] = 'run 200000 1000\n'
# type a program on the keypad: 000 ako 04.042, 001 anz 02.000, 002 spu 09.002; run it, stop, look at ACC and a cell
S['keys'] = BOOT + keys('0 0 0 PC 0 4 0 4 2 INP 0 2 0 0 0 INP 0 9 0 0 2 INP 0 0 0 PC RUN') + 'run 200000 2000\n' + \
            keys('STP ACC 0 0 1 PC OUT CLR 1 2 STEP STEP CAL CAS') + 'run 100000 2000\n'
S['programs'] = BOOT + prog('FIRST') + 'run 150000 2000\n' + keys('STP') + prog('COUNTER') + 'run 300000 2000\n' + \
                keys('STP') + prog('LIGHTS') + 'run 400000 2000\n' + keys('STP') + prog('MULT') + 'run 300000 2000\n'
S['ports'] = BOOT + prog('ECHO') + 'run 100000 2000\np1 170\nrun 100000 2000\np1 15\nrun 100000 2000\np1 255\nrun 50000 2000\n' + \
             keys('STP') + load('000 p3e 22.000\n001 p2a 18.000\n002 p4a 23.000\n003 p5a 24.000\n004 spu 09.000\n') + \
             keys('0 0 0 PC RUN') + 'p3 129\nrun 100000 2000\np3 60\nrun 100000 2000\n'
S['games'] = BOOT + prog('HANOI') + 'run 1500000 5000\n' + keys('STP') + prog('MOON') + 'run 200000 2000\n' + \
             keys('5 INP') + 'run 300000 2000\n'
S['random'] = BOOT + 'cross 1\n' + prog('L036') + 'run 1000000 5000\n' + 'reset\n' + BOOT + 'cross 0\n' + prog('COUNT10') + 'run 300000 2000\n'

for n in (sys.argv[1:] or S):
    open(os.path.join(here, f'scen_{n}.txt'), 'w').write(S[n]); print(n, S[n].count('\n'), 'lines')
