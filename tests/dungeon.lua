-- Dungeon arena test: entry, jump/platforms, pause, contact damage + invulnerability, restart, sword, Select.
-- Addresses: docs/TECH.md "Debug-Adressen".
local M = emu.memType.nesMemory
local held = {}
local function rd(a) return emu.read(a, M) end
local function rd16(a) return rd(a) + 256 * rd(a + 1) end
local function wr(a, v) emu.write(a, v, M) end
local function wr16(a, v) wr(a, v % 256); wr(a + 1, v // 256) end
local STATE, PX, PY, CUR = 0x302, 0x303, 0x305, 0x30A
local HEARTS, INV, GROUND, SWORD, PAUSED = 0x30B, 0x30C, 0x30D, 0x30E, 0x317
local EX, EY, EHP, EFLASH, EDIR = 0x310, 0x311, 0x314, 0x315, 0x316
local FLOOR_Y = 176                      -- player y when standing on the floor

local co
local function frames(n) for _ = 1, n do coroutine.yield() end end
local function hold(keys, n) held = keys; frames(n); held = {} end
local function press(keys) hold(keys, 3); frames(5) end
local function check(cond, msg)
  if not cond then print("FAIL: " .. msg); emu.stop(1); coroutine.yield() end
end
local function wait_until(f, max)
  for _ = 1, max do if f() then return true end frames(1) end
  return f()
end
local function setup(px, ex)               -- player on the floor facing right, enemy alive at ex walking left
  wr16(PX, px); wr(PY, FLOOR_Y); wr(EX, ex); wr(EY, 176); wr(EHP, 5); wr(EFLASH, 0); wr(EDIR, 255)
  wr(HEARTS, 3); wr(INV, 0)
end

co = coroutine.create(function()
  frames(60)
  check(rd(STATE) == 2, "boot reaches overworld")
  wr16(PX, 48); wr(PY, 80)                -- door of dungeon 1 (col 3, row 5)
  frames(30)
  press({a = true})
  frames(20)                              -- building the arena takes a few frames
  check(rd(STATE) == 3 and rd(CUR) == 1, "dungeon 1 entered, state=" .. rd(STATE) .. " px=" .. rd16(PX) .. " py=" .. rd(PY))
  frames(5)
  check(rd(HEARTS) == 3 and rd(INV) == 0, "3 hearts on entry, hearts=" .. rd(HEARTS))
  check(rd(GROUND) == 1 and rd(PY) == FLOOR_Y, "standing on the floor, y=" .. rd(PY))
  check(rd(EHP) == 5, "enemy hp 5, hp=" .. rd(EHP))

  -- jump (enemy parked dead so nothing interferes): y goes up, then back to the floor
  wr(EHP, 0)
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

  -- pause: Start freezes the enemy, Start again resumes
  setup(48, 200)
  frames(3)
  press({start = true})
  check(rd(PAUSED) == 1, "Start pauses")
  local x0 = rd(EX)
  frames(10)
  check(rd(EX) == x0, "enemy frozen while paused")
  press({start = true})
  check(rd(PAUSED) == 0, "Start resumes")
  frames(10)
  check(rd(EX) < x0, "enemy walks again after resume")

  -- contact costs exactly one heart, then invulnerability protects against the next touch
  setup(48, 70)
  check(wait_until(function() return rd(HEARTS) < 3 end, 40), "contact never hurt")
  check(rd(HEARTS) == 2 and rd(INV) > 80, "one heart lost, hearts=" .. rd(HEARTS) .. " inv=" .. rd(INV))
  for _ = 1, 30 do wr16(PX, rd(EX)); frames(1) end
  check(rd(HEARTS) == 2, "no second loss while invulnerable, hearts=" .. rd(HEARTS))
  wr(EX, 200)
  check(wait_until(function() return rd(INV) == 0 end, 120), "invulnerability ends")
  wr16(PX, rd(EX)); frames(2)
  check(rd(HEARTS) == 1, "second hit, hearts=" .. rd(HEARTS))
  wr(EX, 200)
  wait_until(function() return rd(INV) == 0 end, 120)
  wr16(PX, rd(EX)); frames(2)
  check(rd(HEARTS) == 3 and rd(INV) == 0 and rd(EHP) == 5 and rd16(PX) == 48 and rd(PY) == FLOOR_Y,
        "restart after 0 hearts, hearts=" .. rd(HEARTS) .. " px=" .. rd16(PX))

  -- sword: one swing = one hit, 5 hits kill the dummy, which then vanishes and is harmless
  press({right = true})                   -- face right
  for i = 1, 5 do
    setup(98, 120); wr(EHP, 6 - i)       -- keep the hp from the previous swing
    frames(1)
    hold({b = true}, 3)
    check(rd(SWORD) > 0, "sword active, swing " .. i)
    frames(15)
    check(rd(EHP) == 5 - i, "one swing = one hit, hp=" .. rd(EHP) .. " swing " .. i)
    frames(10)
  end
  check(rd(EHP) == 0, "dummy dead")
  frames(15)
  check(rd(0x200 + 24) == 0xFF, "dummy sprites hidden")
  local ex = rd(EX)
  wr16(PX, ex); wr(PY, FLOOR_Y); wr(HEARTS, 3); frames(10)
  check(rd(HEARTS) == 3 and rd(EX) == ex, "dead dummy is harmless and still")

  -- B does not leave; Select returns to the overworld and restores the overworld sprites
  press({b = true})
  check(rd(STATE) == 3, "B does not leave the dungeon")
  press({select = true})
  frames(5)
  check(rd(STATE) == 2 and rd(CUR) == 0, "Select returns to the overworld")
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
