-- CHR/PRG banking test: UI bank in menu/overworld, overworld animation hook (R1 toggles), per-dungeon boss CHR bank (R3..R5),
-- checked through the PPU's view of CHR against CHR-ROM. Layout: docs/TECH.md "CHR-Layout".
local M, P, C = emu.memType.nesMemory, emu.memType.nesPpuMemory, emu.memType.nesChrRom
local held = {}
local function rd(a) return emu.read(a, M) end
local function wr(a, v) emu.write(a, v, M) end
local function wr16(a, v) wr(a, v % 256); wr(a + 1, v // 256) end
local STATE, PX, PY, CUR, BANK, BCHR, ANIM = 0x302, 0x303, 0x305, 0x30A, 0x326, 0x337, 0x338

local co
local function frames(n) for _ = 1, n do coroutine.yield() end end
local function hold(keys, n) held = keys; frames(n); held = {} end
local function check(cond, msg)
  if not cond then print("FAIL: " .. msg); emu.stop(1); coroutine.yield() end
end
-- PPU address a..a+15 shows the CHR-ROM bytes of 1 KB bank number kb at offset off
local function same(a, kb, off)
  for i = 0, 15 do if emu.read(a + i, P) ~= emu.read(kb * 1024 + off + i, C) then return false end end
  return true
end
local function nonblank(a)                   -- first 64 tiles of the 1 KB window at a
  for i = 0, 1023 do if emu.read(a + i, P) ~= 0 then return true end end
  return false
end

co = coroutine.create(function()
  frames(10); held = {down = true}; frames(3); held = {}; frames(5)
  hold({start = true}, 3); frames(60)       -- menu: CHEAT, all gates open
  check(rd(STATE) == 2 and rd(BANK) == 10 and rd(0x8000) ~= 0, "overworld: UI bank 10 mapped, cur_bank=" .. rd(BANK))

  -- overworld animation hook: R1 flips between frame A (bank 2) and B (bank 4); tile 255 is the marker
  local seen = {}
  for _ = 1, 100 do
    frames(1)
    local b = rd(ANIM)
    check(b == 2 or b == 4, "anim_bank is a frame bank, got " .. b)
    seen[b] = (seen[b] or 0) + 1
    check(same(0x0FF0, b, 0x7F0), "R1 shows bank " .. b)
  end
  check(seen[2] and seen[4], "overworld animation toggles between both frames")
  check(not same(0x0FF0, 4, 0x7F0) or not same(0x0FF0, 2, 0x7F0), "the two frames differ")
  check(same(0x0000, 0, 0) and same(0x1000, 6, 0), "R0 = background bank 0, R2 = common sprites bank 6")

  -- every dungeon maps its boss sheet into R3..R5
  for n = 1, 10 do
    wr16(PX, (6 * n - 3) * 16); wr(PY, n % 2 == 1 and 80 or 48); frames(30)
    hold({a = true}, 3); frames(20)
    check(rd(STATE) == 3 and rd(CUR) == n, "dungeon " .. n .. " entered")
    local kb = 8 + 4 * (n - 1)
    check(rd(BCHR) == kb, "dungeon " .. n .. ": boss_chr " .. rd(BCHR) .. " expected " .. kb)
    check(rd(BANK) == n - 1, "dungeon " .. n .. ": boss PRG bank " .. rd(BANK))
    check(same(0x1400, kb, 0) and same(0x1800, kb + 1, 0) and same(0x1C00, kb + 2, 0), "dungeon " .. n .. ": R3..R5 = boss sheet")
    check(nonblank(0x1400), "dungeon " .. n .. ": boss sheet is not empty")
    check(same(0x1000, 6, 0) and same(0x0000, 0, 0), "dungeon " .. n .. ": common sprites and font stay")
    hold({start = true}, 3); frames(5); hold({select = true}, 3); frames(30)   -- pause, give up
    check(rd(STATE) == 2 and rd(BANK) == 10, "dungeon " .. n .. " left, UI bank back")
  end
  print("chr test OK")
  emu.stop(0)
end)

emu.addEventCallback(function() emu.setInput(held, 0, 0) end, emu.eventType.inputPolled)
emu.addEventCallback(function()
  if coroutine.status(co) == "dead" then return end
  local ok, err = coroutine.resume(co)
  if not ok then print("ERROR: " .. tostring(err)); emu.stop(1) end
end, emu.eventType.endFrame)
