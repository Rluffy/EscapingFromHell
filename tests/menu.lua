-- Title/menu/intro test: logo and entries, cursor (Up/Down/Select, wrap), CONTINUE only with a valid save (loads it, no intro),
-- NEW GAME = intro (A / timer / Start) then mask 0 with the old save kept, DELETE SAVE with confirmation, CHEAT = intro,
-- all gates open, hearts stay 3 on hits, nothing ever written to $6000, ending screen times out by itself.
-- Addresses, tiles and save layout: docs/TECH.md "Debug-Adressen", "Speicherstand", "Titel, Intro und Ende (v0.9)".
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
local INTRO, DEAD, ABIL = 0x31A, 0x319, 0x322
local ENDING, CHEAT, SEL = 0x333, 0x334, 0x335
local PAGE, TIMER, CONF = 0x33D, 0x33E, 0x33F
local SAVE = 0x6000
local FLOOR_Y = 176

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
local function row(r, c, n)                  -- n tile ids of nametable row r from column c
  local t = {}
  for i = 0, n - 1 do t[#t + 1] = ppu(0x2000 + r * 32 + c + i) end
  return table.concat(t, ",")
end
local function save_bytes()
  local t = {}
  for i = 0, 6 do t[#t + 1] = rd(SAVE + i) end
  return table.concat(t, ",")
end
local function write_save(lo, hi, ab)       -- valid save: 'E' 'H' 1 lo hi abilities checksum
  local b = {0x45, 0x48, 1, lo, hi, ab}
  local s = 0
  for i = 1, 6 do wr(SAVE + i - 1, b[i]); s = s + b[i] end
  wr(SAVE + 6, s % 256)
end
local function boot()                        -- reset (PRG-RAM stays), wait for the menu to be drawn
  emu.reset(); frames(30)
  check(rd(STATE) == 1, "reset shows the start menu, state=" .. rd(STATE))
end
local BIG0, BIGSET = 157, "ACDEFGHILMNOPRSUY"   -- src/ui.h: big letter k = tiles BIG0 + 4k (TL TR BL BR)
local function big(s, r, c)                  -- expected tiles of a big-letter line: top row (p = 0) or bottom row (p = 1)
  local t = {}
  for p = 0, 1 do
    local w = {}
    for ch in s:gmatch(".") do
      if ch == " " then w[#w + 1] = 0
      else local k = BIGSET:find(ch, 1, true) - 1; w[#w + 1] = BIG0 + 4 * k + 2 * p; w[#w + 1] = BIG0 + 4 * k + 2 * p + 1 end
    end
    t[#t + 1] = table.concat(w, ",")
  end
  return t
end
local function title_ok()                    -- the logo: ESCAPING on rows 3/4 (cols 8..23), FROM HELL on rows 6/7 (cols 7..23)
  local e, f = big("ESCAPING"), big("FROM HELL")
  check(row(3, 8, 16) == e[1] and row(4, 8, 16) == e[2], "logo ESCAPING, got " .. row(3, 8, 16))
  check(row(6, 7, 17) == f[1] and row(7, 7, 17) == f[2], "logo FROM HELL, got " .. row(6, 7, 17))
end
local function skip_intro()                  -- Start leaves the intro for the overworld
  press({start = true})
  check(wait_until(function() return rd(STATE) == 2 end, 10), "Start skips the intro")
  frames(40)
end
local function gate_tile(n)                  -- background tile at the gate of dungeon n
  local dr = (n % 2 == 1) and 5 or 3
  local col = (6 * n - 3) * 2
  return ppu(0x2000 + ((col // 32) % 2) * 0x400 + (dr + 1) * 2 * 32 + col % 32)
end
local function enter(n)                      -- onto door n, A, wait out arena build and intro
  wr16(PX, (6 * n - 3) * 16); wr(PY, (n % 2 == 1) and 80 or 48); frames(30)
  press({a = true}); frames(20)
  check(rd(STATE) == 3 and rd(CUR) == n, "dungeon " .. n .. " entered, state=" .. rd(STATE))
  check(wait_until(function() return rd(INTRO) == 0 end, 100), "intro ends")
end
local function kill()                        -- hp 1, boss pinned beside the player, sword held: until the boss is dead
  wr(EHP, 1)
  check(wait_until(function()
    wr(HEARTS, 3); wr(INV, 99); wr16(PX, 100); wr(PY, FLOOR_Y)
    wr(EX, 114); wr(EY, FLOOR_Y); wr(EFLASH, 0)
    held = {b = rd(0x300) % 2 == 0}      -- B needs a fresh press per swing
    return rd(DEAD) == 1
  end, 1500), "boss killed")
  held = {}
end

co = coroutine.create(function()
  for i = 0, 6 do wr(SAVE + i, 0) end
  frames(30)

  -- no save: title, NEW GAME and CHEAT only (no CONTINUE, no DELETE SAVE)
  check(rd(STATE) == 1 and rd(SEL) == 0 and rd(CONF) == 0, "boot shows the start menu, state=" .. rd(STATE))
  title_ok()
  check(row(12, 12, 8) == "28,30,47,0,29,37,14,30", "entry 'NEW GAME', got " .. row(12, 12, 8))
  check(row(14, 12, 5) == "33,39,30,37,34", "entry 'CHEAT', got " .. row(14, 12, 5))
  check(row(16, 12, 11) == "0,0,0,0,0,0,0,0,0,0,0" and row(18, 12, 11) == "0,0,0,0,0,0,0,0,0,0,0", "no CONTINUE / DELETE SAVE row")
  check(rd(0x200) == 12 * 8 - 1 and rd(0x203) == 80, "cursor beside NEW GAME, y=" .. rd(0x200))
  press({down = true}); frames(1)
  check(rd(SEL) == 1 and rd(0x200) == 14 * 8 - 1, "Down moves to CHEAT")
  press({up = true}); frames(1)
  check(rd(SEL) == 0, "Up moves back to NEW GAME")
  press({up = true})
  check(rd(SEL) == 1, "Up wraps to CHEAT")
  press({select = true})
  check(rd(SEL) == 0, "Select cycles (wraps to NEW GAME)")
  press({select = true})
  check(rd(STATE) == 1, "Select only moves the cursor")

  -- NEW GAME: intro (3 pages) then the overworld with nothing cleared
  boot()
  press({start = true}); frames(20)
  check(rd(STATE) == 5 and rd(CHEAT) == 0 and rd(PAGE) == 0, "NEW GAME starts the intro, state=" .. rd(STATE))
  check(row(7, 11, 9) == "36,31,27,0,37,47,37,46,30" and row(10, 12, 8) == "13,28,0,39,30,44,44,152", "intro page 1 text: " .. row(7, 11, 9) .. " / " .. row(10, 12, 8))
  press({a = true}); frames(20)
  check(rd(STATE) == 5 and rd(PAGE) == 1, "A turns the page, page=" .. rd(PAGE))
  check(row(7, 8, 16) == "34,30,28,0,26,30,14,31,28,38,0,29,27,37,35,26", "intro page 2 text: " .. row(7, 8, 16))
  wr(TIMER, 2); frames(20)                   -- the page times out by itself
  check(rd(STATE) == 5 and rd(PAGE) == 2, "page 2 auto-advances, page=" .. rd(PAGE))
  check(row(7, 10, 12) == "26,30,48,30,37,34,0,34,39,30,14,152", "intro page 3 text: " .. row(7, 10, 12))
  press({a = true})                          -- after the last page: overworld
  check(wait_until(function() return rd(STATE) == 2 end, 10), "A on the last page ends the intro")
  frames(40)
  check(rd16(MASK) == 0 and rd(ABIL) == 0 and rd(ENDING) == 0 and rd(CHEAT) == 0, "NEW GAME: mask 0, abilities 0")

  -- NEW GAME, Start skips the whole intro; an old save is not touched (only a later autosave overwrites it)
  write_save(3, 0x80, 1)
  local before = save_bytes()
  boot()
  press({down = true}); frames(1)
  check(rd(SEL) == 1, "with a save NEW GAME is the second entry")
  press({start = true}); frames(20)
  check(rd(STATE) == 5, "NEW GAME with a save starts the intro")
  skip_intro()
  check(rd16(MASK) == 0 and rd(ABIL) == 0 and rd(ENDING) == 0, "NEW GAME ignores the save, mask=" .. rd16(MASK))
  check(save_bytes() == before, "the old save stays until the first autosave: " .. save_bytes())

  -- CONTINUE (first entry with a valid save): saved mask, abilities and ending bit, no intro
  boot()
  title_ok()
  check(row(12, 12, 8) == "33,31,28,34,13,28,27,30", "entry 'CONTINUE', got " .. row(12, 12, 8))
  check(row(14, 12, 8) == "28,30,47,0,29,37,14,30", "entry 'NEW GAME' second, got " .. row(14, 12, 8))
  check(row(16, 12, 5) == "33,39,30,37,34", "entry 'CHEAT' third, got " .. row(16, 12, 5))
  check(row(18, 12, 11) == "26,30,44,30,34,30,0,38,37,32,30", "entry 'DELETE SAVE' fourth, got " .. row(18, 12, 11))
  check(rd(SEL) == 0 and rd(0x200) == 12 * 8 - 1, "cursor on CONTINUE")
  press({start = true})
  check(wait_until(function() return rd(STATE) ~= 1 end, 10) and rd(STATE) == 2, "CONTINUE goes straight to the overworld (no intro), state=" .. rd(STATE))
  frames(40)
  check(rd(CHEAT) == 0 and rd16(MASK) == 3 and rd(ABIL) == 1 and rd(ENDING) == 1, "CONTINUE loads the save, mask=" .. rd16(MASK))
  wr16(PX, (6 * 3 - 3) * 16); wr(PY, 80); frames(30)
  check(gate_tile(3) == 8 and gate_tile(4) == 7, "gate 3 open, gate 4 locked")

  -- an old version-1 save without the ending bit, and A as the confirm key
  write_save(3, 0, 1)
  boot()
  press({a = true}); frames(40)
  check(rd(STATE) == 2 and rd16(MASK) == 3 and rd(ENDING) == 0, "A confirms; save without the ending bit loads")

  -- a damaged save counts as no save: CONTINUE is hidden
  write_save(3, 0, 1); wr(SAVE + 6, 0)
  boot()
  check(row(12, 12, 8) == "28,30,47,0,29,37,14,30", "bad checksum: no CONTINUE, got " .. row(12, 12, 8))

  -- DELETE SAVE asks first: B cancels, A deletes
  write_save(3, 0, 1)
  before = save_bytes()
  boot()
  press({down = true}); press({down = true}); press({down = true}); frames(1)
  check(rd(SEL) == 3 and rd(0x200) == 18 * 8 - 1, "cursor on DELETE SAVE")
  press({start = true}); frames(30)
  check(rd(STATE) == 1 and rd(CONF) == 1, "DELETE SAVE asks for confirmation")
  check(row(14, 10, 12) == "26,30,44,30,34,30,0,38,37,32,30,154", "question 'DELETE SAVE?', got " .. row(14, 10, 12))
  check(row(17, 10, 12) == "37,0,36,30,38,0,0,0,43,0,28,31", "hint 'A YES   B NO', got " .. row(17, 10, 12))
  check(row(12, 12, 8) == "0,0,0,0,0,0,0,0" and rd(0x200) == 0xFF, "entries and cursor are gone while asking")
  press({down = true}); press({start = true}); press({select = true}); frames(1)
  check(rd(CONF) == 1 and save_bytes() == before, "other keys do nothing while asking")
  press({b = true}); frames(30)
  check(rd(CONF) == 0 and rd(STATE) == 1 and rd(SEL) == 3 and save_bytes() == before, "B cancels, save kept")
  check(row(12, 12, 8) == "33,31,28,34,13,28,27,30", "CONTINUE still listed")
  press({start = true}); frames(30)
  check(rd(CONF) == 1, "asking again")
  press({a = true}); frames(30)
  check(rd(CONF) == 0 and rd(STATE) == 1 and rd(SEL) == 0, "A deletes and returns to the menu")
  check(save_bytes() == "0,0,0,0,0,0,0", "save is cleared: " .. save_bytes())
  check(row(12, 12, 8) == "28,30,47,0,29,37,14,30" and row(16, 12, 11) == "0,0,0,0,0,0,0,0,0,0,0", "CONTINUE and DELETE SAVE are gone")
  boot()
  check(row(12, 12, 8) == "28,30,47,0,29,37,14,30", "still no CONTINUE after a reset")

  -- CHEAT (third entry with a save): intro, then every gate open, nothing granted or lost, nothing saved
  write_save(3, 0, 1)
  before = save_bytes()
  boot()
  press({down = true}); press({down = true})
  check(rd(SEL) == 2, "cursor on CHEAT")
  press({a = true}); frames(20)
  check(rd(STATE) == 5 and rd(CHEAT) == 1, "CHEAT shows the intro too")
  skip_intro()
  check(rd(STATE) == 2 and rd(CHEAT) == 1, "CHEAT starts the overworld")
  check(rd16(MASK) == 1023 and rd(ABIL) == 0, "CHEAT: all dungeons open, abilities start empty, mask=" .. rd16(MASK))
  wr16(PX, (6 * 10 - 3) * 16); wr(PY, 48 + 32); frames(30)
  check(gate_tile(10) == 8, "gate 10 drawn open")
  enter(10)                                -- straight to the last dungeon
  press({start = true}); press({select = true})
  check(rd(STATE) == 2, "gave up dungeon 10 (no ending screen)")
  enter(1)
  for i = 1, 4 do                          -- the boss on top of the player: a hit each time, hearts stay 3
    wr(INV, 0); wr16(PX, 100); wr(PY, FLOOR_Y); wr(EX, 100); wr(EY, FLOOR_Y)
    frames(2)
    check(rd(INV) > 0 and rd(HEARTS) == 3, "hit " .. i .. ": knockback/flash but hearts=" .. rd(HEARTS))
  end
  kill()
  check(wait_until(function() return rd(STATE) == 2 end, 300), "victory over the Imp returns to the overworld")
  check(rd(ABIL) == 1 and rd16(MASK) == 1023, "abilities are earned in RAM, abilities=" .. rd(ABIL))
  check(save_bytes() == before, "cheat victory left the save untouched: " .. save_bytes())
  enter(10)                                -- last demon in cheat: ending screen, times out without Start
  kill()
  check(wait_until(function() return rd(STATE) == 4 end, 300), "ending screen after the last demon")
  check(wait_until(function() return rd(STATE) == 2 end, 400), "ending screen leaves by itself")
  check(save_bytes() == before, "cheat ending left the save untouched: " .. save_bytes())

  -- CONTINUE after the cheat session: progress untouched
  boot()
  press({start = true}); frames(60)
  check(rd(CHEAT) == 0 and rd16(MASK) == 3 and rd(ABIL) == 1, "normal progress untouched, mask=" .. rd16(MASK))

  print("menu test OK")
  emu.stop(0)
end)

emu.addEventCallback(function() emu.setInput(held, 0, 0) end, emu.eventType.inputPolled)
emu.addEventCallback(function()
  if coroutine.status(co) == "dead" then return end
  local ok, err = coroutine.resume(co)
  if not ok then print("ERROR: " .. tostring(err)); emu.stop(1) end
end, emu.eventType.endFrame)
