-- Attack spam must not lock a boss (v1.1): mash B next to each boss (1..10) for 600 frames. After a hit the boss only keeps a short blink
-- (harmless 12 frames) and is immune to damage for 24 frames; its AI never pauses and a hit never resets its state machine.
-- Checks per boss: (a) it still acts: its state/position/shots keep changing on frames without a hit, and it hurts the player, shoots or runs through at least two states,
-- (b) hits are at least 24 frames apart (damage rate <= 1 per window), (c) it was hit at all (the mash really connects).
-- The player is glued to the boss's left side (x, y follow it, so the boss's own movement never ends the contact) and gets his hearts back every frame (never invulnerable:
-- contact and shots count). The boss hp is reset to full after every hit (the phase stays 1).
-- Addresses: docs/TECH.md "Debug-Adressen".
local M = emu.memType.nesMemory
local held = {}
local function rd(a) return emu.read(a, M) end
local function wr(a, v) emu.write(a, v, M) end
local function wr16(a, v) wr(a, v % 256); wr(a + 1, v // 256) end
local STATE, PX, PY, HEARTS, INV, VY = 0x302, 0x303, 0x305, 0x30B, 0x30C, 0x30F
local EX, EY, EH, EHP, EFLASH = 0x310, 0x311, 0x313, 0x314, 0x315
local INTRO, FBX, IAIR, PHASE, HIDE = 0x31A, 0x31B, 0x328, 0x318, 0x327
local FLOOR_Y = 176
local FRAMES, GAP = 600, 24
local HP = {10, 11, 12, 12, 13, 13, 14, 14, 20, 26}      -- max hp per dungeon (src/dungeon.c)

local co
local function frames(n) for _ = 1, n do coroutine.yield() end end
local function press(keys) held = keys; frames(3); held = {}; frames(5) end
local function check(cond, msg)
  if not cond then print("FAIL: " .. msg); emu.stop(1); coroutine.yield() end
end

local function enter(n)
  wr16(0x308, 1023)
  wr16(PX, (6 * n - 3) * 16); wr(PY, ((n % 2 == 1) and 5 or 3) * 16); frames(20)
  press({a = true})
  for _ = 1, 200 do if rd(STATE) == 3 and rd(INTRO) == 0 then break end frames(1) end
  check(rd(STATE) == 3 and rd(INTRO) == 0, "dungeon " .. n .. " fight started")
end
local function leave()
  press({start = true}); press({select = true})
  for _ = 1, 30 do if rd(STATE) == 2 then break end frames(1) end
  check(rd(STATE) == 2, "back in the overworld")
end

local function sig()
  local t = {rd(EX), rd(EY), rd(IAIR), rd(HIDE)}
  for k = 0, 2 do t[#t + 1] = rd(FBX + k) end
  return table.concat(t, ",")
end

local function mash(n)
  local hp, last, lost, shot, seen = HP[n], nil, 0, false, {}
  local hits, hitf, changes = {}, {}, 0
  wr(EHP, hp); wr(HEARTS, 3); wr(INV, 0)
  for i = 1, FRAMES do
    local ey = rd(EY)
    wr16(PX, math.max(16, rd(EX) - 14)); wr(PY, math.min(ey, FLOOR_Y)); wr(VY, 0)
    held = {b = i % 2 == 0}
    local before = rd(EHP)
    frames(1)
    local h = rd(HEARTS)
    if h < 3 then lost = lost + 3 - h; wr(HEARTS, 3) end
    for k = 0, 2 do if rd(FBX + k) ~= 0 then shot = true end end
    seen[rd(IAIR) * 8 + rd(HIDE)] = true
    local now = rd(EHP)
    local s = sig()
    if now < before then hits[#hits + 1] = i; wr(EHP, hp)
    elseif last and s ~= last then changes = changes + 1 end
    last = s
  end
  held = {}
  local mingap = 9999
  for i = 2, #hits do mingap = math.min(mingap, hits[i] - hits[i - 1]) end
  local states = 0
  for _ in pairs(seen) do states = states + 1 end
  return {states = states, hits = #hits, mingap = mingap, changes = changes, lost = lost, shot = shot, phase = rd(PHASE)}
end

co = coroutine.create(function()
  frames(30); held = {start = true}; frames(3); held = {}; frames(20); held = {start = true}; frames(3); held = {}; frames(60)
  check(rd(STATE) == 2, "boot reaches the overworld")
  for n = 1, 10 do
    enter(n)
    local r = mash(n)
    print(string.format("boss %2d: hits %2d, min gap %s, changes without a hit %3d, hearts lost %d, shot %s, states %d", n, r.hits, r.mingap == 9999 and "-" or r.mingap, r.changes, r.lost, tostring(r.shot), r.states))
    check(r.hits >= 1, "boss " .. n .. ": the mash connects")
    check(r.hits <= FRAMES // GAP + 1 and r.mingap >= GAP, "boss " .. n .. ": at most one hit per " .. GAP .. " frames, min gap " .. r.mingap)
    check(r.changes >= 10, "boss " .. n .. ": keeps moving/acting while it is hit, changes " .. r.changes)
    check(r.lost > 0 or r.shot or r.states >= 2, "boss " .. n .. ": still attacks (hearts lost, shots or state changes) while it is hit")
    leave()
  end
  print("spam test OK")
  emu.stop(0)
end)

emu.addEventCallback(function() emu.setInput(held, 0, 0) end, emu.eventType.inputPolled)
emu.addEventCallback(function()
  if coroutine.status(co) == "dead" then return end
  local ok, err = coroutine.resume(co)
  if not ok then print("ERROR: " .. tostring(err)); emu.stop(1) end
end, emu.eventType.endFrame)
