#!/usr/bin/env python3
"""rtl/tones.hex: 32-bit phase increments (at 50 MHz) for the Port 4 tone generator, as the browser emulator:
value v sounds 261.63 Hz * 2^(((v-1) mod 49)/12); 0 and 255 are silent (increment 0)."""
CLK = 50e6
out = []
for v in range(256):
    f = 0 if v in (0, 255) else 261.63 * 2 ** (((v - 1) % 49) / 12)
    out.append('%08x' % round(f * 2**32 / CLK))
open('rtl/tones.hex', 'w').write('\n'.join(out) + '\n')
# the Port 2 tone generators: c d e f g a h c'
print('P2:', ', '.join("32'd%d" % round(f * 2**32 / CLK) for f in (261.63, 293.66, 329.63, 349.23, 392.0, 440.0, 493.88, 523.25)))
