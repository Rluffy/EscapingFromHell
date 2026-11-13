-- Ability hints (v1.1): the victory screen of dungeons 1/3/5/7/9 shows "GOT <ABILITY>" and, one row lower, how to use it (and lasts 60 frames
-- longer); the pause overview (PAUSE, one line per ability active in THIS dungeon, quit hint) is drawn over the arena and removed again
-- tile for tile; all PPU writes happen in vblank. Cheat mode (every gate open, nothing earned). Addresses: docs/TECH.md "Debug-Adressen".
local M = emu.memType.nesMemory
local held = {}
local function rd(a) return emu.read(a, M) end
local function rd16(a) return rd(a) + 256 * rd(a + 1) end
local function wr(a, v) emu.write(a, v, M) end
local function wr16(a, v) wr(a, v % 256); wr(a + 1, v // 256) end
local function ppu(a) return emu.read(a, emu.memType.nesPpuMemory) end
local STATE, PX, PY, CUR, HEARTS, INV = 0x302, 0x303, 0x305, 0x30A, 0x30B, 0x30C
local EX, EY, EHP, EFLASH, PAUSED, INTRO, VICT, AACT = 0x310, 0x311, 0x314, 0x315, 0x317, 0x31A, 0x325, 0x343
local FT = { A = 37, B = 43, C = 33, D = 26, E = 30, F = 48, G = 29, H = 39, I = 13, J = 45, K = 46, L = 44, M = 14, N = 28, O = 31, P = 15,
             Q = 49, R = 35, S = 38, T = 34, U = 27, V = 32, W = 47, Y = 36, ["+"] = 241, [" "] = 0 }

-- vblank discipline (as in budget.lua): VRAM writes while rendering is on must fall into scanlines 241..260
local viol, nw = 0, 0
local function in_vblank_or_off()
  local st = emu.getState()
  if not (st["ppu.mask.backgroundEnabled"] or st["ppu.mask.spritesEnabled"]) then return true end
  local l = st["ppu.scanline"]
  return l >= 241 and l <= 260
end
emu.addMemoryCallback(function() if not in_vblank_or_off() then viol = viol + 1 end end, emu.callbackType.write, 0x2006)
emu.addMemoryCallback(function() nw = nw + 1; if nw % 4 == 0 and not in_vblank_or_off() then viol = viol + 1 end end, emu.callbackType.write, 0x2007)

local co
local function frames(n) for _ = 1, n do coroutine.yield() end end
local function check(cond, msg)
  if not cond then print("FAIL: " .. msg); emu.stop(1); coroutine.yield() end
end
local function press(keys) held = keys; frames(3); held = {}; frames(5) end
local function wait_until(f, max)
  for _ = 1, max do if f() then return true end frames(1) end
  return f()
end
local function enter(n)
  wr16(PX, (6 * n - 3) * 16); wr(PY, n % 2 == 1 and 80 or 48); frames(30)
  press({a = true})
  check(wait_until(function() return rd(STATE) == 3 and rd(CUR) == n end, 200), "dungeon " .. n .. " entered")
end
local function safe() wr(HEARTS, 3); wr(INV, 99) end
local function fight(n)                                   -- intro over, hero safe
  enter(n)
  check(wait_until(function() safe(); return rd(INTRO) == 0 end, 200), "dungeon " .. n .. " intro over")
  frames(3)
end
local function leave() press({start = true}); press({select = true}); check(wait_until(function() return rd(STATE) == 2 end, 40), "back in the overworld") end

local function row(r) local t = {}; for c = 0, 31 do t[c] = ppu(0x2000 + r * 32 + c) end return t end
local function tiles(s, c0, r, what)                       -- the tiles of text s start at column c0 of row r (a "+" is tile 241)
  for i = 1, #s do
    local got, want = ppu(0x2000 + r * 32 + c0 + i - 1), FT[s:sub(i, i)]
    check(got == want, string.format("%s: '%s' row %d col %d is tile %d, want %d", what, s, r, c0 + i - 1, got, want))
  end
end
local function snap() local t = {}; for i = 0, 959 do t[i] = ppu(0x2000 + i) end return t end
local function same(a, what)
  for i = 0, 959 do check(ppu(0x2000 + i) == a[i], string.format("%s: nametable byte row %d col %d changed (%d -> %d)", what, i // 32, i % 32, a[i], ppu(0x2000 + i))) end
end
local function blank(r, what) for c = 7, 24 do check(ppu(0x2000 + r * 32 + c) == 0, what .. ": row " .. r .. " col " .. c .. " blank") end end

local GOT = { [1] = {"GOT DASH", "PRESS SELECT"}, [3] = {"GOT DOUBLE JUMP", "A IN THE AIR"}, [5] = {"GOT FIREBALL", "UP + B"},
              [7] = {"GOT SHIELD", "HOLD DOWN"}, [9] = {"GOT SWORD WAVE", "B AT FULL HEARTS"} }
local LINES = { "SELECT DASH", "A      AIR JUMP", "UP+B   FIREBALL", "DOWN   SHIELD", "B      WAVE" }

local function victory(n)
  fight(n)
  wr(EX, 224); wr(EY, 0); wr(EFLASH, 255)
  wr(EHP, 0)
  check(wait_until(function() safe(); return rd(VICT) > 0 end, 5), "dungeon " .. n .. ": victory starts")
  frames(4)
  local g = GOT[n]
  check(rd(VICT) >= 170 and rd(VICT) <= 176, string.format("dungeon %d: new ability, victory screen 180 frames, left %d", n, rd(VICT)))
  tiles("VICTORY", 12, 10, "dungeon " .. n)
  if g then
    tiles(g[1], (32 - #g[1]) // 2, 13, "dungeon " .. n .. " GOT")
    tiles(g[2], (32 - #g[2]) // 2, 15, "dungeon " .. n .. " hint")
  else
    blank(13, "dungeon " .. n .. " no GOT"); blank(15, "dungeon " .. n .. " no hint")
  end
  check(wait_until(function() return rd(STATE) == 2 end, 300), "dungeon " .. n .. ": victory ends")
end

co = coroutine.create(function()
  frames(30); held = {down = true}; frames(3); held = {}; frames(5)
  press({start = true}); frames(20); press({start = true}); frames(60)       -- CHEAT, Start skips the intro
  check(rd(STATE) == 2, "cheat started")

  for _, n in ipairs({1, 3, 5, 7, 9}) do victory(n) end
  -- an old level (no new ability): the short victory without hint
  fight(1); wr(EX, 224); wr(EY, 0); wr(EFLASH, 255); wr(EHP, 0); frames(8)
  check(rd(VICT) > 100 and rd(VICT) <= 116, "no new ability: victory screen 120 frames, left " .. rd(VICT))
  tiles("VICTORY", 12, 10, "again"); blank(13, "again no GOT"); blank(15, "again no hint")
  check(wait_until(function() return rd(STATE) == 2 end, 300), "victory ends")

  -- pause in dungeon 1: no ability, PAUSE + quit hint only; unpausing restores every nametable byte
  fight(1)
  wr(EX, 224); wr(EY, 0); wr(EFLASH, 255)
  local before = snap()
  press({start = true})
  check(rd(PAUSED) == 1 and rd(AACT) == 0, "dungeon 1 paused, no ability")
  frames(10)
  tiles("PAUSE", 13, 5, "d1"); tiles("START+SELECT QUIT", 7, 13, "d1")
  for r = 7, 11 do blank(r, "d1 no ability line") end
  for c = 0, 31 do for _, r in ipairs({0, 1, 2, 3, 4, 6, 12, 14, 24}) do check(ppu(0x2000 + r * 32 + c) == before[r * 32 + c], "d1: row " .. r .. " untouched") end end
  press({start = true})
  check(rd(PAUSED) == 0, "dungeon 1 unpaused")
  frames(10); same(before, "d1 unpaused")
  press({start = true}); frames(1); press({start = true}); frames(12)     -- toggled quickly: still the exact original
  same(before, "d1 quick toggle")
  leave()

  -- pause in dungeon 10: all five ability lines; the same while the intro runs: nothing is drawn
  enter(10)
  local intro0 = snap()
  press({start = true}); frames(10)
  check(rd(PAUSED) == 1 and rd(INTRO) > 0, "paused during the intro")
  same(intro0, "pause in the intro draws nothing")
  press({start = true})
  check(wait_until(function() safe(); return rd(INTRO) == 0 end, 200), "dungeon 10 intro over"); frames(3)
  wr(EX, 224); wr(EY, 0); wr(EFLASH, 255)
  before = snap()
  press({start = true}); frames(10)
  check(rd(PAUSED) == 1 and rd(AACT) == 31, "dungeon 10 paused with all abilities")
  tiles("PAUSE", 13, 5, "d10"); tiles("START+SELECT QUIT", 7, 13, "d10")
  for k = 1, 5 do tiles(LINES[k], 8, 6 + k, "d10 line " .. k) end
  press({start = true}); frames(10)
  same(before, "d10 unpaused")
  check(viol == 0, "PPU writes outside vblank: " .. viol)
  print("hints test OK")
  emu.stop(0)
end)

emu.addEventCallback(function() emu.setInput(held, 0, 0) end, emu.eventType.inputPolled)
emu.addEventCallback(function()
  if coroutine.status(co) == "dead" then return end
  local ok, err = coroutine.resume(co)
  if not ok then print("ERROR: " .. tostring(err)); emu.stop(1) end
end, emu.eventType.endFrame)
