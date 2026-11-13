-- Boss test (dungeon 1, Imp): intro, movement, fireballs, sword damage, phases, defeat, fireball hit.
-- Addresses: docs/TECH.md "Debug-Adressen".
local M = emu.memType.nesMemory
local held = {}
local function rd(a) return emu.read(a, M) end
local function rd16(a) return rd(a) + 256 * rd(a + 1) end
local function wr(a, v) emu.write(a, v, M) end
local function wr16(a, v) wr(a, v % 256); wr(a + 1, v // 256) end
local STATE, PX, PY, CUR = 0x302, 0x303, 0x305, 0x30A
local HEARTS, INV = 0x30B, 0x30C
local EX, EY, EHP, EFLASH = 0x310, 0x311, 0x314, 0x315
local PHASE, DEAD, INTRO, FBX, FBY, FX = 0x318, 0x319, 0x31A, 0x31B, 0x31E, 0x321
local BANK = 0x326                       -- cur_bank: PRG bank at $8000 (10 = UI bank in menu/overworld/ending)
local FLOOR_Y = 176

local co
local function frames(n) for _ = 1, n do coroutine.yield() end end
local function hold(keys, n) held = keys; frames(n); held = {} end
local function check(cond, msg)
  if not cond then print("FAIL: " .. msg); emu.stop(1); coroutine.yield() end
end
local function wait_until(f, max)
  for _ = 1, max do if f() then return true end frames(1) end
  return f()
end
local function fireballs() local n = 0; for i = 0, 2 do if rd(FBX + i) ~= 0 then n = n + 1 end end return n end
-- player next to the boss on the floor, facing right (boss to the right)
local function duel(hp)
  wr(EX, 120); wr(EY, FLOOR_Y); wr(EHP, hp); wr(EFLASH, 0)
  wr16(PX, 98); wr(PY, FLOOR_Y); wr(HEARTS, 3); wr(INV, 0)
end
-- boss hp bar: 10 BG tiles at row 2, columns 20..29 (40 full, 41 half, 42 empty), as a string like "FFFFFFFFFH"
local function bar()
  local t = ""
  for c = 20, 29 do t = t .. ({[40] = "F", [41] = "H", [42] = "."})[emu.read(0x2000 + 2 * 32 + c, emu.memType.nesPpuMemory)] end
  return t
end
local function swing() hold({b = true}, 3); frames(25) end   -- 25: cooldown over, boss hit-flash over

co = coroutine.create(function()
  frames(30); held = {start = true}; frames(3); held = {}; frames(20); held = {start = true}; frames(3); held = {}; frames(60)   -- boot menu: Start = NEW GAME (CONTINUE with a save), second Start skips the intro
  check(rd(STATE) == 2, "boot reaches overworld")
  check(rd(BANK) == 10 and rd(0x8000) ~= 0, "UI bank (10) mapped in the overworld, no boss bank")
  wr16(PX, 48); wr(PY, 80)                -- door of dungeon 1
  frames(30)
  hold({a = true}, 3)
  frames(20)
  check(rd(STATE) == 3 and rd(CUR) == 1, "dungeon 1 entered")
  check(rd(BANK) == 0 and rd(0x8000) ~= 0, "imp bank 0 mapped, cur_bank=" .. rd(BANK))

  -- intro: boss name drawn, everything frozen, then the fight starts and the name is erased
  check(rd(INTRO) > 0 and rd(INTRO) <= 75, "intro running, intro=" .. rd(INTRO))
  check(rd(EHP) == 10 and rd(PHASE) == 1 and rd(DEAD) == 0, "imp: 10 hp, phase 1, alive")
  check(bar() == "FFFFFFFFFF", "full hp bar during the intro, bar=" .. bar())
  check(emu.read(0x2000 + 10 * 32 + 14, emu.memType.nesPpuMemory) == 13, "name 'I' on screen")
  local x0, y0, px0 = rd(EX), rd(EY), rd16(PX)
  hold({right = true}, 10)
  check(rd(EX) == x0 and rd(EY) == y0 and rd16(PX) == px0, "boss and player frozen during intro")
  check(wait_until(function() return rd(INTRO) == 0 end, 100), "intro ends")
  frames(2)
  check(emu.read(0x2000 + 10 * 32 + 14, emu.memType.nesPpuMemory) == 0, "name erased")

  -- the Imp hops around and spits a fireball
  local moved, fb = false, false
  wr16(PX, 30)                            -- far left; keep the player healthy
  for _ = 1, 400 do
    frames(1)
    wr(HEARTS, 3); wr(INV, 99)
    if rd(EX) ~= 160 or rd(EY) ~= FLOOR_Y - 16 then moved = true end
    if fireballs() > 0 then fb = true end
  end
  check(moved, "imp moves")
  check(fb, "imp spits a fireball")

  -- sword: one swing = exactly one hp (boss put next to the player each time, the AI keeps running)
  hold({right = true}, 2)                 -- face right
  for hp = 9, 8, -1 do
    duel(hp + 1); wr(EX, 112)
    frames(1)
    hold({b = true}, 3)
    frames(25)
    check(rd(EHP) == hp, "one swing = one hp, hp=" .. rd(EHP) .. " want " .. hp)
    if hp == 9 then check(bar() == "FFFFFFFFF.", "one hit = two half steps at max hp 10, bar=" .. bar()) end
  end
  -- the hit boss is pushed 16 px away from the player (112 -> 128) and its flash blocks contact damage
  check(rd(EX) >= 128, "boss knocked back, x=" .. rd(EX))
  duel(5); wr(EX, 100); wr(EFLASH, 20); frames(1)
  check(rd(HEARTS) == 3, "no contact damage during the boss hit-flash")

  -- phase thresholds from max hp 10: phase 2 at hp <= 7, phase 3 at hp <= 5
  duel(8); frames(1); wr(EX, 112); hold({b = true}, 3); frames(2)
  check(rd(EHP) == 7 and rd(PHASE) == 2 and rd(FX) > 0, "hp 7 -> phase 2 with effect, phase=" .. rd(PHASE))
  check(bar() == "FFFFFFF...", "phase change frame: bar updated too (ceil(7*20/10)=14 steps), bar=" .. bar())
  check(emu.read(0x3F16, emu.memType.nesPpuMemory) == 0x27, "phase 2 palette applied")
  local ex = rd(EX)
  frames(10)
  check(rd(EX) == ex, "boss frozen during phase change")
  frames(40)
  check(rd(FX) == 0, "phase effect ends")
  duel(6); frames(1); wr(EX, 112); hold({b = true}, 3); frames(2)
  check(rd(EHP) == 5 and rd(PHASE) == 3, "hp 5 -> phase 3, phase=" .. rd(PHASE))
  check(bar() == "FFFFF.....", "half hp = half bar, bar=" .. bar())
  frames(45)
  check(emu.read(0x3F16, emu.memType.nesPpuMemory) == 0x16, "phase 3 palette applied")

  -- a fireball costs a heart and starts invulnerability
  wr(EX, 224); wr(EY, 0); wr(EFLASH, 255)   -- park the boss away: no contact damage possible
  wr16(PX, 100); wr(PY, FLOOR_Y); wr(HEARTS, 3); wr(INV, 0)
  wr(FBX, 108); wr(FBY, 180)              -- fireball on top of the player
  frames(2)
  check(rd(HEARTS) == 2 and rd(INV) > 80, "fireball hit costs a heart, hearts=" .. rd(HEARTS))
  check(rd(FBX) == 0, "fireball consumed")

  -- defeat: hp 1 -> one hit -> dead flag, boss gone, harmless
  wr(EFLASH, 0)
  duel(1); frames(1); wr(EX, 112); hold({b = true}, 3); frames(3)
  check(rd(EHP) == 0 and rd(DEAD) == 1, "hp 0 -> boss_dead, dead=" .. rd(DEAD))
  frames(30)
  check(bar() == "..........", "empty bar at 0 hp, bar=" .. bar())
  check(rd(0x200 + 24) == 0xFF and fireballs() == 0, "boss and fireballs gone")
  local ex = rd(EX)
  wr16(PX, ex); wr(PY, FLOOR_Y); wr(HEARTS, 3); wr(INV, 0); frames(10)
  check(rd(HEARTS) == 3 and rd(STATE) == 3, "defeated boss is harmless, arena stays")

  check(wait_until(function() return rd(STATE) == 2 end, 200), "victory sequence ends in the overworld (see progress.lua)")

  print("boss test OK")
  emu.stop(0)
end)

emu.addEventCallback(function() emu.setInput(held, 0, 0) end, emu.eventType.inputPolled)
emu.addEventCallback(function()
  if coroutine.status(co) == "dead" then return end
  local ok, err = coroutine.resume(co)
  if not ok then print("ERROR: " .. tostring(err)); emu.stop(1) end
end, emu.eventType.endFrame)
