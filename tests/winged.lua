-- Winged demon test (dungeon 5): intro name, bank 4, patrol with bob, telegraph then dive to the player, rest window on the
-- floor, floor hit = 1 hp, contact = 1 heart, phases (look, palette, speeds, fireballs on the way up, double dive), sprites
-- per scanline, victory with "GOT FIREBALL" (ability bit 2) and a valid save. Addresses: docs/TECH.md "Debug-Adressen".
local M = emu.memType.nesMemory
local held = {}
local function rd(a) return emu.read(a, M) end
local function rd16(a) return rd(a) + 256 * rd(a + 1) end
local function wr(a, v) emu.write(a, v, M) end
local function wr16(a, v) wr(a, v % 256); wr(a + 1, v // 256) end
local function ppu(a) return emu.read(a, emu.memType.nesPpuMemory) end
local STATE, PX, PY, CUR = 0x302, 0x303, 0x305, 0x30A
local HEARTS, INV = 0x30B, 0x30C
local EX, EY, EHP, EFLASH = 0x310, 0x311, 0x314, 0x315
local PHASE, DEAD, INTRO, FBX, FX = 0x318, 0x319, 0x31A, 0x31B, 0x321
local ABIL, VICT = 0x322, 0x325
local BANK, HIDE, IAIR = 0x326, 0x327, 0x328
local PAT, TELE, DIVE, REST, RISE = 1, 2, 3, 4, 5
local FLOOR_Y = 176
local OAM_HEAD = 0x200 + 24

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
local function nfb() local n = 0; for i = 0, 2 do if rd(FBX + i) ~= 0 then n = n + 1 end end return n end
local function bar()
  local t = ""
  for c = 20, 29 do t = t .. ({[40] = "F", [41] = "H", [42] = "."})[ppu(0x2000 + 2 * 32 + c)] end
  return t
end
-- max sprites on one scanline from the OAM copy (hidden = y 0xFF)
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
local maxline, peak = 0, 0
local function safe() wr(HEARTS, 3); wr(INV, 99) end
-- player (facing right) left of the demon, sword box over it; no damage
local function align()
  wr16(PX, math.max(16, rd(EX) - 14)); wr(PY, FLOOR_Y); wr(0x30F, 0); safe()
end
-- wait for the rest on the floor, then swing once at the demon; returns hp afterwards
local function strike()
  local hp = rd(EHP)
  for _ = 1, 6 do
    wait_until(function() safe(); wr16(PX, 120); wr(PY, FLOOR_Y); return rd(IAIR) == REST and rd(FX) == 0 and rd(EFLASH) == 0 end, 900)
    held = {b = true}
    for _ = 1, 3 do align(); frames(1); maxline = math.max(maxline, max_line()) end
    held = {}
    for _ = 1, 6 do align(); frames(1); maxline = math.max(maxline, max_line()) end
    if rd(EHP) ~= hp then break end
  end
  wr16(PX, 120); wr(PY, FLOOR_Y)
  return rd(EHP)
end
-- Watch n frames with the player parked on the floor at x = px and safe.
local function watch(n, px)
  local s = {runs = {}, mxd = 0, mxr = 0, miny = 255, maxy = 0, minx = 255, maxx = 0, line = 0, spawns = 0, volley = 0,
             maxfb = 0, hides = {}, patd = 0, patn = 0, land = {}, rest_y = {}}
  local last, ey, ex, prev = nil, rd(EY), rd(EX), {}
  for i = 0, 2 do prev[i] = rd(FBX + i) end
  for _ = 1, n do
    frames(1)
    safe(); wr16(PX, px); wr(PY, FLOOR_Y)
    local x, y, st = rd(EX), rd(EY), rd(IAIR)
    if rd(FX) == 0 then
      if st == DIVE and last == DIVE then s.mxd = math.max(s.mxd, y - ey) end
      if st == RISE and last == RISE then s.mxr = math.max(s.mxr, ey - y) end
    end
    if st ~= last then
      s.runs[#s.runs + 1] = {st = st, n = 0}
      if st == REST then s.land[#s.land + 1] = x; s.rest_y[#s.rest_y + 1] = y end
      last = st
    end
    local r = s.runs[#s.runs]; r.n = r.n + 1
    if st == TELE then s.hides[rd(HIDE)] = true end
    if st == PAT then
      s.miny = math.min(s.miny, y); s.maxy = math.max(s.maxy, y)
      s.minx = math.min(s.minx, x); s.maxx = math.max(s.maxx, x)
      if r.n > 1 then s.patd = s.patd + math.abs(x - ex); s.patn = s.patn + 1 end
    end
    ex, ey = x, y
    local new = 0
    for i = 0, 2 do
      local v = rd(FBX + i)
      if v ~= 0 and prev[i] == 0 then new = new + 1 end
      prev[i] = v
    end
    s.spawns = s.spawns + new
    s.volley = math.max(s.volley, new)
    s.maxfb = math.max(s.maxfb, nfb())
    s.line = math.max(s.line, max_line())
    peak = math.max(peak, s.line)
  end
  return s
end
local function longest(s, st)
  local m = 0
  for _, r in ipairs(s.runs) do if r.st == st and r.n > m then m = r.n end end
  return m
end
local function shortest_inner(s, st)       -- shortest run of st that has a run before and after it (complete)
  local m = 999
  for i = 2, #s.runs - 1 do if s.runs[i].st == st and s.runs[i].n < m then m = s.runs[i].n end end
  return m
end
local function has_seq(s, seq)
  for i = 1, #s.runs - #seq + 1 do
    local ok = true
    for k = 1, #seq do if s.runs[i + k - 1].st ~= seq[k] then ok = false end end
    if ok then return true end
  end
  return false
end

co = coroutine.create(function()
  frames(30); held = {start = true}; frames(3); held = {}; frames(20); held = {start = true}; frames(3); held = {}; frames(60)   -- boot menu: Start = NEW GAME (CONTINUE with a save), second Start skips the intro
  check(rd(STATE) == 2, "boot reaches overworld")
  wr16(0x308, 15)                         -- dungeons 1-4 cleared: gate 5 open
  wr16(PX, 432); wr(PY, 80)               -- door of dungeon 5
  frames(30)
  hold({a = true}, 3)
  frames(20)
  check(rd(STATE) == 3 and rd(CUR) == 5, "dungeon 5 entered, state=" .. rd(STATE))
  check(rd(BANK) == 4 and rd(0x8000) ~= 0, "winged bank 4 mapped, cur_bank=" .. rd(BANK))

  -- intro: "WINGED DEMON" (tiles 47 13 28 29 30 26 _ 26 30 14 31 28 at row 10, columns 10..21)
  check(rd(INTRO) > 0, "intro running")
  check(rd(EHP) == 14 and rd(PHASE) == 1 and bar() == "FFFFFFFFFF", "winged: 14 hp, phase 1, full bar")
  local name = {}
  for c = 10, 21 do name[#name + 1] = ppu(0x2000 + 10 * 32 + c) end
  check(table.concat(name, ",") == "47,13,28,29,30,26,0,26,30,14,31,28", "name WINGED DEMON on screen: " .. table.concat(name, ","))
  local x0, y0 = rd(EX), rd(EY)
  frames(10)
  check(rd(EX) == x0 and rd(EY) == y0 and rd(IAIR) == 0, "demon frozen during the intro")
  check(rd(0x312) == 16 and rd(0x313) == 24, "16x24 demon")
  check(wait_until(function() return rd(INTRO) == 0 end, 100), "intro ends")
  hold({right = true}, 2)                 -- face right

  -- phase 1: patrol (bob), ~30 frame telegraph with flicker, 4 px/frame dive to the player, 40 frame rest, 3 px/frame rise
  local s = watch(1300, 120)
  check(has_seq(s, {PAT, TELE, DIVE, REST, RISE, PAT}), "cycle PATROL, TELE, DIVE, REST, RISE, PATROL")
  check(longest(s, PAT) >= 400 and longest(s, PAT) <= 440, "phase 1 patrols ~420 frames, got " .. longest(s, PAT))
  check(s.miny >= 56 and s.maxy <= 72 and s.maxy - s.miny >= 8, "flies high and bobs, y " .. s.miny .. ".." .. s.maxy)
  check(s.maxx - s.minx >= 100, "patrols left/right, x " .. s.minx .. ".." .. s.maxx)
  local sp = s.patd / s.patn
  check(sp > 0.6 and sp < 0.9, "phase 1 patrol ~0.75 px/frame, got " .. sp)
  check(shortest_inner(s, TELE) >= 28 and longest(s, TELE) <= 32, "telegraph ~30 frames, got " .. longest(s, TELE))
  check(s.hides[0] and s.hides[2] and not s.hides[1] and not s.hides[3], "telegraph flickers (boss_hide 0 and 2: drawn / not drawn, hittable)")
  check(s.mxd == 4, "phase 1 dives 4 px/frame, got " .. s.mxd)
  check(s.rest_y[1] == 168 and math.abs(s.land[1] - 120) <= 4, "dive lands on the floor at the player's x: " .. s.land[1] .. "," .. s.rest_y[1])
  check(shortest_inner(s, REST) >= 38 and longest(s, REST) <= 42, "rest ~40 frames, got " .. longest(s, REST))
  check(s.mxr == 3, "rises 3 px/frame, got " .. s.mxr)
  check(s.spawns == 0, "phase 1 has no fireballs, got " .. s.spawns)
  check(s.line <= 8, "max 8 sprites per scanline, got " .. s.line)

  -- contact (patrol, high up) costs exactly one heart, the invulnerability protects afterwards
  check(wait_until(function() safe(); wr16(PX, 120); wr(PY, FLOOR_Y); return rd(IAIR) == PAT and rd(EFLASH) == 0 end, 900), "patrolling")
  wr(INV, 0); wr(HEARTS, 3); wr16(PX, rd(EX)); wr(PY, rd(EY)); frames(2)
  check(rd(HEARTS) == 2 and rd(INV) > 80, "contact costs a heart, hearts=" .. rd(HEARTS))
  wr16(PX, rd(EX)); wr(PY, rd(EY)); frames(5)
  check(rd(HEARTS) == 2, "no second loss while invulnerable")
  safe(); wr16(PX, 120); wr(PY, FLOOR_Y)

  -- floor hit during the rest: exactly 1 hp, bar 19 half steps; a hit while hovering high does not reach from the floor
  local hp = strike()
  check(hp == 13 and bar() == "FFFFFFFFFH", "floor hit = exactly 1 hp, bar=" .. bar() .. " hp=" .. hp)
  check(maxline <= 8, "sword swing + overlap: max 8 sprites per scanline, got " .. maxline)
  check(wait_until(function() safe(); wr16(PX, 120); wr(PY, FLOOR_Y); return rd(IAIR) == PAT end, 400), "patrolling again")
  hp = rd(EHP)
  held = {b = true}
  for _ = 1, 4 do wr(EFLASH, 0); wr16(PX, math.max(16, rd(EX) - 14)); wr(PY, FLOOR_Y); safe(); frames(1) end
  held = {}
  check(rd(EHP) == hp, "demon high up: not reachable with the sword from the floor")

  -- phase 2 at hp <= 9: look, palette, faster patrol, dives more often, 5 px/frame, a fireball on the way up
  wr(EHP, 10); wr(EFLASH, 0)
  check(strike() == 9 and rd(PHASE) == 2, "hp 9 -> phase 2, phase=" .. rd(PHASE))
  frames(2)
  check(bar() == "FFFFFFH...", "bar 13 steps at hp 9, bar=" .. bar())
  check(rd(OAM_HEAD + 1) == 0x40 + 6, "phase 2 look (boss tile 6)")
  check(wait_until(function() return ppu(0x3F16) == 0x26 end, 80), "phase 2 palette")
  check(wait_until(function() return rd(FX) == 0 end, 60), "phase effect ends")
  s = watch(1100, 120)
  sp = s.patd / s.patn
  check(sp > 1.1 and sp < 1.4, "phase 2 patrol ~1.25 px/frame, got " .. sp)
  check(longest(s, PAT) >= 280 and longest(s, PAT) <= 320, "phase 2 patrols ~300 frames (dives more often), got " .. longest(s, PAT))
  check(s.mxd == 5, "phase 2 dives 5 px/frame, got " .. s.mxd)
  check(shortest_inner(s, TELE) >= 26 and longest(s, TELE) <= 30, "phase 2 telegraph ~28 frames, got " .. longest(s, TELE))
  check(s.volley == 1 and s.spawns >= 2, "phase 2 drops one fireball per rise, volley " .. s.volley .. " spawns " .. s.spawns)
  check(s.line <= 8, "phase 2: sprites per line " .. s.line)

  -- phase 3 at hp <= 7: look, palette, double dive, fireball spread of 3 when rising
  wr(EHP, 8); wr(EFLASH, 0)
  check(strike() == 7 and rd(PHASE) == 3, "hp 7 -> phase 3, phase=" .. rd(PHASE))
  frames(2)
  check(bar() == "FFFFF.....", "bar half at hp 7, bar=" .. bar())
  check(rd(OAM_HEAD + 1) == 0x40 + 12, "phase 3 look (boss tile 12)")
  check(wait_until(function() return ppu(0x3F16) == 0x16 end, 80), "phase 3 palette")
  check(wait_until(function() return rd(FX) == 0 end, 60), "phase effect ends")
  s = watch(1500, 120)
  check(has_seq(s, {PAT, TELE, DIVE, REST, RISE, TELE, DIVE, REST, RISE, PAT}), "phase 3: two dives in a row")
  check(s.volley == 3 and s.maxfb == 3, "phase 3 drops a spread of 3, volley " .. s.volley)
  check(s.mxd == 5, "phase 3 dives 5 px/frame, got " .. s.mxd)
  check(s.line <= 8, "phase 3: sprites per line " .. s.line)

  -- victory: hp 1 + floor hit -> dead, fireballs gone, "GOT FIREBALL", overworld, bit 4, ability bit 2, saved
  wr(EHP, 1); wr(EFLASH, 0)
  check(strike() == 0 and rd(DEAD) == 1, "hp 0 -> boss_dead")
  frames(3)
  check(rd(VICT) > 0 and ppu(0x2000 + 10 * 32 + 12) == 32 and ppu(0x2000 + 10 * 32 + 18) == 36, "'VICTORY' on screen")
  check(rd(OAM_HEAD) == 0xFF and nfb() == 0, "dead: demon and fireballs gone")
  -- GOT FIREBALL = G O T _ F I R E B A L L = tiles 29 31 34 0 48 13 35 30 43 37 44 44 at row 13, columns 10..21
  local got = {}
  for c = 10, 21 do got[#got + 1] = ppu(0x2000 + 13 * 32 + c) end
  check(table.concat(got, ",") == "29,31,34,0,48,13,35,30,43,37,44,44", "'GOT FIREBALL' on screen: " .. table.concat(got, ","))
  check(wait_until(function() return rd(STATE) == 2 end, 300), "victory returns to the overworld")
  check(rd16(0x308) == 31, "dungeon 5 cleared (bit 4), mask=" .. rd16(0x308))
  check(rd(ABIL) == 4, "Fireball granted (bit 2), abilities=" .. rd(ABIL))
  check(rd16(PX) == 432 and rd(PY) == 80 and rd(CUR) == 0, "back at entrance 5")
  check(rd(0x6000) == 0x45 and rd(0x6001) == 0x48 and rd(0x6002) == 1 and rd(0x6003) == 31 and rd(0x6004) == 0
        and rd(0x6005) == 4 and rd(0x6006) == 0xB1, "autosave valid")

  print("winged test OK (peak sprites per scanline: " .. math.max(peak, maxline) .. ")")
  emu.stop(0)
end)

emu.addEventCallback(function() emu.setInput(held, 0, 0) end, emu.eventType.inputPolled)
emu.addEventCallback(function()
  if coroutine.status(co) == "dead" then return end
  local ok, err = coroutine.resume(co)
  if not ok then print("ERROR: " .. tostring(err)); emu.stop(1) end
end, emu.eventType.endFrame)
