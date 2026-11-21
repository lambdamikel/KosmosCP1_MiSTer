#!/usr/bin/env python3
"""Export the browser emulator's program library (js/programs.js) as .CP1 files for the MiSTer core:
dist/games/KosmosCP1/{Guide,Manual}/NAME.CP1.  Every cell is written as "NNN mnemonic OO.DDD", the form
the core's loader reads; the comments are kept, and a header line says where to start and what the
program needs (menu settings, clips).  The emulator: $CP1_EMU, default ../../emulator."""
import json, os, re, sys
here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(here, '..', 'sim'))
EMU = os.environ.get('CP1_EMU', os.path.join(here, '..', '..', '..', 'emulator'))
os.environ['CP1_EMU'] = EMU
import importlib.util
spec = importlib.util.spec_from_file_location('mkscen', os.path.join(here, '..', 'sim', 'mkscen.py'))
src = open(spec.origin).read().split('\nHOLD = ')[0]          # only the library and the parser, not the scenarios
ns = {'__file__': spec.origin}; exec(src, ns)
LIB, cells, MN = ns['LIB'], ns['cells'], ns['MN']
NAME = {v: k.lower() for k, v in MN.items()}
FOLDER = {'Examples from the guide': 'Guide', 'From the Kosmos manual': 'Manual'}
out = os.path.join(here, '..', 'dist', 'games', 'KosmosCP1')
n = 0
for name, e in LIB.items():
    c = cells(e['text']); start = e.get('start', c[0][0])
    head = [l for l in e['text'].splitlines() if l.startswith('#')]
    needs = []
    if e.get('cross'): needs.append('Random-number wiring = On')
    if e.get('p2tones'): needs.append('Tone generators on Port 2 = On')
    clips = e.get('clips')
    lines = head[:1] + [f'# Start: {start:03d} PC RUN' + (f'.  MiSTer menu: {"; ".join(needs)}' if needs else '')]
    if clips: lines.append('# Contact clips on Port 1 line(s) ' + ', '.join(str(b + 1) for b in range(8) if clips >> b & 1)
                           + ': hold Shift + the line number to press one.')
    lines += head[1:] + ['']
    for a, w in c:
        op, x = w >> 8, w & 255
        lines.append(f'{a:03d} {NAME.get(op, "   ")} {op:02d}.{x:03d}' if op else f'{a:03d}     00.{x:03d}')
    d = os.path.join(out, FOLDER[e['group']]); os.makedirs(d, exist_ok=True)
    open(os.path.join(d, name + '.CP1'), 'w', newline='\r\n').write('\n'.join(lines) + '\n')
    n += 1
print(n, 'programs ->', os.path.normpath(out))
