-- Progress test: pause+Select exit, Dash lock/use/cooldown, Double jump, Imp victory flow, autosave at $6000, boot load / corrupt save.
-- Addresses and save layout: docs/TECH.md "Debug-Adressen", "Speicherstand".
local M = emu.memType.nesMemory
local held = {}
local function rd(a) return emu.read(a, M) end
local function rd16(a) return rd(a) + 256 * rd(a + 1) end
local function wr(a, v) emu.write(a, v, M) end
local function wr16(a, v) wr(a, v % 256); wr(a + 1, v // 256) end
local STATE, PX, PY, CUR, MASK = 0x302, 0x303, 0x305, 0x30A, 0x308
local HEARTS, INV, PAUSED = 0x30B, 0x30C, 0x317
local EX, EY, EHP, EFLASH = 0x310, 0x311, 0x314, 0x315
local INTRO, DEAD = 0x31A, 0x319
local ABIL, DASH, DCD, VICT = 0x322, 0x323, 0x324, 0x325
local VY = 0x30F
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
local function ppu(a) return emu.read(a, emu.memType.nesPpuMemory) end
local function enter1()                     -- from the overworld onto door 1, A, wait out arena build and boss intro
  wr16(PX, 48); wr(PY, 80); frames(30)
  press({a = true}); frames(20)
  check(rd(STATE) == 3 and rd(CUR) == 1, "dungeon 1 entered")
  check(wait_until(function() return rd(INTRO) == 0 end, 100), "intro ends")
end
local function gate2_tile()                 -- gate of dungeon 2: col 9, row 3 -> tile col 18, tile row 8
  return ppu(0x2000 + 8 * 32 + 18)
end
local function boot()                        -- reset the console, PRG-RAM stays
  emu.reset(); frames(30); held = {start = true}; frames(3); held = {}; frames(20); held = {start = true}; frames(3); held = {}; frames(60)   -- boot menu: Start = NEW GAME (CONTINUE with a save), second Start skips the intro
  check(rd(STATE) == 2, "boot reaches overworld after reset")
end

co = coroutine.create(function()
  -- fresh start: no save
  for i = 0, 6 do wr(SAVE + i, 0) end
  boot()
  check(rd16(MASK) == 0 and rd(ABIL) == 0, "new game: mask 0, abilities 0")

  -- Select without Start does not leave; without the Dash ability it does nothing at all
  enter1()
  local x0 = rd16(PX)
  press({select = true})
  check(rd(STATE) == 3 and rd16(PX) == x0 and rd(DASH) == 0, "Select unpaused: no exit, no dash without the ability")
  -- Start, then Select leaves at the door
  press({start = true})
  check(rd(PAUSED) == 1, "Start pauses")
  press({select = true})
  check(rd(STATE) == 2 and rd(CUR) == 0 and rd16(PX) == 48 and rd(PY) == 80, "pause + Select back at door 1")
  check(rd16(MASK) == 0 and rd(SAVE) == 0, "giving up changes nothing and saves nothing")

  -- victory over the Imp: hp 1, one hit
  enter1()
  wr(EX, 112); wr(EY, FLOOR_Y); wr(EHP, 1); wr(EFLASH, 0)
  wr16(PX, 98); wr(PY, FLOOR_Y); wr(HEARTS, 3); wr(INV, 0)
  frames(1)
  wr(EX, 112); hold({b = true}, 3)
  frames(5)
  check(rd(EHP) == 0 and rd(DEAD) == 1 and rd(VICT) > 100, "Imp dead, victory running, victory=" .. rd(VICT))
  check(rd(STATE) == 3 and rd16(MASK) == 0, "victory screen first: still in the dungeon, nothing cleared yet")
  check(ppu(0x2000 + 10 * 32 + 12) == 32 and ppu(0x2000 + 10 * 32 + 18) == 36, "'VICTORY' on screen")
  check(ppu(0x2000 + 13 * 32 + 12) == 29 and ppu(0x2000 + 13 * 32 + 19) == 39, "'GOT DASH' on screen")
  hold({start = true, a = true}, 3)       -- input is ignored during the victory screen
  check(rd(PAUSED) == 0, "victory ignores Start")
  check(wait_until(function() return rd(STATE) == 2 end, 200), "victory ends in the overworld")
  check(rd(CUR) == 0 and rd16(PX) == 48 and rd(PY) == 80, "back at door 1")
  check(rd16(MASK) == 1 and rd(ABIL) == 1, "dungeon 1 cleared, Dash granted")
  frames(10)
  check(gate2_tile() == 8, "gate 2 open, tile=" .. gate2_tile())
  check(rd(SAVE) == 0x45 and rd(SAVE + 1) == 0x48 and rd(SAVE + 2) == 1 and rd(SAVE + 3) == 1 and rd(SAVE + 4) == 0
        and rd(SAVE + 5) == 1 and rd(SAVE + 6) == 0x90, "autosave bytes valid")

  -- boot load: valid save restores progress, a corrupt checksum is a new game
  boot()
  check(rd16(MASK) == 1 and rd(ABIL) == 1, "reset loads the save, mask=" .. rd16(MASK))
  wr(SAVE + 6, (rd(SAVE + 6) + 1) % 256)
  boot()
  check(rd16(MASK) == 0 and rd(ABIL) == 0, "bad checksum = new game")

  -- Dash (ability written directly: the new game has none)
  wr(ABIL, 1)
  enter1()
  wr(HEARTS, 3); wr(INV, 0); wr16(PX, 48); wr(PY, FLOOR_Y); wr(EX, 200)
  frames(2)
  x0 = rd16(PX)
  hold({}, 1); held = {select = true}; frames(1); held = {}
  frames(1)
  check(rd(DASH) > 0 and rd(INV) > 0 and rd(DCD) > 0, "dash started: timer, invulnerable, cooldown")
  frames(12)
  check(rd16(PX) - x0 >= 36 and rd(DASH) == 0, "dash covers ~40 px (walking: 24), dx=" .. (rd16(PX) - x0))
  x0 = rd16(PX)
  check(rd(DCD) > 0, "cooldown still running")
  press({select = true})
  check(rd16(PX) == x0 and rd(DASH) == 0, "second dash blocked by the cooldown")
  check(wait_until(function() return rd(DCD) == 0 end, 40), "cooldown ends")
  wr(HEARTS, 3); wr(INV, 0)
  hold({left = true}, 2)                  -- face left
  x0 = rd16(PX)
  held = {select = true}; frames(1); held = {}
  frames(12)
  check(x0 - rd16(PX) >= 36, "dash to the left works again, dx=" .. (x0 - rd16(PX)))

  -- Double jump: a second A in the air jumps again (once per airtime), only with the ability bit; Dash still works
  local function signed(v) return v >= 128 and v - 256 or v end
  local function jump_and_air_a(ability)
    wr(ABIL, ability)
    wr(HEARTS, 3); wr(INV, 99); wr16(PX, 100); wr(PY, FLOOR_Y); wr(VY, 0); wr(EX, 200); wr(EY, FLOOR_Y)
    frames(3)
    held = {a = true}; frames(12)         -- full jump, hold A while rising
    held = {}
    check(wait_until(function() wr(INV, 99); return signed(rd(VY)) >= 0 end, 40), "first jump reaches its apex")
    local apex = rd(PY)
    held = {a = true}; frames(2)          -- second A in the air, still held (a tap cuts the jump short)
    return apex
  end
  local apex = jump_and_air_a(1)          -- Dash only
  check(signed(rd(VY)) >= 0 and rd(PY) >= apex, "no Double jump without the ability, vy=" .. signed(rd(VY)))
  held = {}
  check(wait_until(function() wr(INV, 99); return rd(PY) == FLOOR_Y end, 60), "lands")
  apex = jump_and_air_a(3)                -- Dash + Double jump
  check(signed(rd(VY)) < 0 and rd(PY) < apex, "second A in the air jumps again, vy=" .. signed(rd(VY)))
  frames(6); held = {}
  local top = rd(PY)
  check(top < apex - 15, "second jump adds height, " .. apex .. " -> " .. top)
  check(wait_until(function() wr(INV, 99); return signed(rd(VY)) >= 0 end, 40), "second jump reaches its apex")
  held = {a = true}; frames(2); held = {}   -- third A: only one air jump per airtime
  check(signed(rd(VY)) >= 0, "no third jump in the same airtime, vy=" .. signed(rd(VY)))
  wr(INV, 99); held = {select = true}; frames(1); held = {}; frames(1)
  check(rd(DASH) > 0, "Dash still works in the air after a double jump")
  check(wait_until(function() wr(INV, 99); return rd(0x30D) == 1 end, 80), "lands again (the dash may end on a platform)")
  held = {a = true}; frames(2); held = {}
  check(signed(rd(VY)) < 0, "landing resets: the next jump works, vy=" .. signed(rd(VY)))

  print("progress test OK")
  emu.stop(0)
end)

emu.addEventCallback(function() emu.setInput(held, 0, 0) end, emu.eventType.inputPolled)
emu.addEventCallback(function()
  if coroutine.status(co) == "dead" then return end
  local ok, err = coroutine.resume(co)
  if not ok then print("ERROR: " .. tostring(err)); emu.stop(1) end
end, emu.eventType.endFrame)
