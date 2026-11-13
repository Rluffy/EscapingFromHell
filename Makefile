NAME   := EscapingFromHell
ROM    := build/$(NAME).nes
CFG    := cfg/mmc3.cfg
CFLAGS := -t none -O -Cl --cpu 6502 -Isrc
# Mesen: portable mode via tools/mesen/settings.json (skips the first-run wizard, enables controller 1);
# invariant globalization avoids a std::bad_cast crash at startup.
MESEN  := env DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1 xvfb-run -a tools/mesen/Mesen

CSRC := $(wildcard src/*.c)
ASRC := $(wildcard src/*.s)
OBJ  := $(patsubst src/%.c,build/%.o,$(CSRC)) $(patsubst src/%.s,build/%.o,$(ASRC))

$(ROM): $(OBJ) $(CFG)
	ld65 -C $(CFG) -m build/$(NAME).map -Ln build/$(NAME).lbl -o $@ $(OBJ) none.lib

build/%.o: build/%.s
	ca65 --cpu 6502 -o $@ $<

build/%.s: src/%.c src/nes.h src/boss.h src/meta.h src/arena.h src/ui.h | build
	cc65 $(CFLAGS) -o $@ $<

build/%.o: src/%.s | build
	ca65 --cpu 6502 -Ibuild -o $@ $<

# CHR sheets are padded to their slot in the CHR-ROM (docs/TECH.md "CHR-Layout"): 2 KB for tiles/anim/common, 4 KB per boss.
PAD_tiles := 2048
PAD_anim_a := 2048
PAD_anim_b := 2048
PAD_common := 2048
build/%.chr: assets/sprites/%.png tools/png2chr.py | build
	python3 tools/png2chr.py $< $@ --pad $(or $(PAD_$*),4096)

build/overworld.bin: assets/overworld.txt tools/mapconv.py | build
	python3 tools/mapconv.py $< $@

# Songs: assets/songs.txt -> build/songs.inc (included by src/music.s), docs/TECH.md "Musik (v1.1)".
build/songs.inc: assets/songs.txt tools/music.py | build
	python3 tools/music.py asm $< $@

build/music.o: build/songs.inc
build/chr.o: $(patsubst assets/sprites/%.png,build/%.chr,$(wildcard assets/sprites/*.png))
build/map.o: build/overworld.bin

build:
	mkdir -p build

# Every tests/*.lua must exit 0, each starting without a battery save (Mesen keeps the .sav between runs).
test: $(ROM)
	@grep -q NesController tools/mesen/settings.json 2>/dev/null || echo '{"Nes":{"Port1":{"Type":"NesController"}}}' > tools/mesen/settings.json
	@set -e; for t in tests/*.lua; do \
	  echo "== $$t"; \
	  rm -f tools/mesen/Saves/$(NAME).sav; \
	  timeout 180 $(MESEN) --testRunner $$t $(ROM); \
	done

clean:
	rm -rf build

.PHONY: test clean
.SECONDARY:
