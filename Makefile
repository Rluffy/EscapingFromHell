NAME   := EscapingFromHell
ROM    := build/$(NAME).nes
CFG    := cfg/mmc3.cfg
CFLAGS := -t none -O --cpu 6502 -Isrc
# Mesen: portable mode via tools/mesen/settings.json (skips the first-run wizard);
# invariant globalization avoids a std::bad_cast crash at startup.
MESEN  := env DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1 xvfb-run -a tools/mesen/Mesen

CSRC := $(wildcard src/*.c)
ASRC := $(wildcard src/*.s)
OBJ  := $(patsubst src/%.c,build/%.o,$(CSRC)) $(patsubst src/%.s,build/%.o,$(ASRC))

$(ROM): $(OBJ) $(CFG)
	ld65 -C $(CFG) -m build/$(NAME).map -Ln build/$(NAME).lbl -o $@ $(OBJ) none.lib

build/%.o: build/%.s
	ca65 --cpu 6502 -o $@ $<

build/%.s: src/%.c src/nes.h | build
	cc65 $(CFLAGS) -o $@ $<

build/%.o: src/%.s | build
	ca65 --cpu 6502 -o $@ $<

build:
	mkdir -p build

# Every tests/*.lua must exit 0.
test: $(ROM)
	@[ -f tools/mesen/settings.json ] || echo '{}' > tools/mesen/settings.json
	@set -e; for t in tests/*.lua; do \
	  echo "== $$t"; \
	  timeout 60 $(MESEN) --testRunner $$t $(ROM); \
	done

clean:
	rm -rf build

.PHONY: test clean
.SECONDARY:
