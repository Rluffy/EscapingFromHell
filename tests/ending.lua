-- Full-order run in NORMAL mode: dungeons 1..10 in order. Per dungeon: its gate is open, the next one locked, boss killed by
-- a real sword hit, mask grows bit by bit, ability appears at 1/3/5/7/9, save valid after each. After 10: ending screen
-- the dawn ending screen (big "YOU ESCAPED", sun, hero, "THE END", "THANKS FOR PLAYING"), Start only after a guard time,
-- back at door 10 with the ending flag in the save.
-- Addresses and save layout: docs/TECH.md "Debug-Adressen", "Speicherstand", "Titel, Intro und Ende (v0.9)".
local M = emu.memType.nesMemory
local held = {}
local function rd(a) return emu.read(a, M) end
local function rd16(a) return rd(a) + 256 * rd(a + 1) end
-- PRG-RAM is write-protected by the game (MMC3 $A001 = $C0 outside save_game): the test writes the save RAM directly
local function wr(a, v) if a >= 0x6000 and a < 0x8000 then emu.write(a - 0x6000, v, emu.memType.nesSaveRam) else emu.write(a, v, M) end end
local function wr16(a, v) wr(a, v % 256); wr(a + 1, v // 256) end
local function ppu(a) return emu.read(a, emu.memType.nesPpuMemory) end
local STATE, PX, PY, MASK, CUR = 0x302, 0x303, 0x305, 0x308, 0x30A
local HEARTS, INV = 0x30B, 0x30C
local EX, EY, EHP, EFLASH = 0x310, 0x311, 0x314, 0x315
local INTRO, DEAD, ABIL, ENDT = 0x31A, 0x319, 0x322, 0x336
local ENDING = 0x333
local SAVE = 0x6000
local FLOOR_Y = 176
local ABILS = {1, 1, 3, 3, 7, 7, 15, 15, 31, 31}     -- abilities after dungeon n

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
local function gate_tile(n)
  local dr = (n % 2 == 1) and 5 or 3
  local col = (6 * n - 3) * 2
  return ppu(0x2000 + ((col // 32) % 2) * 0x400 + (dr + 1) * 2 * 32 + col % 32)
end
local function save_ok(mask, ab, ending)     -- bytes + checksum of the autosave
  local hi = (mask // 256) + (ending and 0x80 or 0)
  local b = {0x45, 0x48, 1, mask % 256, hi, ab}
  local s = 0
  for i = 1, 6 do check(rd(SAVE + i - 1) == b[i], "save byte " .. (i - 1) .. " = " .. rd(SAVE + i - 1) .. ", want " .. b[i]); s = s + b[i] end
  check(rd(SAVE + 6) == s % 256, "save checksum")
end

co = coroutine.create(function()
  for i = 0, 6 do wr(SAVE + i, 0) end
  emu.reset(); frames(30); held = {start = true}; frames(3); held = {}; frames(20); held = {start = true}; frames(3); held = {}; frames(60)
  check(rd(STATE) == 2 and rd16(MASK) == 0 and rd(ENDING) == 0, "NORMAL new game")

  for n = 1, 10 do
    local door_y = (n % 2 == 1) and 80 or 48
    wr16(PX, (6 * n - 3) * 16); wr(PY, door_y); frames(30)
    check(gate_tile(n) == 8, "gate " .. n .. " is open, tile=" .. gate_tile(n))
    if n < 10 then check(gate_tile(n + 1) == 7, "gate " .. (n + 1) .. " is still locked, tile=" .. gate_tile(n + 1)) end
    press({a = true}); frames(20)
    check(rd(STATE) == 3 and rd(CUR) == n, "dungeon " .. n .. " entered, state=" .. rd(STATE))
    check(wait_until(function() return rd(INTRO) == 0 end, 100), "intro " .. n .. " ends")
    wr(EHP, 1)                             -- boss pinned beside the player, sword held: a real hit kills it
    check(wait_until(function()
      wr(HEARTS, 3); wr(INV, 99); wr16(PX, 100); wr(PY, FLOOR_Y)
      wr(EX, 114); wr(EY, FLOOR_Y); wr(EFLASH, 0)
      held = {b = rd(0x300) % 2 == 0}      -- B needs a fresh press per swing
      return rd(DEAD) == 1
    end, 1500), "boss " .. n .. " killed")
    held = {}
    if n < 10 then
      check(wait_until(function() return rd(STATE) == 2 end, 300), "victory " .. n .. " returns to the overworld")
      check(rd16(MASK) == (1 << n) - 1, "mask after dungeon " .. n .. " = " .. rd16(MASK))
      check(rd(ABIL) == ABILS[n], "abilities after dungeon " .. n .. " = " .. rd(ABIL))
      save_ok((1 << n) - 1, ABILS[n], false)
      check(rd(ENDING) == 0, "no ending before dungeon 10")
    end
  end

  -- dungeon 10: ending screen first
  check(wait_until(function() return rd(STATE) == 4 end, 300), "ending screen after dungeon 10, state=" .. rd(STATE))
  check(rd(CUR) == 10, "still 'in' dungeon 10 for the way back")
  local function row(r, c, n)              -- n tile ids of nametable row r from column c
    local t = {}
    for i = 0, n - 1 do t[#t + 1] = ppu(0x2000 + r * 32 + c + i) end
    return table.concat(t, ",")
  end
  local BIG0, BIGSET = 157, "ACDEFGHILMNOPRSUY"          -- src/ui.h: big letter k = tiles BIG0 + 4k (TL TR BL BR)
  local top, bot = {}, {}
  for ch in ("YOU ESCAPED"):gmatch(".") do
    if ch == " " then top[#top + 1] = 0; bot[#bot + 1] = 0
    else
      local k = BIGSET:find(ch, 1, true) - 1
      top[#top + 1] = BIG0 + 4 * k; top[#top + 1] = BIG0 + 4 * k + 1
      bot[#bot + 1] = BIG0 + 4 * k + 2; bot[#bot + 1] = BIG0 + 4 * k + 3
    end
  end
  check(row(2, 5, 21) == table.concat(top, ",") and row(3, 5, 21) == table.concat(bot, ","), "big 'YOU ESCAPED' on screen: " .. row(2, 5, 21))
  check(row(22, 12, 7) == "34,39,30,0,30,28,26", "'THE END' on screen: " .. row(22, 12, 7))
  check(row(25, 7, 18) == "34,39,37,28,46,38,0,48,31,35,0,15,44,37,36,13,28,29", "'THANKS FOR PLAYING' on screen: " .. row(25, 7, 18))
  check(row(10, 0, 32) == string.rep("225,", 31) .. "225", "sky band tiles on row 10: " .. row(10, 0, 32))
  check(row(19, 15, 2) ~= "0,0" and row(20, 0, 32) == string.rep("0,", 31) .. "0", "sun on the horizon, ground black")
  check(rd16(MASK) == 1023 and rd(ENDING) == 1, "mask 1023, ending flag set")
  save_ok(1023, 31, true)
  for i = 0, 3 do check(rd(0x200 + 4 * i) ~= 0xFF and rd(0x201 + 4 * i) == i, "ending screen: hero sprite " .. i .. " shown") end
  for i = 4, 63 do check(rd(0x200 + 4 * i) == 0xFF, "ending screen: sprite " .. i .. " hidden") end
  press({start = true})
  check(rd(STATE) == 4, "Start is ignored during the first 2 seconds")
  check(wait_until(function() return rd(ENDT) < 120 end, 200), "end timer runs")
  frames(300)
  check(rd(STATE) == 4 and rd(ENDT) == 0, "no auto-return: the timer stops at 0")
  press({start = true})
  check(rd(STATE) == 2 and rd(CUR) == 0, "Start leaves the ending screen")
  check(rd16(0x303) == 912 and rd(PY) == 48, "back at door 10, free play")
  frames(20)
  check(gate_tile(10) == 8, "overworld redrawn")
  save_ok(1023, 31, true)

  -- reset + NORMAL keeps the flag
  emu.reset(); frames(30); held = {start = true}; frames(3); held = {}; frames(20); held = {start = true}; frames(3); held = {}; frames(60)
  check(rd16(MASK) == 1023 and rd(ENDING) == 1 and rd(ABIL) == 31, "reset loads everything incl. the ending flag")

  print("ending test OK")
  emu.stop(0)
end)

emu.addEventCallback(function() emu.setInput(held, 0, 0) end, emu.eventType.inputPolled)
emu.addEventCallback(function()
  if coroutine.status(co) == "dead" then return end
  local ok, err = coroutine.resume(co)
  if not ok then print("ERROR: " .. tostring(err)); emu.stop(1) end
end, emu.eventType.endFrame)
