-- Bone hound test (dungeon 3): intro name, bank 2, patrol, charge telegraph + fast charge, bite, dizzy window,
-- jumping over a charge, hits and phases (speed, double charge, leap), victory with Double jump.
-- Addresses: docs/TECH.md "Debug-Adressen".
local M = emu.memType.nesMemory
local held = {}
local function rd(a) return emu.read(a, M) end
local function rd16(a) return rd(a) + 256 * rd(a + 1) end
local function wr(a, v) emu.write(a, v, M) end
local function wr16(a, v) wr(a, v % 256); wr(a + 1, v // 256) end
local function ppu(a) return emu.read(a, emu.memType.nesPpuMemory) end
local STATE, PX, PY, CUR = 0x302, 0x303, 0x305, 0x30A
local HEARTS, INV, VY = 0x30B, 0x30C, 0x30F
local EX, EY, EW, EHP, EFLASH, EDIR = 0x310, 0x311, 0x312, 0x314, 0x315, 0x316
local PHASE, DEAD, INTRO, FX = 0x318, 0x319, 0x31A, 0x321
local ABIL, VICT = 0x322, 0x325
local BANK, IAIR = 0x326, 0x328            -- cur_bank; hound state
local RUN, TELE, CHARGE, REST, BITE, LEAP = 0, 1, 2, 3, 4, 5
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
local function bar()
  local t = ""
  for c = 20, 29 do t = t .. ({[40] = "F", [41] = "H", [42] = "."})[ppu(0x2000 + 2 * 32 + c)] end
  return t
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
local maxline = 0
-- player (facing right) left of the hound, sword box over its body, no damage
local function align()
  wr16(PX, math.max(16, rd(EX) - 14)); wr(PY, FLOOR_Y); wr(VY, 0); wr(HEARTS, 3); wr(INV, 99)
end
-- one sword hit at the hound (the hound is always touchable); returns hp afterwards
local function strike()
  local hp = rd(EHP)
  for _ = 1, 8 do
    wait_until(function() return rd(FX) == 0 and rd(EFLASH) == 0 end, 300)
    held = {b = true}
    for _ = 1, 3 do align(); frames(1); maxline = math.max(maxline, max_line()) end
    held = {}
    for _ = 1, 20 do align(); frames(1); maxline = math.max(maxline, max_line()) end
    if rd(EHP) ~= hp then break end
  end
  return rd(EHP)
end
-- Watch n frames with the player parked at the left wall and safe. Returns the run-length encoded state list
-- and stats: max |dx| per state, min y, leaps seen, x out of the arena.
local function watch(n)
  local s = {runs = {}, mx = {}, miny = 255, oob = false, line = 0}
  local px, last = rd(EX), nil
  for _ = 1, n do
    frames(1)
    wr(HEARTS, 3); wr(INV, 99); wr16(PX, 30); wr(PY, FLOOR_Y)
    local x, y, st = rd(EX), rd(EY), rd(IAIR)
    if rd(FX) == 0 then s.mx[st] = math.max(s.mx[st] or 0, math.abs(x - px)) end
    px = x
    s.miny = math.min(s.miny, y)
    if x < 16 or x > 216 or y > FLOOR_Y then s.oob = true end
    if st ~= last then s.runs[#s.runs + 1] = {st = st, n = 0, x = x}; last = st end
    local r = s.runs[#s.runs]; r.n = r.n + 1
    if st == REST then check(x == r.x, "no movement while dizzy") end
    s.line = math.max(s.line, max_line())
  end
  return s
end
local function longest(s, st)
  local m = 0
  for _, r in ipairs(s.runs) do if r.st == st then m = math.max(m, r.n) end end
  return m
end
local function seen(s, st) return longest(s, st) > 0 end

co = coroutine.create(function()
  frames(30); held = {start = true}; frames(3); held = {}; frames(20); held = {start = true}; frames(3); held = {}; frames(60)   -- boot menu: Start = NEW GAME (CONTINUE with a save), second Start skips the intro
  check(rd(STATE) == 2, "boot reaches overworld")
  wr16(0x308, 3)                          -- dungeons 1 and 2 cleared: gate 3 open
  wr16(PX, 240); wr(PY, 80)               -- door of dungeon 3
  frames(30)
  hold({a = true}, 3)
  frames(20)
  check(rd(STATE) == 3 and rd(CUR) == 3, "dungeon 3 entered, state=" .. rd(STATE))
  check(rd(BANK) == 2 and rd(0x8000) ~= 0, "hound bank 2 mapped, cur_bank=" .. rd(BANK))

  -- intro: "BONE HOUND" (B O N E _ H O U N D = tiles 43 31 28 30 0 39 31 27 28 26 at row 10, columns 11..20)
  check(rd(INTRO) > 0, "intro running")
  check(rd(EHP) == 12 and rd(PHASE) == 1 and bar() == "FFFFFFFFFF", "hound: 12 hp, phase 1, full bar")
  check(rd(EW) == 24, "hound is 24 px wide, w=" .. rd(EW))
  local name = {}
  for c = 11, 20 do name[#name + 1] = ppu(0x2000 + 10 * 32 + c) end
  check(table.concat(name, ",") == "43,31,28,30,0,39,31,27,28,26", "name BONE HOUND on screen: " .. table.concat(name, ","))
  local x0 = rd(EX)
  frames(10)
  check(rd(EX) == x0 and rd(IAIR) == RUN, "hound frozen during the intro")
  check(wait_until(function() return rd(INTRO) == 0 end, 100), "intro ends")
  hold({right = true}, 2)                 -- face right

  -- phase 1: patrols and turns at the walls (<= 1 px/frame), telegraph ~30 frames, charge 4 px/frame, dizzy ~40 frames
  local s = watch(700)
  check(not s.oob and s.miny == FLOOR_Y, "phase 1 stays on the floor inside the arena")
  check(s.mx[RUN] == 1, "patrol speed 1 px/frame, got " .. tostring(s.mx[RUN]))
  check(seen(s, TELE) and longest(s, TELE) >= 28 and longest(s, TELE) <= 32, "charge telegraph ~30 frames, got " .. longest(s, TELE))
  check(s.mx[TELE] == 0, "no movement during the telegraph")
  check(s.mx[CHARGE] == 4, "charge 4 px/frame (run 1), got " .. tostring(s.mx[CHARGE]))
  check(longest(s, REST) >= 38 and longest(s, REST) <= 42, "dizzy ~40 frames, got " .. longest(s, REST))
  check(s.line <= 7, "max 7 sprites per scanline (limit 8), got " .. s.line)

  -- bite: player close (<= 28 px) and on the ground while patrolling -> lunge at 3 px/frame
  for _, st in ipairs({CHARGE, REST, RUN}) do     -- after a charge the next attack is 480 frames away
    check(wait_until(function() wr(HEARTS, 3); wr(INV, 99); wr16(PX, 30); wr(PY, FLOOR_Y); return rd(IAIR) == st end, 400), "state " .. st)
  end
  wr(EX, 200)                          -- the patrol turns back 56 px short of the player (it never walks into him)
  local near = 255
  for _ = 1, 150 do
    wr(HEARTS, 3); wr(INV, 99); wr16(PX, 100); wr(PY, FLOOR_Y); frames(1)
    if rd(IAIR) == RUN then near = math.min(near, math.abs(rd(EX) - 100)) end
  end
  check(near >= 54 and near <= 58, "patrol keeps ~56 px from the player, nearest " .. near)
  wr(EX, 120)
  local bx
  check(wait_until(function()          -- player 22 px left of the hound (bite cooldown <= 60 frames)
    wr(HEARTS, 3); wr(INV, 99); wr16(PX, rd(EX) - 22); wr(PY, FLOOR_Y)
    bx = rd(EX); return rd(IAIR) == BITE
  end, 80), "bites when the player is close")
  frames(3)
  check(math.abs(rd(EX) - bx) >= 5, "bite lunges forward")
  check(wait_until(function() wr(INV, 99); return rd(IAIR) == REST end, 20), "bite ends with a short rest")

  -- scripted charge: player at the right wall, hound pinned at x 40 until it starts the telegraph
  local function charge_test(jump)
    wr(HEARTS, 3); wr(INV, 0); wr16(PX, 200); wr(PY, FLOOR_Y); wr(VY, 0)
    local jumped, lost = false, false
    check(wait_until(function() if rd(IAIR) == RUN then wr(EX, 40); wr(INV, 0) end return rd(IAIR) == TELE end, 700), "attack starts")
    check(wait_until(function() return rd(IAIR) == CHARGE end, 60), "charge follows the telegraph")
    check(wait_until(function()
      local dist = (rd16(PX) + 8) - (rd(EX) + 12)
      if jump and not jumped and dist <= 70 then jumped = 0 end
      held = (jumped and jumped < 20) and {a = true} or {}          -- hold A: a tap is only a short hop
      if jumped then jumped = jumped + 1 end
      if rd(INV) > 0 then lost = true end
      return rd(IAIR) ~= CHARGE
    end, 80), "charge ends at the wall")
    held = {}
    return lost
  end
  wait_until(function() return rd(IAIR) == RUN end, 100)
  check(not charge_test(true) and rd(HEARTS) == 3, "one jump clears the charge: hearts " .. rd(HEARTS))
  wait_until(function() return rd(IAIR) == RUN end, 100)
  wr(PY, FLOOR_Y)
  check(charge_test(false) and rd(HEARTS) == 2, "standing in the charge costs a heart: hearts " .. rd(HEARTS))

  -- dizzy window: hit while resting, exactly 1 hp, bar ceil(11*20/12) = 19 steps; contact while resting costs a heart
  wr(INV, 0); wr(EFLASH, 0)
  check(wait_until(function() return rd(IAIR) == REST end, 200), "dizzy after the charge")
  wr(HEARTS, 3); wr(INV, 0)
  wr16(PX, rd(EX)); wr(PY, FLOOR_Y); frames(2)
  check(rd(HEARTS) == 2, "contact with the dizzy hound costs a heart, hearts=" .. rd(HEARTS))
  wait_until(function() return rd(INV) == 0 end, 130)
  local hp = strike()
  check(hp == 11, "hit = exactly 1 hp, hp=" .. hp)
  check(bar() == "FFFFFFFFFH", "bar after one hit, bar=" .. bar())
  check(maxline <= 7, "sword swing + overlap: max 7 sprites per scanline, got " .. maxline)

  -- phase 2 at hp <= 8 (70 % of 12), phase 3 at hp <= 6 (50 %)
  wr(EHP, 9); wr(EFLASH, 0)
  check(strike() == 8 and rd(PHASE) == 2, "hp 8 -> phase 2, phase=" .. rd(PHASE))
  frames(2)
  check(bar() == "FFFFFFF...", "bar 14 steps at hp 8, bar=" .. bar())
  check(rd(0x201 + 24) == 0x40 + 6, "phase 2 look (boss tile 6, id 0x46)")
  check(wait_until(function() return ppu(0x3F16) == 0x37 end, 80), "phase 2 palette")
  check(wait_until(function() return rd(FX) == 0 end, 60), "phase effect ends")
  s = watch(1000)                         -- an attack every ~500 frames
  check(s.mx[CHARGE] == 5, "phase 2 charges faster (5 px/frame), got " .. tostring(s.mx[CHARGE]))
  check(longest(s, TELE) >= 22 and longest(s, TELE) <= 26, "phase 2 telegraph ~24 frames, got " .. longest(s, TELE))
  check(not s.oob and s.line <= 7, "phase 2 inside the arena, sprites per line " .. s.line)

  wr(EHP, 7); wr(EFLASH, 0)
  check(strike() == 6 and rd(PHASE) == 3, "hp 6 -> phase 3, phase=" .. rd(PHASE))
  frames(2)
  check(bar() == "FFFFF.....", "bar half at hp 6, bar=" .. bar())
  check(rd(0x201 + 24) == 0x40 + 12, "phase 3 look (boss tile 12, id 0x4C)")
  check(wait_until(function() return ppu(0x3F16) == 0x16 end, 80), "phase 3 palette")
  check(wait_until(function() return rd(FX) == 0 end, 60), "phase effect ends")
  s = watch(3000)                         -- an attack every ~600 frames, a leap in half of them
  local double, leaped = false, false
  for i = 1, #s.runs - 2 do
    if s.runs[i].st == CHARGE and s.runs[i + 1].st == TELE and s.runs[i + 2].st == CHARGE and s.runs[i + 1].n <= 12 then double = true end
  end
  check(double, "phase 3 charges twice in a row (CHARGE, short TELE, CHARGE)")
  check(seen(s, LEAP) and s.miny <= FLOOR_Y - 30, "phase 3 leaps, min y " .. s.miny)
  check(s.mx[RUN] == 2, "phase 3 runs faster (2 px/frame), got " .. tostring(s.mx[RUN]))
  check(not s.oob and s.line <= 7, "phase 3 inside the arena, sprites per line " .. s.line)

  -- victory: hp 1 + hit -> dead, text names the ability, overworld, bit 2 set, Double jump granted and saved
  wr(EHP, 1); wr(EFLASH, 0)
  check(strike() == 0 and rd(DEAD) == 1, "hp 0 -> boss_dead")
  frames(3)
  check(rd(VICT) > 0 and ppu(0x2000 + 10 * 32 + 12) == 32 and ppu(0x2000 + 10 * 32 + 18) == 36, "'VICTORY' on screen")
  local got = {}
  for c = 8, 22 do got[#got + 1] = ppu(0x2000 + 13 * 32 + c) end
  check(table.concat(got, ",") == "29,31,34,0,26,31,27,43,44,30,0,45,27,14,15", "'GOT DOUBLE JUMP' on screen: " .. table.concat(got, ","))
  check(wait_until(function() return rd(STATE) == 2 end, 300), "victory returns to the overworld")
  check(rd16(0x308) == 7, "dungeon 3 cleared (bit 2), mask=" .. rd16(0x308))
  check(rd(ABIL) == 2, "Double jump granted, abilities=" .. rd(ABIL))
  check(rd16(PX) == 240 and rd(PY) == 80 and rd(CUR) == 0, "back at entrance 3")
  check(rd(0x6000) == 0x45 and rd(0x6001) == 0x48 and rd(0x6002) == 1 and rd(0x6003) == 7 and rd(0x6004) == 0
        and rd(0x6005) == 2 and rd(0x6006) == 0x97, "autosave valid")

  print("hound test OK")
  emu.stop(0)
end)

emu.addEventCallback(function() emu.setInput(held, 0, 0) end, emu.eventType.inputPolled)
emu.addEventCallback(function()
  if coroutine.status(co) == "dead" then return end
  local ok, err = coroutine.resume(co)
  if not ok then print("ERROR: " .. tostring(err)); emu.stop(1) end
end, emu.eventType.endFrame)
