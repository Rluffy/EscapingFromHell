NAME   := EscapingFromHell
ROM    := build/$(NAME).nes
CFG    := cfg/mmc3.cfg
CFLAGS := -t none -O --cpu 6502 -Isrc
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

build/%.s: src/%.c src/nes.h src/boss.h | build
	cc65 $(CFLAGS) -o $@ $<

build/%.o: src/%.s | build
	ca65 --cpu 6502 -o $@ $<

build/%.chr: assets/sprites/%.png tools/png2chr.py | build
	python3 tools/png2chr.py $< $@ --pad 4096

build/overworld.bin: assets/overworld.txt tools/mapconv.py | build
	python3 tools/mapconv.py $< $@

build/chr.o: build/tiles.chr build/player.chr
build/map.o: build/overworld.bin

build:
	mkdir -p build

# Every tests/*.lua must exit 0, each starting without a battery save (Mesen keeps the .sav between runs).
test: $(ROM)
	@grep -q NesController tools/mesen/settings.json 2>/dev/null || echo '{"Nes":{"Port1":{"Type":"NesController"}}}' > tools/mesen/settings.json
	@set -e; for t in tests/*.lua; do \
	  echo "== $$t"; \
	  rm -f tools/mesen/Saves/$(NAME).sav; \
	  timeout 60 $(MESEN) --testRunner $$t $(ROM); \
	done

clean:
	rm -rf build

.PHONY: test clean
.SECONDARY:
