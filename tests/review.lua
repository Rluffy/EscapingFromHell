-- v1.0 review (docs/TECH.md "Fehlersuche v1.0"): overworld bounds (long walk, every frame checked), spawn at all 10 doors and re-entry,
-- pause (intro and fight clock stand still), the restart at 0 hearts resets all state for every boss, victory hides every boss sprite,
-- the autosave (checksum, ending bit, no GOT text for a known ability, PRG-RAM write-protected), ending replay, shield/dash combos.
-- Addresses: docs/TECH.md "Debug-Adressen".
local M = emu.memType.nesMemory
local held = {}
local function rd(a) return emu.read(a, M) end
local function rd16(a) return rd(a) + 256 * rd(a + 1) end
local function wr(a, v) emu.write(a, v, M) end
local function wr16(a, v) wr(a, v % 256); wr(a + 1, v // 256) end
local function ppu(a) return emu.read(a, emu.memType.nesPpuMemory) end
local STATE, PX, PY, CAM, MASK, CUR = 0x302, 0x303, 0x305, 0x306, 0x308, 0x30A
local HEARTS, INV, SWORD, PAUSED = 0x30B, 0x30C, 0x30E, 0x317
local EX, EY, EHP, PHASE, DEAD, INTRO, FBX = 0x310, 0x311, 0x314, 0x318, 0x319, 0x31A, 0x31B
local ABIL, DASH, VICT, HIDE, PFX, SHIELD, SLOW, TLEN, FTICK = 0x322, 0x323, 0x325, 0x327, 0x329, 0x331, 0x332, 0x330, 0x342
local SAVE = 0x6000
local MAXHP = {10, 11, 12, 12, 13, 13, 14, 14, 20, 26}

local co
local function frames(n) for _ = 1, n do coroutine.yield() end end
local function hold(keys, n) held = keys; frames(n); held = {} end
local function press(keys) hold(keys, 3); frames(5) end
local function check(cond, msg)
  if not cond then print("FAIL: " .. msg); emu.stop(1); coroutine.yield() end
end
local function wait_until(f, max) for _ = 1, max do if f() then return true end frames(1) end return f() end
local function door(n) return (6 * n - 3) * 16, (n % 2 == 1) and 80 or 48 end
local function enter(n)
  local x, y = door(n)
  wr16(PX, x); wr(PY, y); frames(25)
  press({a = true})
  check(wait_until(function() return rd(STATE) == 3 and rd(INTRO) == 0 end, 300), "dungeon " .. n .. ": fight started")
end
local function leave()
  press({start = true}); press({select = true})
  check(wait_until(function() return rd(STATE) == 2 end, 60), "back in the overworld")
end
local function save_ok()                         -- 'E' 'H' 1 lo hi ab sum: the sum is the last byte
  local s = 0
  for i = 0, 5 do s = (s + rd(SAVE + i)) % 256 end
  return rd(SAVE) == 0x45 and rd(SAVE + 1) == 0x48 and rd(SAVE + 2) == 1 and rd(SAVE + 6) == s
end
local function visible(a) return rd(a) < 0xEF end

co = coroutine.create(function()
  frames(30); press({start = true}); frames(15); press({start = true}); frames(60)       -- NEW GAME, skip the intro
  check(rd(STATE) == 2, "boot reaches the overworld")

  -- PRG-RAM: write-protected outside save_game (MMC3 $A001 = $C0)
  wr(SAVE, 0x45)
  check(rd(SAVE) ~= 0x45, "PRG-RAM is write-protected at boot")

  -- overworld: 3000 frames of walking in all 8 directions from several starts; the position never leaves the walkable map
  wr16(MASK, 1023)
  local dirs = {{right = true}, {left = true}, {down = true}, {up = true}, {right = true, up = true}, {left = true, down = true},
                {right = true, down = true}, {left = true, up = true}}
  local starts = {{100, 160}, {900, 160}, {500, 144}, {40, 100}, {980, 200}, {300, 200}}
  local minx, maxx, miny, maxy, maxcam = 9999, 0, 999, 0, 0
  for i = 1, 3000 do
    if (i - 1) % 500 == 0 then local s = starts[(i - 1) // 500 + 1]; wr16(PX, s[1]); wr(PY, s[2]); frames(5) end
    held = dirs[(i // 37) % 8 + 1]
    frames(1)
    local x, y, c = rd16(PX), rd(PY), rd16(CAM)
    minx, maxx, miny, maxy, maxcam = math.min(minx, x), math.max(maxx, x), math.min(miny, y), math.max(maxy, y), math.max(maxcam, c)
    check(x >= 12 and x <= 996 and y >= 6 and y <= 208 and c <= 768, string.format("walk: out of bounds x=%d y=%d cam=%d", x, y, c))
    check(rd(0x203) == (x - c) % 256 and rd(0x200) == y - 1, "walk: sprite follows the player")
  end
  held = {}
  wr16(PX, 100); wr(PY, 160); frames(5); hold({left = true}, 300); check(rd16(PX) <= 14 and rd16(CAM) == 0, "left end: x=" .. rd16(PX) .. " cam=" .. rd16(CAM))
  wr16(PX, 900); wr(PY, 160); frames(5); hold({right = true}, 300)
  check(rd16(PX) >= 994 and rd16(PX) <= 996 and rd16(CAM) == 768, "right end: x=" .. rd16(PX) .. " cam=" .. rd16(CAM))
  print(string.format("walk: x %d..%d, y %d..%d, cam max %d", minx, maxx, miny, maxy, maxcam))

  -- every door: A enters, give up returns onto the door, A enters again
  for n = 1, 10 do
    local x, y = door(n)
    enter(n); check(rd(CUR) == n, "door " .. n .. ": dungeon " .. rd(CUR))
    leave()
    check(rd16(PX) == x and rd(PY) == y, string.format("door %d: spawn %d/%d, want %d/%d", n, rd16(PX), rd(PY), x, y))
    press({a = true}); frames(20)
    check(rd(STATE) == 3 and rd(CUR) == n, "door " .. n .. ": A on the spawn enters again")
    leave()
  end

  -- pause: Start freezes the intro and the fight clock
  wr16(PX, 48); wr(PY, 80); frames(25); press({a = true}); frames(10)
  local i0 = rd(INTRO); check(i0 > 0 and rd(FTICK) == 0, "intro running, ftick 0")
  press({start = true}); local i1 = rd(INTRO); frames(20)
  check(rd(PAUSED) == 1 and rd(INTRO) == i1 and rd(FTICK) == 0, "intro frozen by pause, intro=" .. rd(INTRO))
  press({start = true}); frames(5)
  check(rd(PAUSED) == 0 and rd(INTRO) < i1, "intro runs again")
  check(wait_until(function() return rd(INTRO) == 0 end, 200), "intro ends")
  frames(10)
  check(rd(PAUSED) == 0 and rd(FTICK) > 0, "the fight starts unpaused")
  press({start = true}); local f1 = rd(FTICK); frames(40)
  check(rd(PAUSED) == 1 and rd(FTICK) == f1, "fight clock stands still while paused")
  press({start = true}); frames(5)
  check(rd(FTICK) > f1, "fight clock runs again")

  -- the first picture after a screen change shows the new sprites (OAM DMA before rendering starts), not the stale ones of the old screen
  wr16(PX, 48); wr(PY, 80); frames(25); press({a = true}); frames(5)
  check(wait_until(function() return rd(STATE) == 3 and rd(INTRO) == 0 end, 300), "dungeon 1 for the OAM check")
  wr(0x328, 0); frames(2)
  press({start = true}); hold({select = true}, 2)
  local first = nil
  for _ = 1, 30 do
    frames(1)
    if rd(STATE) == 2 and emu.getState()["ppu.mask.backgroundEnabled"] then first = true; break end
  end
  check(first, "overworld picture after leaving the dungeon")
  for i = 0, 255 do                                -- attribute bytes read back without bits 2..4
    local want = i % 4 == 2 and rd(0x200 + i) & 0xE3 or rd(0x200 + i)
    check(emu.read(i, emu.memType.nesSpriteRam) == want, string.format("first overworld picture: OAM byte %d is stale (%d, want %d)", i,
      emu.read(i, emu.memType.nesSpriteRam), want))
  end
  check(rd(0x200) == rd(PY) - 1, "first overworld picture: the hero is in place")
  wr16(PX, 48); wr(PY, 80); frames(25)             -- the dungeon: the same on the way in
  press({a = true})
  first = nil
  for _ = 1, 30 do
    frames(1)
    if rd(STATE) == 3 and emu.getState()["ppu.mask.backgroundEnabled"] then first = true; break end
  end
  check(first, "dungeon picture")
  check(emu.read(0, emu.memType.nesSpriteRam) == rd(PY) - 1, "first dungeon picture: the hero is in place")
  for i = 40, 51 do
    check(emu.read(i, emu.memType.nesSpriteRam) == (i % 4 == 2 and rd(0x200 + i) & 0xE3 or rd(0x200 + i)), "first dungeon picture: hearts are in place")
  end
  check(wait_until(function() return rd(INTRO) == 0 end, 300), "intro ends")

  -- shield / dash combos (abilities 31)
  wr(0x343, 31); wr(HEARTS, 3); wr(INV, 99); wr16(PX, 100); wr(PY, 176)
  hold({down = true}, 8); check(rd(SHIELD) == 1, "shield up with Down")
  held = {down = true}; frames(1); held = {down = true, select = true}; frames(2); held = {down = true}
  check(rd(DASH) > 0 and rd(SHIELD) == 0, "dash drops the shield")
  frames(15); check(rd(DASH) == 0 and rd(SHIELD) == 1, "shield again after the dash")
  hold({down = true, b = true}, 5); check(rd(SWORD) == 0, "no sword swing behind the shield")
  held = {}; frames(5)
  hold({a = true}, 3); frames(3); hold({a = true}, 2)
  held = {select = true, a = true}; frames(3); held = {}
  check(rd16(PX) >= 16 and rd16(PX) <= 224 and rd(PY) <= 176, "jump + dash stay inside the arena")
  leave()

  -- all bosses: the restart at 0 hearts resets everything; the victory hides the boss; the save; the arena stays inside
  local acc = 0                                -- abilities earned so far
  for n = 1, 10 do
    wr(ABIL, acc)
    enter(n)
    wr(0x343, 31)
    -- arena invariants under a busy input pattern
    local pat = {{right = true, b = true}, {left = true, b = true}, {up = true, b = true}, {down = true}, {right = true, a = true},
                 {select = true, right = true}, {left = true, a = true, b = true}, {right = true}}
    for i = 1, 300 do
      wr(HEARTS, 3); wr(INV, 99); wr(EHP, MAXHP[n]); held = pat[(i // 20) % 8 + 1]; frames(1)
      local px, py, ex, ey = rd16(PX), rd(PY), rd(EX), rd(EY)
      check(px >= 16 and px <= 224 and py <= 176, string.format("boss %d: player outside the arena %d/%d", n, px, py))
      check(ex >= 8 and ex <= 240 and ey >= 16 and ey <= 200, string.format("boss %d: boss outside the arena %d/%d", n, ex, ey))
      check(not visible(0x200 + 212) and not visible(0x200 + 240) and not visible(0x200 + 252), "boss " .. n .. ": unused sprites stay hidden")
    end
    held = {}
    -- restart: dirty state, then the last heart goes
    local done = false
    for i = 1, 900 do
      wr(HEARTS, 1); wr(INV, 0); wr(EHP, MAXHP[n]); wr(PHASE, 1); wr(SLOW, 60); wr(PFX, 40); wr(0x32A, 20); wr(DASH, 5); if n == 7 then wr(TLEN, 2) end
      for k = 0, 2 do wr(FBX + k, 120) end
      wr16(PX, rd(EX)); wr(PY, rd(EY)); frames(1)
      if rd(HEARTS) == 3 then done = true; break end
    end
    check(done, "boss " .. n .. ": no restart")
    check(rd(SLOW) == 0 and rd(PFX) == 0 and rd(DASH) == 0 and rd(PHASE) == 1 and rd(EHP) == MAXHP[n] and rd(VICT) == 0
          and rd(INV) == 0 and rd(PAUSED) == 0, string.format("boss %d: restart left state: slow %d pf %d dash %d phase %d hp %d", n,
          rd(SLOW), rd(PFX), rd(DASH), rd(PHASE), rd(EHP)))
    check(rd(FBX) == 0 and rd(FBX + 1) == 0 and rd(FBX + 2) == 0, "boss " .. n .. ": fireballs survived the restart")
    check(rd(FTICK) < 3, "boss " .. n .. ": fight clock after the restart: " .. rd(FTICK))
    frames(2)
    check(n ~= 7 or rd(TLEN) == 0, "toad: tongue out after the restart")      -- tlen is the toad's alone; its INIT clears it
    frames(18)
    -- victory
    wr(HEARTS, 3); wr(INV, 99); wr(EHP, 0); wr(DEAD, 1); wr(ABIL, acc)
    for _, f in ipairs({3, 30, 100}) do
      frames(f == 3 and 3 or f == 30 and 27 or 70)
      if f == 30 and n <= 2 then                -- "GOT DASH" (row 13, 0x21A0) for the new ability of boss 1, nothing after boss 2
        local blank = true
        for c = 8, 23 do if ppu(0x21A0 + c) ~= 0 then blank = false end end
        check(blank == (n == 2), "boss " .. n .. ": GOT text " .. (blank and "missing" or "shown"))
      end
      for _, a in ipairs({24, 28, 32, 36, 52, 56, 60, 64, 68, 72, 100, 136, 140, 180, 208}) do
        check(not visible(0x200 + a), string.format("boss %d: victory frame %d: sprite at OAM byte %d still shown", n, f, a))
      end
    end
    acc = acc | ({1, 0, 2, 0, 4, 0, 8, 0, 16, 0})[n]
    check(wait_until(function() return rd(STATE) ~= 3 end, 200), "victory ends")
    check(save_ok(), "boss " .. n .. ": save checksum")
    check(rd(SAVE + 3) == 0xFF and rd(SAVE + 4) & 3 == 3, "mask saved")
    check((rd(SAVE + 4) & 0x80) == (n == 10 and 0x80 or 0), "boss " .. n .. ": ending bit " .. rd(SAVE + 4))
    wr(SAVE + 1, 0)
    check(rd(SAVE + 1) == 0x48, "boss " .. n .. ": PRG-RAM write-protected after the save")
    if n == 10 then
      check(wait_until(function() return rd(STATE) == 4 end, 60), "ending shown")
      check(wait_until(function() return rd(STATE) == 2 end, 400), "ending over")
    else
      check(rd(STATE) == 2, "boss " .. n .. ": back in the overworld")
    end
    frames(10)
  end

  -- ending replay and re-clearing a dungeon: the ending shows again, the save stays valid, no ability text for a known ability
  wr(ABIL, 31)
  enter(10); wr(EHP, 0); wr(DEAD, 1)
  check(wait_until(function() return rd(STATE) == 4 end, 400), "ending replay")
  check(save_ok() and rd(SAVE + 4) & 0x80 == 0x80, "save intact after the replay")
  check(wait_until(function() return rd(STATE) == 2 end, 400), "replay over")
  enter(1); wr(EHP, 0); wr(DEAD, 1); frames(10)
  local blank = true
  for c = 8, 23 do if ppu(0x21A0 + c) ~= 0 then blank = false end end
  check(blank, "no GOT text when the ability is already known")
  check(wait_until(function() return rd(STATE) == 2 end, 400), "cleared dungeon: back")
  print("review test OK")
  emu.stop(0)
end)

emu.addEventCallback(function() emu.setInput(held, 0, 0) end, emu.eventType.inputPolled)
emu.addEventCallback(function()
  if coroutine.status(co) == "dead" then return end
  local ok, err = coroutine.resume(co)
  if not ok then print("ERROR: " .. tostring(err)); emu.stop(1) end
end, emu.eventType.endFrame)
