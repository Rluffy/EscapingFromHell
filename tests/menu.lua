-- Start menu test: boot state and text, cursor (Up/Down/Select, wrap), NORMAL loads the save (incl. the ending bit),
-- CHEAT = all gates open, hearts stay 3 on hits, nothing ever written to $6000, ending screen times out by itself.
-- Addresses and save layout: docs/TECH.md "Debug-Adressen", "Speicherstand", "Startmenü und Ende (v0.8)".
local M = emu.memType.nesMemory
local held = {}
local function rd(a) return emu.read(a, M) end
local function rd16(a) return rd(a) + 256 * rd(a + 1) end
local function wr(a, v) emu.write(a, v, M) end
local function wr16(a, v) wr(a, v % 256); wr(a + 1, v // 256) end
local function ppu(a) return emu.read(a, emu.memType.nesPpuMemory) end
local STATE, PX, PY, MASK, CUR = 0x302, 0x303, 0x305, 0x308, 0x30A
local HEARTS, INV = 0x30B, 0x30C
local EX, EY, EHP, EFLASH = 0x310, 0x311, 0x314, 0x315
local INTRO, DEAD, ABIL = 0x31A, 0x319, 0x322
local ENDING, CHEAT, SEL = 0x333, 0x334, 0x335
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
local function boot()                        -- reset (PRG-RAM stays), wait for the menu
  emu.reset(); frames(20)
  check(rd(STATE) == 1, "reset shows the start menu, state=" .. rd(STATE))
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
  frames(20)
  check(rd(STATE) == 1 and rd(SEL) == 0, "boot shows the start menu, state=" .. rd(STATE))
  check(row(6, 12, 8) == "30,38,33,37,15,13,28,29", "title 'ESCAPING', got " .. row(6, 12, 8))
  check(row(8, 11, 9) == "48,35,31,14,0,39,30,44,44", "title 'FROM HELL', got " .. row(8, 11, 9))
  check(row(14, 13, 6) == "28,31,35,14,37,44", "entry 'NORMAL', got " .. row(14, 13, 6))
  check(row(16, 13, 5) == "33,39,30,37,34", "entry 'CHEAT', got " .. row(16, 13, 5))
  check(rd(0x200) == 14 * 8 - 1 and rd(0x203) == 88, "cursor beside NORMAL, y=" .. rd(0x200))
  press({down = true}); frames(1)
  check(rd(SEL) == 1 and rd(0x200) == 16 * 8 - 1, "Down moves to CHEAT")
  press({up = true}); frames(1)
  check(rd(SEL) == 0, "Up moves back to NORMAL")
  press({up = true})
  check(rd(SEL) == 1, "Up wraps to CHEAT")
  press({select = true})
  check(rd(SEL) == 0, "Select cycles (wraps to NORMAL)")
  press({select = true})
  check(rd(STATE) == 1, "Select only moves the cursor")

  -- NORMAL loads the save: dungeons 1+2, Dash, ending seen
  write_save(3, 0x80, 1)
  boot()
  press({start = true}); frames(60)
  check(rd(STATE) == 2 and rd(CHEAT) == 0, "NORMAL starts the overworld")
  check(rd16(MASK) == 3 and rd(ABIL) == 1 and rd(ENDING) == 1, "NORMAL loads the save, mask=" .. rd16(MASK))
  wr16(PX, (6 * 3 - 3) * 16); wr(PY, 80); frames(30)
  check(gate_tile(3) == 8 and gate_tile(4) == 7, "gate 3 open, gate 4 locked")

  -- NORMAL with an old version-1 save without the ending bit, and with A as the confirm key
  write_save(3, 0, 1)
  boot()
  press({a = true}); frames(60)
  check(rd(STATE) == 2 and rd16(MASK) == 3 and rd(ENDING) == 0, "A confirms; save without the ending bit loads")

  -- CHEAT: every gate open, nothing granted or lost, nothing saved
  write_save(3, 0, 1)
  local before = save_bytes()
  boot()
  press({down = true})
  press({a = true}); frames(60)
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

  -- NORMAL after the cheat session: progress untouched
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
