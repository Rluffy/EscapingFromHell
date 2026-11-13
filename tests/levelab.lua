-- Abilities by level (v1.1): in dungeon n exactly the abilities of demons 1..n-1 work (Dash after 1, Double jump after 3, Fireball after 5,
-- Shield after 7, Sword wave after 9), in normal and cheat mode alike, whatever the save / the progress record (`abilities` $0322) holds.
-- Checked through the active mask `ab_act` ($0343) and by trying every ability in the game (Select, A in the air, Up + B, Down, B at full hearts).
-- Addresses: docs/TECH.md "Debug-Adressen".
local M = emu.memType.nesMemory
local held = {}
local function rd(a) return emu.read(a, M) end
local function wr(a, v) if a >= 0x6000 and a < 0x8000 then emu.write(a - 0x6000, v, emu.memType.nesSaveRam) else emu.write(a, v, M) end end
local function wr16(a, v) wr(a, v % 256); wr(a + 1, v // 256) end
local STATE, PX, PY, CUR, HEARTS, INV, VY = 0x302, 0x303, 0x305, 0x30A, 0x30B, 0x30C, 0x30F
local EX, EY, EFLASH, INTRO = 0x310, 0x311, 0x315, 0x31A
local ABIL, DASH, PFX, PFCD, SHIELD, AACT, CHEAT, MASK = 0x322, 0x323, 0x329, 0x32B, 0x331, 0x343, 0x334, 0x308
local SAVE = 0x6000
local FLOOR_Y = 176

local co
local function frames(n) for _ = 1, n do coroutine.yield() end end
local function check(cond, msg)
  if not cond then print("FAIL: " .. msg); emu.stop(1); coroutine.yield() end
end
local function signed(v) return v >= 128 and v - 256 or v end
local function press(keys) held = keys; frames(3); held = {}; frames(5) end
local function wait_until(f, max)
  for _ = 1, max do if f() then return true end frames(1) end
  return f()
end
local function safe()                                  -- the boss is parked away and harmless, the player cannot be hurt
  wr(EX, 224); wr(EY, 0); wr(EFLASH, 255); wr(HEARTS, 3); wr(INV, 99)
end
local function stand()
  safe(); wr16(PX, 100); wr(PY, FLOOR_Y); wr(VY, 0); wr(PFX, 0); wr(PFCD, 0)
end
local function run(keys, n) held = keys; for _ = 1, n do safe(); frames(1) end held = {} end

-- Tries all five abilities; returns the string of those that work, e.g. "DJF--" (Dash, Double jump, Fireball, Shield, Wave)
local function probe()
  local r = ""
  stand(); frames(3); wr(0x324, 0)
  run({select = true}, 2); r = r .. (rd(DASH) > 0 and "D" or "-")
  run({}, 20)
  stand(); frames(3)
  run({a = true}, 4); run({}, 14)                         -- a short jump, then (near the apex or falling) A again in the air
  run({a = true}, 1)
  r = r .. (signed(rd(VY)) <= -4 and "J" or "-")
  run({}, 60)
  stand(); frames(3)
  run({up = true, b = true}, 2); r = r .. (rd(PFX) ~= 0 and "F" or "-")
  run({}, 5)
  stand(); frames(3)
  run({down = true}, 3); r = r .. (rd(SHIELD) == 1 and "S" or "-")
  run({}, 5)
  stand(); frames(3)
  run({b = true}, 2); r = r .. (rd(PFX) ~= 0 and "W" or "-")
  run({}, 5)
  return r
end
local function enter(n)
  wr16(PX, (6 * n - 3) * 16); wr(PY, n % 2 == 1 and 80 or 48); frames(30)
  press({a = true})
  check(wait_until(function() return rd(STATE) == 3 and rd(CUR) == n and rd(INTRO) == 0 end, 200), "dungeon " .. n .. " entered")
  frames(3)
end
local function leave()
  press({start = true}); press({select = true})
  check(wait_until(function() return rd(STATE) == 2 end, 40), "back in the overworld")
end
local function level(n, mask, word, who)
  enter(n)
  check(rd(AACT) == mask, who .. ": dungeon " .. n .. " active abilities " .. mask .. ", got " .. rd(AACT))
  local p = probe()
  check(p == word, who .. ": dungeon " .. n .. " works " .. word .. ", got " .. p)
  leave()
end

co = coroutine.create(function()
  -- cheat mode: nothing earned, yet each dungeon gives what its level would
  frames(30); held = {down = true}; frames(3); held = {}; frames(5)
  press({start = true}); frames(20); press({start = true}); frames(60)       -- CHEAT, Start skips the intro
  check(rd(STATE) == 2 and rd(CHEAT) == 1 and rd(ABIL) == 0, "cheat mode started, nothing earned")
  level(1, 0, "-----", "cheat")
  level(6, 7, "DJF--", "cheat")
  level(10, 31, "DJFSW", "cheat")
  check(rd(ABIL) == 0, "the progress record stays untouched, abilities=" .. rd(ABIL))

  -- normal mode: a save with all five abilities and all dungeons cleared; replaying an old level gives only that level's set
  local b, s = {0x45, 0x48, 1, 0xFF, 0x03, 31}, 0
  for i = 1, 6 do wr(SAVE + i - 1, b[i]); s = s + b[i] end
  wr(SAVE + 6, s % 256)
  emu.reset(); frames(30)
  press({start = true}); frames(20)                                           -- CONTINUE (first entry with a save)
  wait_until(function() return rd(STATE) == 2 end, 100)
  check(rd(STATE) == 2 and rd(CHEAT) == 0 and rd(ABIL) == 31 and rd(MASK) == 255 and rd(MASK + 1) == 3, "continue: all abilities saved, all dungeons open")
  level(2, 1, "D----", "normal")
  level(4, 3, "DJ---", "normal")
  level(10, 31, "DJFSW", "normal")
  check(rd(ABIL) == 31, "the progress record stays, abilities=" .. rd(ABIL))
  print("level abilities test OK")
  emu.stop(0)
end)

emu.addEventCallback(function() emu.setInput(held, 0, 0) end, emu.eventType.inputPolled)
emu.addEventCallback(function()
  if coroutine.status(co) == "dead" then return end
  local ok, err = coroutine.resume(co)
  if not ok then print("ERROR: " .. tostring(err)); emu.stop(1) end
end, emu.eventType.endFrame)
