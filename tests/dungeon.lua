-- Dungeon arena test (dungeon 1, the Imp; it is pinned by writing its position / clearing its fireballs every frame): entry, jump/platforms,
-- pause, contact damage + invulnerability, restart, sword hits + hp bar, victory without leaving by B.
-- Addresses: docs/TECH.md "Debug-Adressen".
local M = emu.memType.nesMemory
local held = {}
local function rd(a) return emu.read(a, M) end
local function rd16(a) return rd(a) + 256 * rd(a + 1) end
local function wr(a, v) emu.write(a, v, M) end
local function wr16(a, v) wr(a, v % 256); wr(a + 1, v // 256) end
local STATE, PX, PY, CUR = 0x302, 0x303, 0x305, 0x30A
local HEARTS, INV, GROUND, SWORD, PAUSED = 0x30B, 0x30C, 0x30D, 0x30E, 0x317
local EX, EY, EHP, EFLASH = 0x310, 0x311, 0x314, 0x315
local IAIR, INTRO, FBX = 0x328, 0x31A, 0x31B
local FLOOR_Y = 176                      -- player y when standing on the floor

local co
local pin = nil                            -- {x, y}: the imp is held there every frame (nil = it moves freely); its fireballs are cleared
local function frames(n)
  for _ = 1, n do
    if pin then wr(EX, pin[1]); wr(EY, pin[2]) end
    for i = 0, 2 do wr(FBX + i, 0) end
    coroutine.yield()
  end
end
local function hold(keys, n) held = keys; frames(n); held = {} end
local function press(keys) hold(keys, 3); frames(5) end
local function check(cond, msg)
  if not cond then print("FAIL: " .. msg); emu.stop(1); coroutine.yield() end
end
local function wait_until(f, max)
  for _ = 1, max do if f() then return true end frames(1) end
  return f()
end
local function setup(px, ex)               -- player on the floor facing right, the imp at ex on the floor, full hp
  pin = {ex, 176}
  wr16(PX, px); wr(PY, FLOOR_Y); wr(EX, ex); wr(EY, 176); wr(EHP, 10); wr(EFLASH, 0)
  wr(HEARTS, 3); wr(INV, 0)
end

co = coroutine.create(function()
  frames(30); held = {start = true}; frames(3); held = {}; frames(20); held = {start = true}; frames(3); held = {}; frames(60)   -- boot menu: Start = NEW GAME (CONTINUE with a save), second Start skips the intro
  check(rd(STATE) == 2, "boot reaches overworld")
  wr16(PX, 48); wr(PY, 80)                -- door of dungeon 1 (the gate is open from the start)
  frames(30)
  press({a = true})
  frames(20)                              -- building the arena takes a few frames
  check(rd(STATE) == 3 and rd(CUR) == 1, "dungeon 1 entered, state=" .. rd(STATE) .. " px=" .. rd16(PX) .. " py=" .. rd(PY))
  check(wait_until(function() return rd(INTRO) == 0 end, 100), "intro ends")
  check(rd(HEARTS) == 3 and rd(INV) == 0, "3 hearts on entry, hearts=" .. rd(HEARTS))
  check(rd(GROUND) == 1 and rd(PY) == FLOOR_Y, "standing on the floor, y=" .. rd(PY))
  check(rd(EHP) == 10, "imp hp 10, hp=" .. rd(EHP))

  -- jump (imp parked at the ceiling so nothing interferes): y goes up, then back to the floor
  pin = {200, 0}
  wr16(PX, 84)                            -- the gap between platforms 1 and 3
  frames(2)
  local miny, air = 255, false
  held = {a = true}
  for _ = 1, 40 do
    frames(1)
    miny = math.min(miny, rd(PY))
    if rd(GROUND) == 0 then air = true end
  end
  held = {}
  frames(40)
  check(air and miny < FLOOR_Y - 40, "jump rises, min y=" .. miny)
  check(rd(GROUND) == 1 and rd(PY) == FLOOR_Y, "lands on the floor, y=" .. rd(PY))

  -- one-way platform: x=40 is under platform 1 (top y=152); the jump passes through and lands on top
  wr16(PX, 40)
  frames(2)
  hold({a = true}, 40)
  frames(30)
  check(rd(GROUND) == 1 and rd(PY) == 136, "lands on platform from below, y=" .. rd(PY))
  hold({right = true}, 40)                -- walks off the right edge (platform ends at x=80)
  frames(40)
  check(rd(PY) == FLOOR_Y and rd(GROUND) == 1, "falls from platform edge to the floor, y=" .. rd(PY))
  hold({left = true}, 200)                -- cannot leave the screen: wall at x=16
  check(rd16(PX) == 16, "left wall stops the player, x=" .. rd16(PX))

  -- pause: Start freezes the imp in mid-hop, Start again resumes the hop
  pin = nil
  wr16(PX, 48); wr(PY, FLOOR_Y); wr(HEARTS, 3); wr(INV, 99); wr(EX, 200); wr(EY, 176); wr(EFLASH, 0)
  check(wait_until(function() wr(INV, 99); return rd(EY) < 170 end, 400), "the imp hops")
  hold({start = true}, 2)
  check(rd(PAUSED) == 1, "Start pauses")
  local x0, y0 = rd(EX), rd(EY)
  frames(10)
  check(rd(EX) == x0 and rd(EY) == y0, "imp frozen while paused")
  hold({start = true}, 2)
  check(rd(PAUSED) == 0, "Start resumes")
  frames(6)
  check(rd(EY) ~= y0, "imp hops again after resume")
  pin = {200, 0}

  -- contact costs exactly one heart, then invulnerability protects against the next touch
  setup(48, 56)
  check(wait_until(function() return rd(HEARTS) < 3 end, 40), "contact never hurt")
  check(rd(HEARTS) == 2 and rd(INV) > 80, "one heart lost, hearts=" .. rd(HEARTS) .. " inv=" .. rd(INV))
  for _ = 1, 30 do wr16(PX, rd(EX)); frames(1) end
  check(rd(HEARTS) == 2, "no second loss while invulnerable, hearts=" .. rd(HEARTS))
  pin = {200, 176}
  check(wait_until(function() return rd(INV) == 0 end, 120), "invulnerability ends")
  -- the imp keeps hopping while pinned: stand on it until it touches
  local function touched(h) return wait_until(function() if rd(HEARTS) == h then return true end wr16(PX, rd(EX)); wr(PY, FLOOR_Y); return false end, 200) end
  check(touched(1), "second hit, hearts=" .. rd(HEARTS))
  wait_until(function() return rd(INV) == 0 end, 120)
  touched(3)
  frames(2)
  check(rd(HEARTS) == 3 and rd(INV) == 0 and rd(EHP) == 10 and rd16(PX) == 48 and rd(PY) == FLOOR_Y,
        "restart after 0 hearts, hearts=" .. rd(HEARTS) .. " px=" .. rd16(PX))

  -- sword: one swing = one hit (1 hp, 12 frames of hit protection), the bar follows; 1 hp left + a swing = victory
  press({right = true})                   -- face right
  for i = 1, 2 do
    setup(98, 120)
    frames(1)
    hold({b = true}, 3)
    check(rd(SWORD) > 0, "sword active, swing " .. i)
    frames(15)
    check(rd(EHP) == 9, "one swing = one hit, hp=" .. rd(EHP) .. " swing " .. i)
    if i == 1 then   -- generic hp bar: 9/10 hp = 18 of 20 half steps (tiles 40 full, 42 empty, row 2 columns 20..29)
      local t = {}
      for c = 20, 29 do t[#t + 1] = emu.read(0x2000 + 2 * 32 + c, emu.memType.nesPpuMemory) end
      check(table.concat(t, ",") == "40,40,40,40,40,40,40,40,40,42", "hp bar after one hit: " .. table.concat(t, ","))
    end
    frames(10)
  end
  setup(98, 120); wr(EHP, 1)
  frames(1)
  hold({b = true}, 3)
  frames(15)
  check(rd(EHP) == 0, "imp dead")
  frames(15)
  check(rd(0x200 + 24) == 0xFF, "imp sprites hidden")
  local ex = rd(EX)
  wr16(PX, ex); wr(PY, FLOOR_Y); wr(HEARTS, 3); frames(10)
  check(rd(HEARTS) == 3 and rd(EX) == ex, "dead imp is harmless and still")

  -- imp dead = victory: B does not leave, then the sequence returns to the overworld, dungeon 1 cleared
  check(rd(0x325) > 0, "victory running")
  press({b = true})
  check(rd(STATE) == 3, "B does not leave the dungeon")
  check(wait_until(function() return rd(STATE) == 2 end, 200), "victory returns to the overworld")
  check(rd(CUR) == 0 and rd16(0x308) == 1 and rd(0x322) == 1, "dungeon 1 cleared (mask 1), dash granted, mask=" .. rd16(0x308))
  check(rd16(PX) == 48 and rd(PY) == 80, "back at entrance 1")
  check(rd(0x201) == 0 and rd(0x202) == 0 and rd(0x200 + 24) == 0xFF, "overworld sprites restored")

  print("dungeon test OK")
  emu.stop(0)
end)

emu.addEventCallback(function() emu.setInput(held, 0, 0) end, emu.eventType.inputPolled)
emu.addEventCallback(function()
  if coroutine.status(co) == "dead" then return end
  local ok, err = coroutine.resume(co)
  if not ok then print("ERROR: " .. tostring(err)); emu.stop(1) end
end, emu.eventType.endFrame)
