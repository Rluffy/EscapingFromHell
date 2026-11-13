-- Boss fights are deterministic: the boss rng is seeded per dungeon on entry and on the restart at 0 hearts, and all boss timing runs
-- on the fight clock (ftick), not on frame_count. For every dungeon 1..10 the same inputs (none: a standing player) give the identical
-- frame-by-frame trace (boss, shots, hearts, the visible sprites) (1) on the first entry, (2) after leaving and entering again at
-- another frame_count, (3) after the restart at 0 hearts. One sample per game frame, taken when the main loop calls wait_vblank
-- (the previous frame is complete; a frame that overruns the vblank, like the Lava Snake's, would be sampled half done at its end).
-- Addresses: docs/TECH.md "Debug-Adressen", "Boss-Zufall (v1.0)".
local M = emu.memType.nesMemory
local held = {}
local function rd(a) return emu.read(a, M) end
local function wr(a, v) emu.write(a, v, M) end
local function wr16(a, v) wr(a, v % 256); wr(a + 1, v // 256) end
local STATE, PX, PY, HEARTS, INV, EX, EY = 0x302, 0x303, 0x305, 0x30B, 0x30C, 0x310, 0x311
local PHASE, INTRO, FBX, FBY, IAIR, HIDE, EHP = 0x318, 0x31A, 0x31B, 0x31E, 0x328, 0x327, 0x314
local N = 240                                -- game frames compared per trace

-- wait_vblank: lda _frame_count / cmp _frame_count / beq -5 / rts, found in the fixed bank
local WAIT
for a = 0xC000, 0xFFF0 do
  if rd(a) == 0xAD and rd(a + 1) == 0x00 and rd(a + 2) == 0x03 and rd(a + 3) == 0xCD and rd(a + 4) == 0x00 and rd(a + 5) == 0x03
     and rd(a + 6) == 0xF0 and rd(a + 7) == 0xFB and rd(a + 8) == 0x60 then WAIT = a; break end
end
if not WAIT then print("FAIL: wait_vblank not found"); emu.stop(1) end

local samples = {}                           -- {str = trace line, intro = , hearts = , state = } per game frame
local function snap()
  local t = {}
  for _, a in ipairs({EX, EY, EHP, IAIR, HIDE, PHASE, HEARTS, INV}) do t[#t + 1] = rd(a) end
  for k = 0, 2 do t[#t + 1] = rd(FBX + k); t[#t + 1] = rd(FBX + k) ~= 0 and rd(FBY + k) or 0 end     -- a free slot keeps a stale y
  local h = 0
  for i = 0, 252, 4 do                       -- the visible sprites (a hidden one keeps stale tile/x bytes of an earlier dungeon)
    if rd(0x200 + i) < 0xEF then for j = 0, 3 do h = (h * 31 + rd(0x200 + i + j)) % 1000000007 end end
    h = (h * 31 + (rd(0x200 + i) < 0xEF and 1 or 0)) % 1000000007
  end
  t[#t + 1] = h
  samples[#samples + 1] = {str = table.concat(t, ","), intro = rd(INTRO), hearts = rd(HEARTS), state = rd(STATE)}
end
emu.addMemoryCallback(snap, emu.callbackType.exec, WAIT)

local co
local function frames(n) for _ = 1, n do coroutine.yield() end end
local function press(keys) held = keys; frames(3); held = {}; frames(5) end
local function check(cond, msg)
  if not cond then print("FAIL: " .. msg); emu.stop(1); coroutine.yield() end
end
-- waits for the first sample where test(sample) holds, then for N more samples; returns those N trace lines
local function collect(test, what)
  local s0
  for _ = 1, 600 do
    for i = 1, #samples do if test(samples[i]) then s0 = i; break end end
    if s0 then break end
    frames(1)
  end
  check(s0, what .. ": sync point")
  for _ = 1, 600 do if #samples >= s0 + N then break end frames(1) end
  check(#samples >= s0 + N, what .. ": enough samples")
  local t = {}
  for i = 1, N do t[i] = samples[s0 + i].str end
  return t
end
local function same(a, b, what)
  for i = 1, N do
    if a[i] ~= b[i] then
      for j = math.max(1, i - 2), i do print(j, a[j], b[j]) end
      check(false, what .. ": traces differ at fight frame " .. i)
    end
  end
end
local function enter(n)
  local dr = (n % 2 == 1) and 5 or 3
  wr16(PX, (6 * n - 3) * 16); wr(PY, dr * 16); frames(30)
  samples = {}
  press({a = true})
end
local function fresh(n)                      -- sync: the sample after the last intro frame
  return collect(function(s) return s.state == 3 and s.intro == 0 end, "dungeon " .. n)
end
local function leave()
  press({start = true}); press({select = true})
  for _ = 1, 30 do if rd(STATE) == 2 then break end frames(1) end
  check(rd(STATE) == 2, "back in the overworld")
end

co = coroutine.create(function()
  frames(30); held = {start = true}; frames(3); held = {}; frames(20); held = {start = true}; frames(3); held = {}; frames(60)
  check(rd(STATE) == 2, "boot reaches the overworld")
  wr16(0x308, 1023)                          -- all gates open (mask, not the menu cheat: fights are the real thing)
  for n = 1, 10 do
    enter(n)
    local a = fresh(n)
    leave(); frames(7 + 3 * n)               -- another history: other frame_count, other idle time
    enter(n)
    local b = fresh(n)
    same(a, b, "dungeon " .. n .. ": first entry vs re-entry")
    samples = {}                             -- the boss touches the player: 0 hearts, the fight restarts
    for _ = 1, 400 do
      wr(HEARTS, 1); wr(INV, 0); wr16(PX, rd(EX)); wr(PY, rd(EY))
      frames(1)
      if #samples > 0 and samples[#samples].hearts == 3 then break end      -- hearts 3 right after the pin of 1: the restart
    end
    local c = collect(function(s) return s.hearts == 3 end, "dungeon " .. n .. " restart")
    same(a, c, "dungeon " .. n .. ": first entry vs restart")
    leave(); frames(11)
    print("dungeon " .. n .. " deterministic over " .. N .. " frames")
  end
  print("determinism test OK")
  emu.stop(0)
end)

emu.addEventCallback(function() emu.setInput(held, 0, 0) end, emu.eventType.inputPolled)
emu.addEventCallback(function()
  if coroutine.status(co) == "dead" then return end
  local ok, err = coroutine.resume(co)
  if not ok then print("ERROR: " .. tostring(err)); emu.stop(1) end
end, emu.eventType.endFrame)
