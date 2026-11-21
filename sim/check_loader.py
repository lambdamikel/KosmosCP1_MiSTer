#!/usr/bin/env python3
"""Every exported .CP1 through the hardware loader must give the cells the emulator's parser gives for the original text."""
import glob, os, subprocess, sys
here = os.path.dirname(os.path.abspath(__file__))
os.environ.setdefault('CP1_EMU', os.path.join(here, '..', '..', '..', 'emulator'))
ns = {'__file__': os.path.join(here, 'mkscen.py')}; exec(open(ns['__file__']).read().split('\nHOLD = ')[0], ns)
ok = bad = 0
for f in sorted(glob.glob(os.path.join(here, '..', 'dist', 'games', 'KosmosCP1', '*', '*.CP1'))):
    name = os.path.basename(f)[:-4]
    want = ns['cells'](ns['LIB'][name]['text'])
    out = subprocess.run([os.path.join(here, 'objl', 'tb_loader'), f], capture_output=True, text=True).stdout
    got = [(int(a), int(w, 16)) for a, w in (l.split() for l in out.splitlines())]
    if got == want: ok += 1
    else: bad += 1; print(name, 'DIFFERENT', len(got), len(want), next(((g, w) for g, w in zip(got, want) if g != w), None))
print(f'{ok} programs identical, {bad} different')
