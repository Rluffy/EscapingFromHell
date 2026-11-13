-- Balance test: two scripted bots survive each boss in all 3 phases (the fights are deterministic: fight clock and rng seed per dungeon).
--  (a) standing bot: no input at x 48 on the floor.
--  (b) dodger bot: stays at x 90 (no platform above it) and only jumps (A held 12 frames, no abilities) when a boss shot (fb slots: fireballs, webs, slime,
--      shockwaves) is within 24 px horizontally at its height, or the boss body rushes at it (>= 2 px/frame) within 48 px at its height.
-- Hearts lost per phase are counted (hearts are refilled so the fight never restarts) and must stay within the targets per 1200 frames: standing bot <= 2
-- for bosses 1..5 and <= 3 for 6..10, dodger <= 3 (aim 1..2); with SAMPLE = 600 the limits are halved, rounded up (1 / 2 / 2) (docs/GAMEDESIGN.md "Balance", docs/TECH.md "Balance-Messung (v1.0)"). One dungeon entry per boss and bot; the
-- phases run one after the other, forced like a real phase change (phase, hp, boss_fx 30, shots cleared). SAMPLE frames per phase: 600 keeps the whole test
-- near 90 s (Mesen runs ~450 frames/s); the table in the docs was measured with SAMPLE = 1200 (change the constant to repeat it, ~190 s, over the
-- 180 s timeout of make test, so run it by hand).
-- The hp table below must match src/dungeon.c. Addresses: docs/TECH.md "Debug-Adressen".
local M = emu.memType.nesMemory
local held = {}
local function rd(a) return emu.read(a, M) end
local function wr(a, v) emu.write(a, v, M) end
local function wr16(a, v) wr(a, v % 256); wr(a + 1, v // 256) end
local STATE, PX, PY, HEARTS, INV, GROUND = 0x302, 0x303, 0x305, 0x30B, 0x30C, 0x30D
local EX, EY, EW, EH, EHP = 0x310, 0x311, 0x312, 0x313, 0x314
local PHASE, INTRO, FBX, FBY, HIDE, VY = 0x318, 0x31A, 0x31B, 0x31E, 0x327, 0x30F
local FLOOR_Y = 176
local SAMPLE = 600
local SHOT_RANGE, BODY_RANGE = 24, 48
local DODGE_X = 90                                         -- between the left and the top platform: a jump from x 48 would land on the left platform
local HP = {10, 11, 12, 12, 13, 13, 14, 14, 20, 26}        -- max hp per dungeon (src/dungeon.c)
local LIMIT_STAND = {2, 2, 2, 2, 2, 3, 3, 3, 4, 4}          -- standing bot per 1200 frames: bosses 1..5 <= 2 hearts per phase, 6..8 <= 3, the climax 9 and 10 <= 4 (v1.1)
local LIMIT_DODGE = 3                                      -- dodger bot per 1200 frames, every boss and phase (the aim is 1..2, see docs/GAMEDESIGN.md "Balance")
local function limit(t) return (t * SAMPLE + 1199) // 1200 end   -- the targets are per 1200 frames: scaled (rounded up) to the sampled window

local co
local function frames(n) for _ = 1, n do coroutine.yield() end end
local function press(keys) held = keys; frames(3); held = {}; frames(5) end
local function check(cond, msg)
  if not cond then print("FAIL: " .. msg); emu.stop(1); coroutine.yield() end
end

local function enter(n)
  wr16(0x308, 1023)                                        -- all gates open
  local dr = (n % 2 == 1) and 5 or 3
  wr16(PX, (6 * n - 3) * 16); wr(PY, dr * 16); frames(20)
  press({a = true})
  for _ = 1, 200 do if rd(STATE) == 3 and rd(INTRO) == 0 then break end frames(1) end
  check(rd(STATE) == 3 and rd(INTRO) == 0, "dungeon " .. n .. " fight started")
end
local function leave()
  press({start = true}); press({select = true})
  for _ = 1, 30 do if rd(STATE) == 2 then break end frames(1) end
  check(rd(STATE) == 2, "back in the overworld")
end

-- true when a boss shot is within SHOT_RANGE px horizontally and level with the player (the jump takes ~44 frames: shots fly 1..3 px/frame),
-- or the boss body rushes at the player (moves >= 2 px/frame toward him: charge, hop, dash) within BODY_RANGE px at his height.
-- Slow drifters and fliers are not jumped at: a jump would only meet them (their numbers come from the standing bot).
local pex = 0
local function threat()
  local px, py = rd(PX) + 8, rd(PY)
  local ex, ey, ew, eh = rd(EX), rd(EY), rd(EW), rd(EH)
  local v = ex - pex; pex = ex
  for k = 0, 2 do
    local fx = rd(FBX + k)
    if fx ~= 0 then
      local fy = rd(FBY + k)
      if math.abs(fx + 4 - px) <= SHOT_RANGE and fy + 8 > py - 8 and fy < py + 16 then return true end
    end
  end
  local mid = ex + ew // 2
  if rd(HIDE) & 1 == 0 and rd(EHP) > 0 and math.abs(v) >= 2 and math.abs(v) < 8 and (px - mid) * v > 0 and math.abs(px - mid) <= BODY_RANGE + ew // 2
     and ey + eh > py and ey < py + 16 then return true end
  return false
end

-- one run: returns hearts lost over SAMPLE frames
local function run(n, ph, dodger)
  local hp = HP[n]
  hp = ph == 1 and hp or ph == 2 and (hp * 70 // 100) or hp // 2
  if ph > 1 then wr(PHASE, ph); wr(EHP, hp); wr(0x321, 30); for k = 0, 2 do wr(FBX + k, 0) end end
  frames(2)
  local lost, jump = 0, 0
  wr(HEARTS, 3); wr(INV, 0)
  for _ = 1, SAMPLE do
    wr16(PX, dodger and DODGE_X or 48)
    if not dodger then wr(PY, FLOOR_Y); wr(VY, 0) end
    if dodger then
      local t = threat()
      if jump == 0 and rd(GROUND) == 1 and t then jump = 12 end
      held = jump > 0 and {a = true} or {}
      if jump > 0 then jump = jump - 1 end
    end
    frames(1)
    local h = rd(HEARTS)
    if h < 3 then lost = lost + 3 - h; wr(HEARTS, 3) end
    wr(EHP, hp)
  end
  held = {}
  return lost
end

co = coroutine.create(function()
  frames(30); held = {start = true}; frames(3); held = {}; frames(20); held = {start = true}; frames(3); held = {}; frames(60)
  check(rd(STATE) == 2, "boot reaches the overworld")
  local bad = {}
  print(string.format("balance (%d frames per phase): hearts lost  stand p1/p2/p3  dodge p1/p2/p3", SAMPLE))
  for n = 1, 10 do
    local r = {}
    for _, dodger in ipairs({false, true}) do
      local t = {}
      enter(n)
      if rd(EHP) ~= HP[n] then bad[#bad + 1] = "boss " .. n .. " has " .. rd(EHP) .. " hp, want " .. HP[n]; HP[n] = rd(EHP) end   -- (the thresholds follow the real hp)
      for ph = 1, 3 do
        t[ph] = run(n, ph, dodger)
        if t[ph] > limit(dodger and LIMIT_DODGE or LIMIT_STAND[n]) then
          bad[#bad + 1] = string.format("boss %d phase %d %s bot lost %d", n, ph, dodger and "dodger" or "standing", t[ph])
        end
      end
      leave()
      r[#r + 1] = table.concat(t, "/")
    end
    print(string.format("boss %2d  hp %2d  stand %s  dodge %s", n, HP[n], r[1], r[2]))
  end
  check(#bad == 0, "over the targets: " .. table.concat(bad, "; "))
  print("balance test OK")
  emu.stop(0)
end)

emu.addEventCallback(function() emu.setInput(held, 0, 0) end, emu.eventType.inputPolled)
emu.addEventCallback(function()
  if coroutine.status(co) == "dead" then return end
  local ok, err = coroutine.resume(co)
  if not ok then print("ERROR: " .. tostring(err)); emu.stop(1) end
end, emu.eventType.endFrame)
