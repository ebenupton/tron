#!/bin/sh
# Build the disc: tools/gen.py's tiles and map, the 6502, the DFS image.
set -e
cd "$(dirname "$0")"
mkdir -p build
python3 tools/gen.py
ca65 -g --cpu 6502 -I src -o build/tron.o src/tron.s -l build/tron.lst
ld65 -C tron.cfg -o build/TRON build/tron.o -m build/map.txt -Ln build/labels.txt
ca65 -g --cpu 6502 -I src -o build/loader.o src/loader.s
ld65 -C loader.cfg -o build/LOADER build/loader.o -Ln build/loader_labels.txt
# bank 4: gen.py's image with the code and tables that read the map put in;
# the code bank: the explosion's frames, room for the font (LOADER), the code
python3 - <<'P'
b = bytearray(open('build/bank4.bin', 'rb').read())
for f, a in (('build/CODEA', 0xB400), ('build/TABA', 0xBF50)):
    d = open(f, 'rb').read()
    assert all(x == 0 for x in b[a - 0x8000:a - 0x8000 + len(d)]), f
    b[a - 0x8000:a - 0x8000 + len(d)] = d
open('build/BANK4', 'wb').write(b)
e = open('build/expl.bin', 'rb').read()
assert len(e) == 0xF00
open('build/BANKB', 'wb').write(e + bytes(0x300) + open('build/CODEB', 'rb').read())
P
printf '*RUN LOADER\r' > build/BOOT
DISC="!BOOT:build/BOOT LOADER:build/LOADER:1900:1900 TRON:build/TRON:3000:0800 BANK4:build/BANK4:3000 BANKB:build/BANKB:3000"
# the narrow build (narrow/README), for a Model B with one bank of sideways RAM
narrow/build.sh
N=narrow/build
DISC="$DISC LOAD16:$N/LOADER:1900:1900 TRON16:$N/TRON:4400:0E00 BANK16:$N/bank4.bin:3000 EXPL16:$N/expl.bin:3000"
python3 tools/mkdfs.py build build/tron.ssd TRON $DISC
cp build/tron.ssd tron.ssd               # (the disc, checked in)
ls -l build/TRON build/BANKB tron.ssd
