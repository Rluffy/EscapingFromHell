-- Frame budget: the main loop must never miss a frame and keeps ~10 % cycle headroom (a frame whose work overruns the vblank costs the next NMI: 30 fps, OAM
-- DMA of half-written sprites). Measured as frame_count delta - main-loop iteration delta (debug counter `loops`, $0340) over
-- 600 frames of busy play (the player is hit all the time: invulnerability skips the contact tests) for EVERY boss in all 3 phases (phase and hp forced via memory writes, all abilities, a looping input
-- pattern: sword, fireball, wave, shield, dash, double jump), plus the victory screen, the ending, overworld scrolling with animation,
-- title menu and intro. Addresses: docs/TECH.md "Debug-Adressen", "Fehlersuche v1.0".
local M = emu.memType.nesMemory
local held = {}
local function rd(a) return emu.read(a, M) end
local function rd16(a) return rd(a) + 256 * rd(a + 1) end
local function wr(a, v) emu.write(a, v, M) end
local function wr16(a, v) wr(a, v % 256); wr(a + 1, v // 256) end
local STATE, PX, PY, CLEARED, HEARTS, INV, EHP = 0x302, 0x303, 0x305, 0x308, 0x30B, 0x30C, 0x314
local INTRO, ABIL, DEAD, LOOPS, FRAMES = 0x31A, 0x322, 0x319, 0x340, 0x300
local N = 600
local HP = {{10, 11, 12, 12, 13, 13, 14, 14, 15, 18}}          -- max hp per dungeon (src/dungeon.c)
local PHASE_HP = function(n, ph)                                -- hp inside phase ph (thresholds: 70 % and 50 % of max)
  local m = HP[1][n]
  return ph == 1 and m or ph == 2 and math.floor(m * 70 / 100) or math.floor(m / 2)
end
local PAT = {{right = true, b = true}, {left = true, b = true}, {up = true, b = true}, {down = true}, {right = true, a = true},
             {select = true, right = true}, {left = true, a = true, b = true}, {right = true}}

-- CPU cycles the main loop needs per frame: from the start of the NMI handler to the call of wait_vblank (found in the fixed bank:
-- lda _frame_count / cmp _frame_count / beq -5 / rts). A frame has 29780 cycles; LIMIT keeps ~10 % headroom.
local LIMIT = 26800
local WAIT
for a = 0xC000, 0xFFF0 do
  if rd(a) == 0xAD and rd(a + 1) == 0x00 and rd(a + 2) == 0x03 and rd(a + 3) == 0xCD and rd(a + 4) == 0x00 and rd(a + 5) == 0x03
     and rd(a + 6) == 0xF0 and rd(a + 7) == 0xFB and rd(a + 8) == 0x60 then WAIT = a; break end
end
if not WAIT then print("FAIL: wait_vblank not found"); emu.stop(1) end
local cyc_nmi, spent_max = 0, 0
local function cycles() return emu.getState()["cpu.cycleCount"] end
emu.addMemoryCallback(function() cyc_nmi = cycles() end, emu.callbackType.exec, rd(0xFFFA) + 256 * rd(0xFFFB))
emu.addMemoryCallback(function()
  local c = cycles() - cyc_nmi
  if c < 2 * 29780 and c > spent_max then spent_max = c end     -- a longer gap = rendering off (screen redraw), not a frame
end, emu.callbackType.exec, WAIT)

-- Vblank discipline: while rendering is on, VRAM address / data writes must happen in vblank (scanlines 241..260). Checked at every $2006
-- write and every 4th $2007 write (so a burst that runs past the end of vblank is caught at its tail).
local viol, nw = {}, 0
local function in_vblank_or_off()
  local st = emu.getState()
  if not (st["ppu.mask.backgroundEnabled"] or st["ppu.mask.spritesEnabled"]) then return true end
  local l = st["ppu.scanline"]
  return l >= 241 and l <= 260
end
emu.addMemoryCallback(function() if not in_vblank_or_off() then viol[#viol + 1] = "$2006" end end, emu.callbackType.write, 0x2006)
emu.addMemoryCallback(function()
  nw = nw + 1
  if nw % 4 == 0 and not in_vblank_or_off() then viol[#viol + 1] = "$2007" end
end, emu.callbackType.write, 0x2007)

local co
local function frames(n) for _ = 1, n do coroutine.yield() end end
local function press(keys) held = keys; frames(3); held = {}; frames(5) end
local function check(cond, msg)
  if not cond then print("FAIL: " .. msg); emu.stop(1); coroutine.yield() end
end
-- n frames, calling drive(i) before each; returns the frames the main loop missed
local function measure(n, drive)
  local f0, l0 = rd16(FRAMES), rd16(LOOPS)
  spent_max = 0
  for i = 1, n do if drive then drive(i) end frames(1) end
  return (rd16(FRAMES) - f0) % 65536 - (rd16(LOOPS) - l0) % 65536
end
local worst, bad = 0, {}
local function report(name, missed)
  print(string.format("budget %-26s missed frames %d, busiest frame %5d of 29780 cycles", name, missed, spent_max))
  worst = math.max(worst, missed)
  if #viol > 0 then print("  PPU write outside vblank while rendering: " .. viol[1] .. " (" .. #viol .. "x)"); viol = {}; bad[#bad + 1] = name .. " (PPU write outside vblank)" end
  if missed ~= 0 or spent_max > LIMIT then bad[#bad + 1] = name end      -- all scenes run, then the list fails the test
end

local function leave()
  press({start = true}); press({select = true})
  for _ = 1, 30 do if rd(STATE) == 2 then break end frames(1) end
  check(rd(STATE) == 2, "back in the overworld")
end

co = coroutine.create(function()
  frames(30)
  check(rd(STATE) == 1, "title menu")
  report("title menu", measure(N))
  press({start = true}); frames(1)                 -- NEW GAME: intro
  check(rd(STATE) == 5, "intro, state=" .. rd(STATE)); frames(10)
  report("intro", measure(N // 3))
  press({start = true}); frames(30)
  check(rd(STATE) == 2, "overworld")
  wr16(CLEARED, 1023); wr(ABIL, 31)
  -- overworld: walk the whole map right and back with the camera scrolling and the lava animating
  wr16(PX, 12); wr(PY, 144); frames(10)
  report("overworld scroll right", measure(N, function() held = {right = true} end))
  report("overworld scroll left", measure(N, function() held = {left = true} end))
  report("overworld diagonal", measure(N, function(i) held = (i // 90) % 2 == 0 and {right = true, up = true} or {left = true, down = true} end))
  held = {}
  for n = 1, 10 do
    local dr = (n % 2 == 1) and 5 or 3
    wr16(PX, (6 * n - 3) * 16); wr(PY, dr * 16); frames(20)
    press({a = true})
    for _ = 1, 200 do if rd(STATE) == 3 and rd(INTRO) == 0 then break end frames(1) end
    check(rd(STATE) == 3 and rd(INTRO) == 0, "dungeon " .. n .. " fight started")
    wr(ABIL, 31)
    for ph = 1, 3 do
      local hp = PHASE_HP(n, ph)
      held = {}; frames(4)                          -- the hp bar of the last hit is written first (a forced phase change right behind it would put bar and palette into one vblank, which the game itself never does)
      wr(0x318, ph); wr(EHP, hp); frames(2)
      report(string.format("boss %2d phase %d", n, ph), measure(N, function(i)
        wr(HEARTS, 3); wr(INV, 0)                     -- never invulnerable: every overlap test runs, the bot gets hit (hearts stay 3)
        if rd(EHP) < hp then wr(EHP, hp) end        -- the bot hits, the boss stays in the phase (hp changes still redraw the bar)
        if rd(EHP) == 0 then wr(EHP, hp) end
        held = PAT[(i // 20) % #PAT + 1]
      end))
    end
    held = {}
    -- victory screen (and for dungeon 10 the ending screen)
    wr(HEARTS, 3); wr(INV, 99); wr(EHP, 0); wr(DEAD, 1); frames(5)
    local vic = measure(N // 6, function() wr(HEARTS, 3); wr(INV, 99) end)
    report("victory " .. n, vic)
    if n == 10 then
      for _ = 1, 400 do if rd(STATE) == 4 then break end frames(1) end
      check(rd(STATE) == 4, "ending shown")
      frames(5)
      report("ending", measure(N // 5))
    end
    for _ = 1, 400 do if rd(STATE) == 2 then break end frames(1) end
    check(rd(STATE) == 2, "back in the overworld after dungeon " .. n)
    frames(5)
  end
  check(#bad == 0, "frames missed or less than 10 % headroom in: " .. table.concat(bad, ", "))
  print("budget test OK (worst missed frames: " .. worst .. ")")
  emu.stop(0)
end)

emu.addEventCallback(function() emu.setInput(held, 0, 0) end, emu.eventType.inputPolled)
emu.addEventCallback(function()
  if coroutine.status(co) == "dead" then return end
  local ok, err = coroutine.resume(co)
  if not ok then print("ERROR: " .. tostring(err)); emu.stop(1) end
end, emu.eventType.endFrame)
