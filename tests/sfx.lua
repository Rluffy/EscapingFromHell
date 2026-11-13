-- Sound effects test (src/sfx.s): every effect id shows up on its channel after the action that triggers it, the APU channels are
-- enabled and really get written (volume > 0 while an effect plays, 0 when idle), nothing is louder than volume 10, and the engine
-- costs no frames (frame_count +1 per frame during a busy fight). Addresses: docs/TECH.md "Debug-Adressen", ids "Soundeffekte (v0.9)".
local M = emu.memType.nesMemory
local held = {}
local function rd(a) return emu.read(a, M) end
local function rd16(a) return rd(a) + 256 * rd(a + 1) end
local function wr(a, v) emu.write(a, v, M) end
local function wr16(a, v) wr(a, v % 256); wr(a + 1, v // 256) end
local STATE, PX, PY, MASK, CUR = 0x302, 0x303, 0x305, 0x308, 0x30A
local HEARTS, INV = 0x30B, 0x30C
local EX, EY, EHP, EFLASH = 0x310, 0x311, 0x314, 0x315
local INTRO, DEAD, ABIL = 0x31A, 0x319, 0x322
local LAST, ID = 0x339, 0x33A        -- ID + channel: 0 pulse 1, 1 pulse 2, 2 noise
local FLOOR_Y = 176
local JUMP, DJUMP, SWORD, HURT, BHIT, PHASE, BDEATH, VICTORY, DASH, FIRE, WAVE, BLOCK, SPIT, THUMP, MOVE, OK, GATE, ENDING =
  1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18
local CH = { 0, 0, 2, 0, 2, 1, 2, 1, 2, 0, 0, 2, 1, 2, 0, 0, 1, 1 }     -- channel of each id (src/sfx.s fx_cp)

local co
local seen, maxv, maxp, bad_vol = {}, {}, {}, nil        -- seen[id] = channel it played on, maxv[id] = loudest volume register sampled
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

local VOLKEY = { "apu.square1.envelope.volume", "apu.square2.envelope.volume", "apu.noise.envelope.volume" }
local PERKEY = { "apu.square1.realPeriod", "apu.square2.realPeriod" }
local function sample()                         -- once per frame: which effect plays where, how loud the channel is
  local s = emu.getState()
  for ch = 0, 2 do
    local id, v = rd(ID + ch), s[VOLKEY[ch + 1]]
    if id ~= 0 then
      if seen[id] == nil then seen[id] = ch end
      if v > (maxv[id] or 0) then maxv[id] = v end
      if ch < 2 and s[PERKEY[ch + 1]] > (maxp[id] or 0) then maxp[id] = s[PERKEY[ch + 1]] end
      if v > 10 then bad_vol = "id " .. id .. " volume " .. v end
    end
  end
  return s
end
local function expect(id, what, act)               -- run act, the effect must start on its channel
  seen = {}; maxv = {}; maxp = {}
  act()
  check(wait_until(function() return seen[id] ~= nil end, 90), what .. ": sfx " .. id .. " played")
  check(seen[id] == CH[id], what .. ": sfx " .. id .. " on channel " .. seen[id] .. ", want " .. CH[id])
  check(wait_until(function() return (maxv[id] or 0) > 0 end, 40), what .. ": channel register written (volume " .. tostring(maxv[id]) .. ")")
end
local function idle(ch) check(wait_until(function() return rd(ID + ch) == 0 end, 120), "channel " .. ch .. " goes idle") end

local pin = function() end                       -- runs every frame before the test resumes (parks boss / player)
local function enter(n)                          -- teleport onto door n, A, wait out arena build and intro
  wr16(PX, (6 * n - 3) * 16); wr(PY, (n % 2 == 1) and 80 or 48); frames(30)
  press({a = true}); frames(20)
  check(rd(STATE) == 3 and rd(CUR) == n, "dungeon " .. n .. " entered, state=" .. rd(STATE))
  check(wait_until(function() return rd(INTRO) == 0 end, 100), "intro ends")
end
local function safe() wr16(PX, 100); wr(PY, FLOOR_Y); wr(HEARTS, 3); wr(INV, 99) end
local function face_right() held = {right = true}; for _ = 1, 3 do safe(); frames(1) end; held = {}; safe(); frames(2) end

co = coroutine.create(function()
  -- boot: APU channels enabled, nothing played yet
  frames(20)
  local s = emu.getState()
  check(rd(STATE) == 1, "boot shows the start menu")
  check(s["apu.square1.envelope.lengthCounter.enabled"] and s["apu.square2.envelope.lengthCounter.enabled"] and
        s["apu.noise.envelope.lengthCounter.enabled"], "$4015 enables pulse 1, pulse 2 and noise")
  check(rd(LAST) == 0 and rd(ID) + rd(ID + 1) + rd(ID + 2) == 0, "no effect before any action")

  -- menu: move and confirm (cheat, so every gate is open)
  expect(MOVE, "menu move", function() hold({down = true}, 3) end)
  check(rd(LAST) == MOVE, "last effect = menu move, " .. rd(LAST))
  frames(15)
  check(rd(ID) == 0 and sample()["apu.square1.envelope.volume"] == 0, "finished effect leaves the channel silent")
  expect(OK, "menu confirm", function() hold({a = true}, 3) end)
  check(rd(LAST) == OK, "last effect = menu confirm")
  frames(60)
  check(rd(STATE) == 2 and rd(0x334) == 1, "cheat game started")

  -- dungeon 1 (Imp parked at the ceiling): entering plays the gate sound
  wr16(MASK, 0x3FF)
  seen = {}
  wr16(PX, 48); wr(PY, 80); frames(30)
  hold({a = true}, 3)
  check(wait_until(function() return seen[GATE] ~= nil end, 40) and seen[GATE] == 1, "dungeon enter: gate sound on pulse 2")
  frames(20)
  check(wait_until(function() return rd(INTRO) == 0 end, 100), "intro ends")
  pin = function() wr(EY, 0) end

  wr(ABIL, 0); safe(); frames(30); idle(0)
  expect(JUMP, "jump", function() hold({a = true}, 3) end)
  check(rd(LAST) == JUMP, "jump is the last effect, " .. rd(LAST))
  check((maxp[JUMP] or 0) > 100, "jump sets a pulse period, " .. tostring(maxp[JUMP]))
  check(wait_until(function() return rd(0x30D) == 1 end, 80), "landed"); idle(0)

  wr(ABIL, 2); safe(); frames(2)                 -- double jump: a second A press in the air
  expect(DJUMP, "double jump", function()
    held = {a = true}; frames(3); held = {}; frames(8); held = {a = true}; frames(3); held = {}
  end)
  check(wait_until(function() return rd(0x30D) == 1 end, 80), "landed again"); idle(0)

  pin = function() wr(EY, 0); wr(INV, 99); wr(HEARTS, 3) end
  idle(2)
  expect(SWORD, "sword swing", function() hold({b = true}, 3) end)
  idle(2)

  wr(ABIL, 1); frames(30)
  expect(DASH, "dash", function() hold({select = true}, 3) end)
  idle(2)

  wr(ABIL, 4); frames(45); idle(0)
  expect(FIRE, "player fireball", function() hold({up = true, b = true}, 3) end)
  frames(45); idle(0)

  wr(ABIL, 16); wr(0x329, 0); frames(30)
  expect(WAVE, "sword wave", function() safe(); face_right(); hold({b = true}, 3) end)
  frames(40); idle(0); idle(2)

  -- boss hit + phase change: the Imp (10 hp, phase 2 from hp 7) next to the player, one swing
  wr(ABIL, 0)
  pin = function() safe(); wr(EX, 114); wr(EY, FLOOR_Y); wr(EFLASH, 0) end
  wr(EHP, 8); wr(0x318, 1); frames(3)
  expect(BHIT, "boss hit", function() held = {b = true}; frames(3); held = {} end)
  check(wait_until(function() return seen[PHASE] ~= nil end, 30) and seen[PHASE] == 1, "phase change: sfx 6 on pulse 2")
  check(rd(0x318) == 2, "boss is in phase 2")
  frames(45)

  -- player hurt: boss on top of the player, no invulnerability
  pin = function() wr16(PX, 100); wr(PY, FLOOR_Y); wr(HEARTS, 3); wr(EX, 100); wr(EY, FLOOR_Y); wr(EFLASH, 0) end
  wr(INV, 0); idle(0)
  expect(HURT, "player hurt", function() wr(INV, 0); frames(3) end)
  frames(10)

  -- shield block: shield up (Down), boss touching from the front
  wr(ABIL, 8)
  pin = function() wr16(PX, 100); wr(PY, FLOOR_Y); wr(HEARTS, 3); wr(EFLASH, 0) end
  wr(INV, 99); wr(EX, 140); frames(60); idle(0); idle(2)
  held = {down = true}; frames(3)
  expect(BLOCK, "shield block", function() wr(INV, 0); wr(EX, 108); wr(EY, FLOOR_Y); frames(3) end)
  held = {}; frames(20)

  -- boss spit (Imp fireballs) at a safe distance
  pin = function() wr16(PX, 100); wr(PY, FLOOR_Y); wr(HEARTS, 3); wr(INV, 99); wr(EY, 100); wr(EFLASH, 0) end
  wr(ABIL, 0)
  seen = {}
  check(wait_until(function() return seen[SPIT] ~= nil end, 600) and seen[SPIT] == 1, "boss spit: sfx 13 on pulse 2")

  -- busy fight: the engine does not slow the main loop (60 Hz, +1 per frame) while effects keep firing
  pin = function() safe(); wr(EY, 0) end
  local f0 = rd16(0x300)
  for i = 1, 300 do held = { a = i % 20 < 3, b = i % 14 < 3 }; frames(1) end
  held = {}
  local d = rd16(0x300) - f0
  check(d >= 299 and d <= 301, "busy scene runs at 60 Hz: frame_count +" .. d .. " in 300 frames")

  -- kill: boss death, victory jingle
  pin = function() safe(); wr(EX, 114); wr(EY, FLOOR_Y); wr(EFLASH, 0) end
  wr(EHP, 1); frames(2)
  seen = {}
  check(wait_until(function() held = {b = rd(0x300) % 2 == 0}; return rd(DEAD) == 1 end, 600), "boss killed")
  held = {}
  check(wait_until(function() return seen[VICTORY] ~= nil end, 20), "victory jingle played")
  check(seen[BDEATH] == 2 and seen[VICTORY] == 1, "boss death on noise, victory on pulse 2")
  check(rd(LAST) == VICTORY, "last effect = victory, " .. rd(LAST))
  pin = function() end
  check(wait_until(function() return rd(STATE) == 2 end, 400), "back on the overworld")

  -- dungeon 9: shockwave thump
  enter(9)
  pin = function() safe(); wr(EFLASH, 0) end
  seen = {}
  check(wait_until(function() return seen[THUMP] ~= nil end, 1500) and seen[THUMP] == 2, "oni shockwave: thump on noise")
  pin = function() end
  press({start = true}); press({select = true})
  check(wait_until(function() return rd(STATE) == 2 end, 100), "gave up dungeon 9")
  enter(10)
  pin = function() safe(); wr(EX, 114); wr(EY, FLOOR_Y); wr(EFLASH, 0) end
  wr(EHP, 1)
  seen = {}
  check(wait_until(function() held = {b = rd(0x300) % 2 == 0}; return rd(STATE) == 4 end, 900), "ending screen reached")
  held = {}; pin = function() end
  check(wait_until(function() return seen[ENDING] ~= nil end, 10) and seen[ENDING] == 1, "ending sting on pulse 2")
  check(rd(LAST) == ENDING, "last effect = ending sting, " .. rd(LAST))

  check(bad_vol == nil, "nothing louder than volume 10: " .. tostring(bad_vol))
  print("sfx test OK")
  emu.stop(0)
end)

emu.addEventCallback(function() emu.setInput(held, 0, 0) end, emu.eventType.inputPolled)
emu.addEventCallback(function()
  if coroutine.status(co) == "dead" then return end
  sample()
  pin()
  local ok, err = coroutine.resume(co)
  if not ok then print("ERROR: " .. tostring(err)); emu.stop(1) end
end, emu.eventType.endFrame)
