#!/usr/bin/env python3
"""Generate rtl/text.hex: the 80x30 text layer of the CP1 picture, 12-bit {shift, colour, char}.
The positions match the shapes in rtl/video.v (text cell = 8x16 pixels).  rtl/font.hex (misc-fixed
8x16) comes from the Microtronic core's tools/mklayout.py."""
W, H = 80, 30
BLACK, LIGHT, MID, WHITE, YELLOW = 0, 1, 2, 3, 4
cells = [[(0, 0, 32)] * W for _ in range(H)]
def put(col, row, s, colour, shift=0):
    for i, ch in enumerate(s): cells[row][col + i] = (shift, colour, ord(ch))
def at(x, row, s, colour):
    """Centre s on pixel x (a multiple of 4): an odd start lands on a half cell and is drawn shifted."""
    start = x - 4 * len(s)
    assert start % 4 == 0, (x, s)
    put(start // 8, row, s, colour, shift=1 if start % 8 else 0)

# I/O module: LEDs (Port 2) at x = 92 + 32i, switches (Port 1) at x = 372 + 32i
put(4, 1, 'kosmos', LIGHT)
at(204, 1, 'Port 2  Ausgang/Output', LIGHT)
at(484, 1, 'Port 1  Eingang/Input', LIGHT)
for i in range(8):
    at(92 + 32 * i, 6, str(i + 1), MID)
    at(372 + 32 * i, 6, str(i + 1), MID)
# the plate beside the display (x 404..563, y 172..211)
at(484, 11, 'kosmos', WHITE)
at(484, 12, 'CP1  Computer-Praxis', LIGHT)
# keys: labels at the key centres (rtl/video.v key())
for i in range(10): at(64 + 36 * i, 17, str(i), BLACK)
for j, k in enumerate(('STEP', 'STP', 'RUN', 'CAL')): at(100 + 80 * j, 19, k, BLACK)
for j, k in enumerate(('CLR', 'ACC', 'CAS')): at(140 + 80 * j, 21, k, BLACK)
for j, k in enumerate(('PC', 'OUT', 'INP')): at(140 + 80 * j, 23, k, BLACK)
for r, row in enumerate(('789', '456', '123')):
    for c, k in enumerate(row): at(472 + 44 * c, 17 + 2 * r, k, BLACK)
at(496, 23, '0', BLACK)
# the PC keys
put(3, 26, 'PC keys: 0-9   Enter/I INP   O OUT   P PC   A ACC   R RUN   H or . STP', LIGHT)
put(3, 27, '         T STEP   Del/X CLR   L CAL   S CAS   F1-F8 Port 1 switches', LIGHT)
put(3, 28, '         Shift+1-8 contact clips   Esc switch off and on', LIGHT)
put(3, 29, 'F12 menu: load a .CP1 program, speed, random-number wiring, Port 2 tones', MID)

flat = ['%03x' % ((sh << 11) | (col << 8) | ch) for row in cells for sh, col, ch in row]
flat += ['020'] * (4096 - len(flat))
open('rtl/text.hex', 'w').write('\n'.join(flat) + '\n')
print('text', W * H, 'cells')
