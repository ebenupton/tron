#!/bin/sh
# the narrow build (see README), into narrow/build
set -e
cd "$(dirname "$0")"
mkdir -p build
python3 tools/gen.py > /dev/null
ca65 --cpu 6502 -I src -o build/tron.o src/tron.s
ld65 -C tron.cfg -o build/TRON build/tron.o
ca65 --cpu 6502 -I src -o build/loader.o src/loader.s
ld65 -C loader.cfg -o build/LOADER build/loader.o
