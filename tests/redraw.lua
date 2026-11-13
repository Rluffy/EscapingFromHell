-- Full-screen redraws: frames with rendering off (the black screen) per redraw, measured as endFrame samples with the background
-- disabled over the 40 frames after the trigger. Limit MAX = 3 (v1.0 package 1: asm blits in src/ppu.s; before: 10..14).
-- Redraws: menu question (DELETE SAVE) and back, intro start, intro page turn, overworld, overworld teleport, dungeon entry (1: plain,
-- 4: lava pools, 8: ceiling), leaving a dungeon, ending screen.
-- Addresses: docs/TECH.md "Debug-Adressen", "Bildaufbau (v1.0)".
local M = emu.memType.nesMemory
local held = {}
local function rd(a) return emu.read(a, M) end
local function rd16(a) return rd(a) + 256 * rd(a + 1) end
-- PRG-RAM is write-protected by the game (MMC3 $A001 = $C0 outside save_game): the test writes the save RAM directly
local function wr(a, v) if a >= 0x6000 and a < 0x8000 then emu.write(a - 0x6000, v, emu.memType.nesSaveRam) else emu.write(a, v, M) end end
local function wr16(a, v) wr(a, v % 256); wr(a + 1, v // 256) end
local STATE, PX, PY, CUR, DEAD, VICT = 0x302, 0x303, 0x305, 0x30A, 0x319, 0x325
local SAVE = 0x6000
local MAX = 3

local co
local function frames(n) for _ = 1, n do coroutine.yield() end end
local function press(keys) held = keys; frames(3); held = {}; frames(5) end
local function check(cond, msg)
  if not cond then print("FAIL: " .. msg); emu.stop(1); coroutine.yield() end
end
local function black() return not emu.getState()["ppu.mask.backgroundEnabled"] end
-- run trigger() (it presses keys), then count black frames over the next 40 frames
local function measure(name, trigger)
  local n = 0
  local f = coroutine.create(trigger)
  held = {}
  for i = 1, 40 do
    if coroutine.status(f) ~= "dead" then coroutine.resume(f) end
    coroutine.yield()
    if black() then n = n + 1 end
  end
  held = {}
  print(string.format("redraw %-28s black frames %2d", name, n))
  check(n >= 1 and n <= MAX, name .. ": black frames " .. n .. " (limit " .. MAX .. ")")
end
local function hold3(keys) return function() held = keys; coroutine.yield(); coroutine.yield(); coroutine.yield(); held = {} end end
local function write_save(lo, hi, ab)
  local b = {0x45, 0x48, 1, lo, hi, ab}
  local s = 0
  for i = 1, 6 do wr(SAVE + i - 1, b[i]); s = s + b[i] end
  wr(SAVE + 6, s % 256)
end

co = coroutine.create(function()
  frames(20)                                 -- PRG-RAM is enabled once the reset code has run
  write_save(0, 0, 0)
  emu.reset(); frames(40)
  check(rd(STATE) == 1, "menu shown")
  press({down = true}); press({down = true}); press({down = true})          -- CONTINUE, NEW GAME, CHEAT, DELETE SAVE
  measure("menu: DELETE SAVE question", hold3({a = true}))
  measure("menu: back (B)", hold3({b = true}))
  press({up = true})                                                         -- CHEAT
  measure("intro (start)", hold3({start = true}))
  check(rd(STATE) == 5, "intro shown, state=" .. rd(STATE))
  measure("intro page turn", hold3({a = true}))
  measure("overworld (from intro)", hold3({start = true}))
  check(rd(STATE) == 2, "overworld, state=" .. rd(STATE))
  measure("overworld teleport", function() wr16(PX, 5 * 16 * 6); wr(PY, 48) end)
  for _, n in ipairs({1, 4, 8}) do
    local dr = (n % 2 == 1) and 5 or 3
    wr16(PX, (6 * n - 3) * 16); wr(PY, dr * 16); frames(30)
    measure("dungeon " .. n .. " entry", hold3({a = true}))
    check(rd(STATE) == 3 and rd(CUR) == n, "dungeon " .. n .. " entered, state=" .. rd(STATE))
    frames(10)
    press({start = true})
    measure("leave dungeon " .. n, hold3({select = true}))
    check(rd(STATE) == 2, "overworld again")
  end
  wr16(PX, (6 * 10 - 3) * 16); wr(PY, 48); frames(30)
  press({a = true}); frames(100)
  check(rd(STATE) == 3 and rd(CUR) == 10, "dungeon 10 entered")
  measure("ending screen", function() wr(DEAD, 1); wr(VICT, 2) end)
  check(rd(STATE) == 4, "ending shown, state=" .. rd(STATE))
  print("redraw test OK")
  emu.stop(0)
end)

emu.addEventCallback(function() emu.setInput(held, 0, 0) end, emu.eventType.inputPolled)
emu.addEventCallback(function()
  if coroutine.status(co) == "dead" then return end
  local ok, err = coroutine.resume(co)
  if not ok then print("ERROR: " .. tostring(err)); emu.stop(1) end
end, emu.eventType.endFrame)
