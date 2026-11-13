-- Giant toad test (dungeon 7): intro name, bank 6, crouch telegraph + big hop + landing stun and shake, tongue telegraph +
-- extension + costs a heart (the shield stops it) and is not hittable, hits on the body, phases (look, palette, slime,
-- double tongue, hop chains), sprites per scanline, 60 Hz loop, standing-bot hearts, victory with the Shield (mask bit 6,
-- ability bit 3, valid save). Addresses: docs/TECH.md "Debug-Adressen".
local M = emu.memType.nesMemory
local held = {}
local function rd(a) return emu.read(a, M) end
local function rd16(a) return rd(a) + 256 * rd(a + 1) end
local function wr(a, v) emu.write(a, v, M) end
local function wr16(a, v) wr(a, v % 256); wr(a + 1, v // 256) end
local function ppu(a) return emu.read(a, emu.memType.nesPpuMemory) end
local STATE, PX, PY, CUR = 0x302, 0x303, 0x305, 0x30A
local HEARTS, INV, SWORD, VY = 0x30B, 0x30C, 0x30E, 0x30F
local EX, EY, EW, EH, EHP, EFLASH, EDIR = 0x310, 0x311, 0x312, 0x313, 0x314, 0x315, 0x316
local PHASE, DEAD, INTRO, FBX, FBY, FX = 0x318, 0x319, 0x31A, 0x31B, 0x31E, 0x321
local ABIL, VICT = 0x322, 0x325
local BANK, HIDE, IAIR = 0x326, 0x327, 0x328
local TLEN, SHIELD = 0x330, 0x331
local SIT, CROUCH, HOP, LAND, TTELE, TONGUE, STELE = 1, 2, 3, 4, 5, 6, 7
local FLOOR_Y = 176
local OAM_TONGUE, OAM_BODY, OAM_FB = 0x200 + 72, 0x200 + 84, 0x200 + 52

local co
local function frames(n) for _ = 1, n do coroutine.yield() end end
local function hold(keys, n) held = keys; frames(n); held = {} end
local function check(cond, msg)
  if not cond then print("FAIL: " .. msg); emu.stop(1); coroutine.yield() end
end
local function wait_until(f, max)
  for _ = 1, max do if f() then return true end frames(1) end
  return f()
end
local function bar()
  local t = ""
  for c = 20, 29 do t = t .. ({[40] = "F", [41] = "H", [42] = "."})[ppu(0x2000 + 2 * 32 + c)] end
  return t
end
local function max_line()
  local cnt, m = {}, 0
  for i = 0, 63 do
    local y = rd(0x200 + 4 * i)
    if y < 0xEF then
      for l = y + 1, y + 8 do cnt[l] = (cnt[l] or 0) + 1; m = math.max(m, cnt[l]) end
    end
  end
  return m
end
local function nfb() local n = 0; for i = 0, 2 do if rd(FBX + i) ~= 0 then n = n + 1 end end return n end
local function safe() wr(HEARTS, 3); wr(INV, 99) end
local function park() safe(); wr16(PX, 48); wr(PY, FLOOR_Y); wr(VY, 0) end
local peak = 0
local function line() local m = max_line(); peak = math.max(peak, m); return m end

-- player (facing right) just left of the toad, sword box over its body, no damage
local function align()
  wr16(PX, math.max(16, rd(EX) - 14)); wr(PY, FLOOR_Y); wr(VY, 0); safe()
end
-- one sword hit at the toad (waits until it sits or is stunned); returns hp afterwards
local function strike()
  local hp = rd(EHP)
  for _ = 1, 10 do
    wait_until(function()
      park(); local s = rd(IAIR)
      return rd(FX) == 0 and rd(EFLASH) == 0 and (s == SIT or s == LAND)
    end, 600)
    held = {b = true}
    for _ = 1, 3 do align(); frames(1); line() end
    held = {}
    for _ = 1, 20 do align(); frames(1); line() end
    if rd(EHP) ~= hp then break end
  end
  park()
  return rd(EHP)
end

-- Watch n frames with the player parked at x = 48 and safe. Run-length encoded states plus stats.
local function watch(n)
  local s = {runs = {}, mx = {}, miny = 255, line = 0, scroll = 0, scroll_late = 0, tl = 0, maxfb = 0, fc0 = rd16(0x300), fs = 0}
  local last, px, lnx = nil, rd(EX), nil
  for _ = 1, n do
    frames(1)
    park()
    local st, x, y = rd(IAIR), rd(EX), rd(EY)
    if rd(FX) == 0 then
      if st ~= last then s.runs[#s.runs + 1] = {st = st, n = 0, x = x, x0 = x, y0 = y, dx = 0}; last = st end
      local r = s.runs[#s.runs]; r.n = r.n + 1
      r.dx = math.max(r.dx, math.abs(x - r.x0))
      if r.n == 1 then s.fs = 0 end
      s.mx[st] = math.max(s.mx[st] or 0, math.abs(x - px))
      s.miny = math.min(s.miny, y)
      s.tl = math.max(s.tl, rd(TLEN))
      if st == LAND then
        local xs = emu.getState()["ppu.xScroll"]
        if r.n <= 12 then s.scroll = math.max(s.scroll, xs) else s.scroll_late = math.max(s.scroll_late, xs) end
      end
      r.xe = x
    end
    px = x
    s.maxfb = math.max(s.maxfb, nfb())
    s.line = math.max(s.line, line())
  end
  s.frames = rd16(0x300) - s.fc0
  return s
end
local function longest(s, st)
  local m = 0
  for _, r in ipairs(s.runs) do if r.st == st and r.n > m then m = r.n end end
  return m
end
local function first(s, st) for _, r in ipairs(s.runs) do if r.st == st then return r end end end
local function seen(s, st) return first(s, st) ~= nil end
-- standing bot: no input at x = 48 on the floor; hearts lost (refilled, so the fight never restarts)
local function bot(n)
  local lost = 0
  wr(HEARTS, 3); wr(INV, 0)
  for _ = 1, n do
    wr16(PX, 48); wr(PY, FLOOR_Y); wr(VY, 0)
    frames(1)
    local h = rd(HEARTS)
    if h < 3 then lost = lost + 3 - h; wr(HEARTS, 3) end
  end
  return lost
end
-- wait for a state of the toad (player parked), then act on it
local function until_state(st, max)
  return wait_until(function() park(); return rd(IAIR) == st and rd(FX) == 0 end, max)
end

co = coroutine.create(function()
  frames(10); held = {start = true}; frames(3); held = {}; frames(60)   -- boot menu: Start = NORMAL
  check(rd(STATE) == 2, "boot reaches overworld")
  wr16(0x308, 63)                           -- dungeons 1..6 cleared: gate 7 open
  wr16(PX, 624); wr(PY, 80)                 -- door of dungeon 7
  frames(30)
  hold({a = true}, 3)
  frames(20)
  check(rd(STATE) == 3 and rd(CUR) == 7, "dungeon 7 entered, state=" .. rd(STATE))
  check(rd(BANK) == 6 and rd(0x8000) ~= 0, "toad bank 6 mapped, cur_bank=" .. rd(BANK))

  -- intro: "GIANT TOAD" (G I A N T _ T O A D = 29 13 37 28 34 0 34 31 37 26 at row 10, columns 11..20)
  check(rd(INTRO) > 0, "intro running")
  check(rd(EHP) == 16 and rd(PHASE) == 1 and bar() == "FFFFFFFFFF", "toad: 16 hp, phase 1, full bar")
  check(rd(EW) == 32 and rd(EH) == 24, "toad is 32x24, w=" .. rd(EW) .. " h=" .. rd(EH))
  local name = {}
  for c = 11, 20 do name[#name + 1] = ppu(0x2000 + 10 * 32 + c) end
  check(table.concat(name, ",") == "29,13,37,28,34,0,34,31,37,26", "name GIANT TOAD on screen: " .. table.concat(name, ","))
  check(rd(OAM_BODY) == rd(EY) - 1 + 0 and rd(OAM_BODY + 1) == 0x40, "toad body drawn already in the intro, tile " .. rd(OAM_BODY + 1))
  check(rd(OAM_BODY + 2) == 0x41, "faces left toward the player (flipped), attr=" .. rd(OAM_BODY + 2))
  for i = 0, 2 do check(rd(OAM_TONGUE + 4 * i) == 0xFF, "no tongue in the intro") end
  local x0 = rd(EX)
  frames(10)
  check(rd(EX) == x0 and rd(IAIR) == 0, "toad frozen during the intro")
  check(wait_until(function() return rd(INTRO) == 0 end, 100), "intro ends")

  -- phase 1 cycle: hop, hop, tongue. Crouch ~30 frames (sinks 3 px), hop 36..42 frames to the player's side,
  -- stun ~40 frames, landing shake, tongue telegraph ~25 frames, tongue ~36 frames.
  local s = watch(900)
  check(s.frames == 900, "game loop runs at 60 Hz: 900 frames -> frame_count +" .. s.frames)
  local c1, h1 = first(s, CROUCH), first(s, HOP)
  check(c1 and c1.n >= 28 and c1.n <= 32 and c1.dx == 0, "crouch ~30 frames without moving, n=" .. tostring(c1 and c1.n))
  check(h1 and h1.n >= 36 and h1.n <= 42, "hop 36..42 frames, n=" .. tostring(h1 and h1.n))
  check(h1.dx == h1.xe - h1.x0 or h1.dx == h1.x0 - h1.xe, "hop moves one way")
  check(s.miny <= 110 and s.miny >= 96, "hop arc ~63 px high (min y 105), min y " .. s.miny)
  check(s.mx[HOP] >= 2 and s.mx[HOP] <= 4, "hop speed 2..4 px/frame, got " .. tostring(s.mx[HOP]))
  check(h1.x0 == 160 and h1.xe >= 78 and h1.xe <= 82, "lands at the player: toad front edge 24 px from his center (x 80), x=" .. h1.xe)
  check(longest(s, LAND) >= 38 and longest(s, LAND) <= 42, "stun ~40 frames, got " .. longest(s, LAND))
  local l1 = first(s, LAND)
  check(l1.dx == 0, "no movement while stunned")
  check(s.scroll == 2 and s.scroll_late == 0, "landing shake (scroll 2) for a few frames only, " .. s.scroll .. " / " .. s.scroll_late)
  check(longest(s, TTELE) >= 23 and longest(s, TTELE) <= 27, "tongue telegraph ~25 frames, got " .. longest(s, TTELE))
  check(first(s, TTELE).dx == 0, "no movement during the tongue telegraph")
  check(longest(s, TONGUE) >= 34 and longest(s, TONGUE) <= 38, "tongue ~36 frames, got " .. longest(s, TONGUE))
  check(s.tl == 3, "tongue grows to 3 segments, got " .. s.tl)
  check(not seen(s, STELE) and s.maxfb == 0, "phase 1 spits no slime")
  check(s.line <= 8, "phase 1: max 8 sprites per scanline, got " .. s.line)
  local lost1 = bot(1200)
  check(lost1 <= 3, "phase 1 standing bot loses <= 3 hearts, lost " .. lost1)

  -- tongue sprites: out toward the player, one per segment; the mouth cell makes room
  check(until_state(TTELE, 600), "tongue telegraph")
  wr(EX, 100)
  frames(2)
  check(rd(OAM_BODY + 4 * 7 + 1) == 0x40 + 38, "mouth open while telegraphing (boss tile 38)")
  check(until_state(TONGUE, 40), "tongue follows")
  check(wait_until(function() park(); return rd(TLEN) == 3 end, 20), "tongue fully out")
  frames(1)
  local n = 0
  for i = 0, 2 do if rd(OAM_TONGUE + 4 * i) ~= 0xFF then n = n + 1 end end
  check(n == 3 and rd(OAM_TONGUE + 1) == 0x40 + 36 and rd(OAM_TONGUE + 9) == 0x40 + 37, "3 tongue sprites, tip boss tile 37")
  check(rd(OAM_TONGUE + 3) == rd(EX) and rd(OAM_TONGUE + 7) == rd(EX) - 8, "tongue starts at the mouth cell and goes left (toad faces left)")
  check(rd(OAM_BODY + 4 * 7) == 0xFF, "mouth cell hidden while the tongue is out")
  check(rd(HEARTS) == 3, "player far away: no damage")

  -- tongue not hittable: sword box over the tongue only (right of... left of the toad, facing right)
  local hp = rd(EHP)
  wr16(PX, rd(EX) - 34); wr(PY, FLOOR_Y); safe()
  hold({b = true}, 3)
  local tl = 0
  for _ = 1, 3 do wr16(PX, rd(EX) - 34); safe(); frames(1); tl = math.max(tl, max_line()) end
  check(tl <= 10, "tongue out + sword swinging: at most 10 sprites per scanline (the toad's last body sprites drop out), got " .. tl)
  check(rd(EHP) == hp and rd(EFLASH) == 0, "sword on the tongue does not hurt the toad, hp=" .. rd(EHP))
  wait_until(function() park(); return rd(IAIR) == SIT end, 60)

  -- tongue costs exactly one heart: player 12 px beyond the front edge (not touching the body)
  check(until_state(TTELE, 700), "next tongue telegraph")
  wr(EX, 100)
  wr(HEARTS, 3); wr(INV, 0)
  local dir = rd(EDIR) >= 128 and -1 or 1
  local function reach() wr16(PX, dir > 0 and rd(EX) + 32 + 12 - 8 or rd(EX) - 12 - 8); wr(PY, FLOOR_Y); wr(VY, 0) end
  local lost = false
  for _ = 1, 70 do
    reach(); frames(1)
    if rd(HEARTS) < 3 then lost = true; break end
    wr(INV, 0)
  end
  check(lost and rd(HEARTS) == 2 and rd(INV) > 0, "tongue costs one heart, hearts=" .. rd(HEARTS))
  check(rd(IAIR) == TONGUE, "the hit happens during the tongue")
  frames(60)
  check(rd(HEARTS) == 2, "no second hit during the invulnerability, hearts=" .. rd(HEARTS))
  check(wait_until(function() park(); return rd(IAIR) == SIT end, 80), "tongue ends")
  check(rd(TLEN) == 0 and rd(OAM_TONGUE) == 0xFF, "tongue retracted")

  -- shield stops the tongue and pushes back
  wr(ABIL, 8)
  check(until_state(TTELE, 700), "tongue telegraph again")
  wr(EX, 100)
  wr(HEARTS, 3); wr(INV, 0)
  dir = rd(EDIR) >= 128 and -1 or 1
  hold(dir > 0 and {left = true} or {right = true}, 1)       -- face the toad (the shield is in front)
  held = {down = true}
  local x1
  for _ = 1, 45 do reach(); frames(1); x1 = x1 or rd16(PX) end
  held = {}
  check(rd(HEARTS) == 3 and rd(INV) == 0, "shield: the tongue costs no heart, hearts=" .. rd(HEARTS))
  wr(ABIL, 0)
  wait_until(function() park(); return rd(IAIR) == SIT end, 80)

  -- contact with the toad costs a heart (also while it crouches), at the stun too
  wr(EX, 100); wr(EY, 168)
  wr(HEARTS, 3); wr(INV, 0); wr16(PX, 110); wr(PY, FLOOR_Y)
  frames(2)
  check(rd(HEARTS) == 2, "body contact costs a heart, hearts=" .. rd(HEARTS))

  -- crouch looks: the body sinks 3 px; the hit box stays
  until_state(CROUCH, 700)
  frames(3)
  check(rd(OAM_BODY) == rd(EY) + 2 and rd(EY) == 168, "crouch: body drawn 3 px lower, oam y=" .. rd(OAM_BODY))

  -- sword hit on the body: exactly 1 hp, bar ceil(15*20/16) = 19 half steps, <= 8 sprites per line with the sword out
  local hp = strike()
  check(hp == 15, "hit = exactly 1 hp, hp=" .. hp)
  check(bar() == "FFFFFFFFFH", "bar after one hit, bar=" .. bar())
  check(peak <= 8, "sword + toad + player: max 8 sprites per scanline, got " .. peak)

  -- phase 2 at hp <= 11 (70 % of 16 = 11): look, palette, slime, standing bot
  wr(EHP, 12); wr(EFLASH, 0)
  check(strike() == 11 and rd(PHASE) == 2, "hp 11 -> phase 2, phase=" .. rd(PHASE))
  frames(2)
  check(bar() == "FFFFFFF...", "bar 14 half steps at hp 11, bar=" .. bar())
  check(wait_until(function() return ppu(0x3F15) == 0x04 end, 80), "phase 2 palette")
  check(wait_until(function() return rd(FX) == 0 end, 60), "phase effect ends")
  check(rd(OAM_BODY + 1) >= 0x40 + 12 and rd(OAM_BODY + 1) < 0x40 + 24, "phase 2 look (boss tiles 12..23)")
  -- slime: lobbed blob in an arc toward the player, boss palette and tile 167
  check(until_state(STELE, 900), "phase 2 spits")
  wr(EX, 140); wr(EY, 168)
  check(wait_until(function() park(); return nfb() > 0 end, 40), "a blob spawns")
  local k = 0
  for i = 0, 2 do if rd(FBX + i) ~= 0 then k = i end end
  check(rd(OAM_FB + 4 * k + 1) == 0x40 + 39 and rd(OAM_FB + 4 * k + 2) == 1, "slime sprite: boss tile 39, palette 1")
  local y0, ymin, lastx = rd(FBY + k), 255, 0
  check(y0 <= 160 and y0 >= 150, "blob starts above the toad's head (160, minus one flight step if the frame parity differs), y=" .. y0)
  local peakline = 0
  for _ = 1, 160 do
    park(); frames(1)
    if rd(FBX + k) == 0 then break end
    ymin = math.min(ymin, rd(FBY + k)); lastx = rd(FBX + k)
    peakline = math.max(peakline, line())
  end
  check(ymin < y0 - 20, "the blob rises and then falls (arc), min y " .. ymin)
  check(rd(FBX + k) == 0 and math.abs(lastx - 52) <= 24, "the blob lands near the player (x 52; the arc depends on frame_count mod 8), x=" .. lastx)
  check(peakline <= 8, "slime flight: max 8 sprites per scanline, got " .. peakline)
  s = watch(1200)
  check(seen(s, STELE) and longest(s, STELE) >= 18 and longest(s, STELE) <= 22, "spit telegraph ~20 frames, got " .. longest(s, STELE))
  check(s.maxfb == 1, "phase 2 spits one blob at a time, max " .. s.maxfb)
  check(s.line <= 8, "phase 2: max 8 sprites per scanline, got " .. s.line)
  local lost2 = bot(1200)
  check(lost2 <= 3, "phase 2 standing bot loses <= 3 hearts, lost " .. lost2)

  -- phase 3 at hp <= 8: look, palette, hop chains, double tongue, two blobs
  wr(EHP, 9); wr(EFLASH, 0)
  check(strike() == 8 and rd(PHASE) == 3, "hp 8 -> phase 3, phase=" .. rd(PHASE))
  frames(2)
  check(bar() == "FFFFF.....", "bar half at hp 8, bar=" .. bar())
  check(wait_until(function() return ppu(0x3F15) == 0x03 end, 80), "phase 3 palette")
  check(wait_until(function() return rd(FX) == 0 end, 60), "phase effect ends")
  s = watch(1500)
  check(rd(OAM_BODY + 1) >= 0x40 + 24 and rd(OAM_BODY + 1) < 0x40 + 36, "phase 3 look (boss tiles 24..35)")
  local chain, dbl = false, false
  for i = 1, #s.runs - 4 do
    local a, b, c, d, e = s.runs[i], s.runs[i + 1], s.runs[i + 2], s.runs[i + 3], s.runs[i + 4]
    if a.st == HOP and b.st == LAND and b.n <= 16 and c.st == SIT and c.n <= 8 and d.st == CROUCH and d.n <= 16 and e.st == HOP then chain = true end
    if a.st == TONGUE and b.st == SIT and b.n <= 10 and c.st == TTELE and c.n <= 17 and d.st == TONGUE then dbl = true end
  end
  check(chain, "phase 3: hops in a row (short stun and crouch)")
  check(dbl, "phase 3: double tongue (second one after a short pause)")
  check(s.maxfb == 2, "phase 3 spits two blobs, max " .. s.maxfb)
  check(s.line <= 8, "phase 3: max 8 sprites per scanline, got " .. s.line)
  check(longest(s, LAND) >= 38 and longest(s, LAND) <= 42, "the last hop of a chain still stuns ~40 frames, got " .. longest(s, LAND))
  local lost3 = bot(1200)
  check(lost3 <= 3, "phase 3 standing bot loses <= 3 hearts, lost " .. lost3)

  -- victory: hp 1 + hit -> dead, body and tongue gone, text names the ability, overworld, mask bit 6, Shield granted and saved
  wr(EHP, 1); wr(EFLASH, 0)
  check(strike() == 0 and rd(DEAD) == 1, "hp 0 -> boss_dead")
  frames(3)
  check(rd(VICT) > 0 and ppu(0x2000 + 10 * 32 + 12) == 32 and ppu(0x2000 + 10 * 32 + 18) == 36, "'VICTORY' on screen")
  for i = 0, 14 do check(rd(OAM_TONGUE + 4 * i) == 0xFF, "dead: toad sprite " .. i .. " hidden") end
  check(emu.getState()["ppu.xScroll"] == 0, "no shake left over")
  local got = {}
  for c = 11, 20 do got[#got + 1] = ppu(0x2000 + 13 * 32 + c) end
  check(table.concat(got, ",") == "29,31,34,0,38,39,13,30,44,26", "'GOT SHIELD' on screen: " .. table.concat(got, ","))
  check(wait_until(function() return rd(STATE) == 2 end, 300), "victory returns to the overworld")
  check(rd16(0x308) == 127, "dungeon 7 cleared (bit 6), mask=" .. rd16(0x308))
  check(rd(ABIL) == 8, "Shield granted, abilities=" .. rd(ABIL))
  check(rd16(PX) == 624 and rd(PY) == 80 and rd(CUR) == 0, "back at entrance 7")
  check(rd(0x6000) == 0x45 and rd(0x6001) == 0x48 and rd(0x6002) == 1 and rd(0x6003) == 127 and rd(0x6004) == 0
        and rd(0x6005) == 8 and rd(0x6006) == 0x15, "autosave valid")

  print("toad test OK (hearts lost by a standing bot per phase: " .. lost1 .. " / " .. lost2 .. " / " .. lost3 ..
        ", peak sprites per scanline: " .. peak .. ")")
  emu.stop(0)
end)

emu.addEventCallback(function() emu.setInput(held, 0, 0) end, emu.eventType.inputPolled)
emu.addEventCallback(function()
  if coroutine.status(co) == "dead" then return end
  local ok, err = coroutine.resume(co)
  if not ok then print("ERROR: " .. tostring(err)); emu.stop(1) end
end, emu.eventType.endFrame)
