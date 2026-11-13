-- Ghost test (dungeon 2): intro name, bank 1, floating movement, invisible state (not hittable, no contact damage),
-- flicker before it is solid, visible hit/contact, phases 2/3 (swoop, fireball), victory without ability.
-- Addresses: docs/TECH.md "Debug-Adressen".
local M = emu.memType.nesMemory
local held = {}
local function rd(a) return emu.read(a, M) end
local function rd16(a) return rd(a) + 256 * rd(a + 1) end
local function wr(a, v) emu.write(a, v, M) end
local function wr16(a, v) wr(a, v % 256); wr(a + 1, v // 256) end
local STATE, PX, PY, CUR = 0x302, 0x303, 0x305, 0x30A
local HEARTS, INV, VY = 0x30B, 0x30C, 0x30F
local EX, EY, EHP, EFLASH = 0x310, 0x311, 0x314, 0x315
local PHASE, DEAD, INTRO, FBX, FX = 0x318, 0x319, 0x31A, 0x31B, 0x321
local BANK, HIDE = 0x326, 0x327          -- cur_bank; boss_hide: bit 0 untouchable, bit 1 not drawn
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
local function nfb() local n = 0; for i = 0, 2 do if rd(FBX + i) ~= 0 then n = n + 1 end end return n end
local function bar()
  local t = ""
  for c = 20, 29 do t = t .. ({[40] = "F", [41] = "H", [42] = "."})[emu.read(0x2000 + 2 * 32 + c, emu.memType.nesPpuMemory)] end
  return t
end
-- player (facing right) at the ghost's left side, sword box over its body; safe = no contact damage
local function align(safe)
  wr16(PX, math.max(16, rd(EX) - 14)); wr(PY, math.min(rd(EY) + 8, FLOOR_Y)); wr(VY, 0)
  if safe then wr(HEARTS, 3); wr(INV, 99) end
end
-- swing at the ghost (waits until it is touchable); returns the hp afterwards. The swing may miss a vanishing ghost: retry.
local function strike()
  local hp = rd(EHP)
  for _ = 1, 8 do
    wait_until(function() return rd(HIDE) & 1 == 0 and rd(FX) == 0 and rd(EFLASH) == 0 end, 600)
    held = {b = true}
    for _ = 1, 3 do align(true); frames(1) end
    held = {}
    for _ = 1, 20 do align(true); frames(1) end
    if rd(EHP) ~= hp then break end
  end
  return rd(EHP)
end
-- max sprites on one scanline from the OAM copy (hidden = y 0xFF)
local function max_line()
  local cnt, m = {}, 0
  for i = 0, 63 do
    local y = rd(0x200 + 4 * i)
    if y < 0xEF then
      for l = y + 1, y + 8 do cnt[l] = (cnt[l] or 0) + 1; m = math.max(m, cnt[l]) end
    end
  end
  return m
end
-- watch the fight for n frames with the player parked and safe; returns stats
local function watch(n)
  local s = {minx = 255, maxx = 0, miny = 255, maxy = 0, maxdx = 0, gone = false, fb = false, line = 0, oob = false}
  local px = rd(EX)
  for _ = 1, n do
    frames(1)
    wr(HEARTS, 3); wr(INV, 99); wr16(0x303, 30); wr(PY, FLOOR_Y)
    local x, y, h = rd(EX), rd(EY), rd(HIDE)
    s.minx = math.min(s.minx, x); s.maxx = math.max(s.maxx, x)
    s.miny = math.min(s.miny, y); s.maxy = math.max(s.maxy, y)
    if rd(FX) == 0 then s.maxdx = math.max(s.maxdx, math.abs(x - px)) end
    px = x
    if x < 16 or x > 224 or y < 28 or y > 168 then s.oob = true end
    if h == 3 then s.gone = true; check(rd(0x200 + 24) == 0xFF and rd(0x200 + 64) == 0xFF, "invisible: no ghost sprite drawn") end
    if nfb() > 0 then s.fb = true end
    s.line = math.max(s.line, max_line())
  end
  return s
end

co = coroutine.create(function()
  frames(30); held = {start = true}; frames(3); held = {}; frames(20); held = {start = true}; frames(3); held = {}; frames(60)   -- boot menu: Start = NEW GAME (CONTINUE with a save), second Start skips the intro
  check(rd(STATE) == 2, "boot reaches overworld")
  wr16(0x308, 1)                          -- dungeon 1 cleared: gate 2 open
  wr16(PX, 144); wr(PY, 48)               -- door of dungeon 2
  frames(30)
  hold({a = true}, 3)
  frames(20)
  check(rd(STATE) == 3 and rd(CUR) == 2, "dungeon 2 entered, state=" .. rd(STATE))
  check(rd(BANK) == 1 and rd(0x8000) ~= 0, "ghost bank 1 mapped, cur_bank=" .. rd(BANK))

  -- intro: "GHOST" (G H O S T = tiles 29 39 31 38 34 at row 10, columns 13..17), full bar, frozen
  check(rd(INTRO) > 0, "intro running")
  check(rd(EHP) == 12 and rd(PHASE) == 1 and bar() == "FFFFFFFFFF", "ghost: 12 hp, phase 1, full bar")
  local name = {}
  for c = 13, 17 do name[#name + 1] = emu.read(0x2000 + 10 * 32 + c, emu.memType.nesPpuMemory) end
  check(table.concat(name, ",") == "29,39,31,38,34", "name GHOST on screen: " .. table.concat(name, ","))
  local x0, y0 = rd(EX), rd(EY)
  frames(10)
  check(rd(EX) == x0 and rd(EY) == y0, "ghost frozen during the intro")
  check(wait_until(function() return rd(INTRO) == 0 end, 100), "intro ends")
  hold({right = true}, 2)                 -- face right

  -- phase 1: floats around (x and y change, stays inside the arena), vanishes at times, max 8 sprites per scanline
  local s = watch(300)
  check(s.maxx - s.minx > 10 and s.maxy - s.miny > 30, "ghost floats in x and y, x " .. s.minx .. ".." .. s.maxx .. " y " .. s.miny .. ".." .. s.maxy)
  check(not s.oob, "ghost stays inside the arena")
  check(s.maxdx <= 1, "phase 1 drifts slowly (max dx " .. s.maxdx .. ")")
  check(s.line <= 8, "max 8 sprites per scanline, got " .. s.line)

  -- invisible: no contact damage, no sword damage, nothing drawn
  check(wait_until(function() return rd(HIDE) == 3 end, 300), "ghost becomes invisible")
  wr(EX, 120); wr(EY, 120)
  wr(HEARTS, 3); wr(INV, 0); wr(EFLASH, 0)
  for _ = 1, 8 do wr16(PX, rd(EX)); wr(PY, rd(EY) + 4); frames(1) end      -- player right inside the ghost
  check(rd(HIDE) == 3, "still invisible (test timing)")
  check(rd(HEARTS) == 3 and rd(INV) == 0, "no contact damage while invisible, hearts=" .. rd(HEARTS))
  local hp = rd(EHP)
  held = {b = true}
  for _ = 1, 3 do align(false); frames(1) end
  held = {}
  for _ = 1, 6 do align(false); frames(1) end
  check(rd(HIDE) == 3, "still invisible (test timing)")
  check(rd(EHP) == hp, "sword does not hurt the invisible ghost, hp=" .. rd(EHP))

  -- re-appearing: flickers (drawn at times but untouchable, hide = 1) before it is solid (hide = 0)
  local flicker = false
  check(wait_until(function() if rd(HIDE) == 1 then flicker = true end return rd(HIDE) == 0 end, 200), "ghost becomes solid again")
  check(flicker, "flickered (hide = 1) before it became solid")
  frames(2)
  check(rd(0x200 + 24) ~= 0xFF or rd(HIDE) ~= 0, "solid ghost is drawn")

  -- solid: contact costs exactly one heart, a hit costs one hp
  wr(EFLASH, 0); wr(HEARTS, 3); wr(INV, 0)
  for _ = 1, 3 do wr16(PX, rd(EX)); wr(PY, rd(EY) + 4); frames(1) end
  check(rd(HEARTS) == 2 and rd(INV) > 80, "contact with the solid ghost costs a heart, hearts=" .. rd(HEARTS))
  wait_until(function() return rd(INV) == 0 end, 130)
  hp = strike()
  check(hp == 11, "visible hit = exactly 1 hp, hp=" .. hp)
  check(bar() == "FFFFFFFFFH", "bar after one hit (ceil(11*20/12)=19 steps), bar=" .. bar())

  -- phase 2 at hp <= 8 (70 % of 12), phase 3 at hp <= 6 (50 %)
  wr(EHP, 9); wr(EFLASH, 0)
  check(strike() == 8 and rd(PHASE) == 2, "hp 8 -> phase 2, phase=" .. rd(PHASE))
  frames(2)
  check(rd(EHP) ~= 0 and bar() == "FFFFFFF...", "bar 14 steps at hp 8, bar=" .. bar())
  check(wait_until(function() return emu.read(0x3F16, emu.memType.nesPpuMemory) == 0x33 end, 80), "phase 2 palette")
  check(wait_until(function() return rd(FX) == 0 end, 60), "phase effect ends")
  s = watch(400)                          -- swoop: 3 px/frame steps that the slow drift never has
  check(s.maxdx >= 2, "phase 2 swoops (max dx " .. s.maxdx .. ")")
  check(not s.oob and s.line <= 8, "phase 2 inside arena, sprites per line " .. s.line)

  wr(EHP, 7); wr(EFLASH, 0)
  check(strike() == 6 and rd(PHASE) == 3, "hp 6 -> phase 3, phase=" .. rd(PHASE))
  frames(2)
  check(bar() == "FFFFF.....", "bar half at hp 6, bar=" .. bar())
  check(wait_until(function() return emu.read(0x3F16, emu.memType.nesPpuMemory) == 0x16 end, 80), "phase 3 palette")
  check(wait_until(function() return rd(FX) == 0 end, 60), "phase effect ends")
  s = watch(600)
  check(s.fb, "phase 3 fires a fireball")
  check(s.gone, "phase 3 still vanishes")
  check(not s.oob and s.line <= 8, "phase 3 inside arena, sprites per line " .. s.line)

  -- victory: hp 1 + hit -> dead, back in the overworld, dungeon 2 cleared, no ability
  wr(EHP, 1); wr(EFLASH, 0)
  check(strike() == 0 and rd(DEAD) == 1, "hp 0 -> boss_dead")
  check(wait_until(function() return rd(STATE) == 2 end, 300), "victory returns to the overworld")
  check(rd16(0x308) == 3, "dungeon 2 cleared, mask=" .. rd16(0x308))
  check(rd(0x322) == 0, "ghost grants no ability, abilities=" .. rd(0x322))
  check(rd16(PX) == 144 and rd(PY) == 48 and rd(CUR) == 0, "back at entrance 2")

  print("ghost test OK")
  emu.stop(0)
end)

emu.addEventCallback(function() emu.setInput(held, 0, 0) end, emu.eventType.inputPolled)
emu.addEventCallback(function()
  if coroutine.status(co) == "dead" then return end
  local ok, err = coroutine.resume(co)
  if not ok then print("ERROR: " .. tostring(err)); emu.stop(1) end
end, emu.eventType.endFrame)
