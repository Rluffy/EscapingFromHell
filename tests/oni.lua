-- Oni warlord test (dungeon 9): intro name, bank 8, walks toward the player and stops in front, club telegraph -> smash ->
-- shockwave on the floor (moves away, jumpable, the shield stops it), recovery window, charge (telegraph, speed, dazed at the
-- wall, jumpable), phase 2 (both-way shockwaves, faster), phase 3 (double smash, leap), looks, sprites per scanline, 60 Hz
-- loop, standing-bot hearts, contact, victory with "GOT SWORD WAVE" (mask bit 8, ability bit 4, valid save).
-- Addresses: docs/TECH.md "Debug-Adressen".
local M = emu.memType.nesMemory
local held = {}
local function rd(a) return emu.read(a, M) end
local function rd16(a) return rd(a) + 256 * rd(a + 1) end
local function wr(a, v) emu.write(a, v, M) end
local function wr16(a, v) wr(a, v % 256); wr(a + 1, v // 256) end
local function ppu(a) return emu.read(a, emu.memType.nesPpuMemory) end
local function signed(v) return v >= 128 and v - 256 or v end
local STATE, PX, PY, CUR = 0x302, 0x303, 0x305, 0x30A
local HEARTS, INV, ONG, SWORD, VY = 0x30B, 0x30C, 0x30D, 0x30E, 0x30F
local EX, EY, EW, EH, EHP, EFLASH, EDIR = 0x310, 0x311, 0x312, 0x313, 0x314, 0x315, 0x316
local PHASE, DEAD, INTRO, FBX, FBY, FX = 0x318, 0x319, 0x31A, 0x31B, 0x31E, 0x321
local ABIL, VICT = 0x322, 0x325
local BANK, HIDE, IAIR, SHIELD = 0x326, 0x327, 0x328, 0x331
local WALK, STELE, SMASH, REST, CTELE, CHARGE, LTELE, LEAP = 1, 2, 3, 4, 5, 6, 7, 8
local FLOOR_Y, GROUND = 176, 160
local OAM_FB, OAM_E, OAM_BODY, OAM_CLUB = 0x200 + 52, 0x200 + 24, 0x200 + 72, 0x200 + 112
local SHOCK = 189

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
local function noshots() for i = 0, 2 do wr(FBX + i, 0) end end
local function safe() wr(HEARTS, 3); wr(INV, 99) end
local function park() safe(); wr16(PX, 48); wr(PY, FLOOR_Y); wr(VY, 0) end
local peak, wave_peak = 0, 0

-- one sword hit at the oni (player beside it on its left, no damage); returns hp afterwards
local function strike()
  local hp = rd(EHP)
  for _ = 1, 12 do
    wait_until(function() safe(); return rd(FX) == 0 and rd(EFLASH) == 0 end, 900)
    held = {b = true}
    for _ = 1, 3 do wr16(PX, math.max(16, rd(EX) - 14)); wr(PY, FLOOR_Y); wr(VY, 0); safe(); frames(1) end
    held = {}
    for _ = 1, 20 do wr16(PX, math.max(16, rd(EX) - 14)); wr(PY, FLOOR_Y); wr(VY, 0); safe(); frames(1) end
    if rd(EHP) ~= hp then break end
  end
  park()
  return rd(EHP)
end

-- Watch n frames with the player standing at x = 48 (unsafe: `bot`) or safe. Run-length encoded states plus stats.
local function watch(n, bot, swing)
  local s = {runs = {}, line = 0, fc0 = rd16(0x300), lost = 0, wave_y = {}, wave_v = {}, both = false, nwave = 0, maxwave = 0,
             club = {}, tile = nil, waves = {}}
  local last, pw = nil, {}
  if bot then wr(HEARTS, 3); wr(INV, 0) end
  for i = 1, n do
    if swing then held = {b = i % 16 < 3} end
    wr16(PX, 48); wr(PY, FLOOR_Y); wr(VY, 0)
    if not bot then safe() end
    frames(1)
    if bot then
      local h = rd(HEARTS)
      if h < 3 then s.lost = s.lost + 3 - h; wr(HEARTS, 3) end
    end
    local st, x, y = rd(IAIR), rd(EX), rd(EY)
    if rd(FX) == 0 then
      if st ~= last then s.runs[#s.runs + 1] = {st = st, n = 0, x0 = x, y0 = y, ymin = y, hide = {}, fc = rd16(0x300)}; last = st end
      local r = s.runs[#s.runs]; r.n = r.n + 1; r.xe = x; r.ymin = math.min(r.ymin, y)
      r.hide[rd(HIDE)] = true
      s.tile = rd(OAM_BODY + 1)
      if rd(OAM_CLUB) < 0xEF then s.club[st] = true end
    end
    local pos, neg, w = false, false, 0
    for k = 0, 2 do
      local fx = rd(FBX + k)
      if fx ~= 0 and rd(OAM_FB + 4 * k + 1) == SHOCK then
        w = w + 1
        s.wave_y[rd(FBY + k)] = true
        if not pw[k] then s.waves[#s.waves + 1] = {st = st, x = fx, fc = rd16(0x300), tile = rd(OAM_FB + 4 * k + 1), attr = rd(OAM_FB + 4 * k + 2)} end
        if pw[k] then
          local v = fx - pw[k]
          s.wave_v[v] = true
          if v > 0 then pos = true elseif v < 0 then neg = true end
        end
        pw[k] = fx
      else pw[k] = nil end
    end
    if pos and neg then s.both = true end
    s.maxwave = math.max(s.maxwave, w)
    local m = max_line(); s.line = math.max(s.line, m); peak = math.max(peak, m)
  end
  s.frames = rd16(0x300) - s.fc0
  return s
end
local function runs_of(s, st) local t = {}; for _, r in ipairs(s.runs) do if r.st == st then t[#t + 1] = r end end return t end
local function first(s, st) return runs_of(s, st)[1] end
local function maxn(s, st) local m = 0; for _, r in ipairs(runs_of(s, st)) do m = math.max(m, r.n) end return m end
local function minn(s, st) local m = 9999; for _, r in ipairs(runs_of(s, st)) do m = math.min(m, r.n) end return m end
-- the first complete run of st that is neither the first nor the last of the watch
local function full(s, st) local t = runs_of(s, st); for _, r in ipairs(t) do if r ~= s.runs[1] and r ~= s.runs[#s.runs] then return r end end end
local function set_len(t) local n = 0; for _ in pairs(t) do n = n + 1 end return n end

-- Provoke the retaliation smash: wait (player far away) until the oni walks again with its cooldown expired, then hit it with the
-- sword (hp is set to hp0 first, so the phase does not change). Returns at the first STELE frame. The oni is put at x = ox first.
local function bait(ox, hp0)
  wait_until(function() park(); return rd(IAIR) == WALK and rd(FX) == 0 end, 400)
  frames(125)
  wait_until(function() park(); return rd(IAIR) == WALK and rd(EFLASH) == 0 end, 300)
  wr(EX, ox); wr(EDIR, 255); wr(EHP, hp0)
  held = {b = true}
  for _ = 1, 20 do
    wr16(PX, rd(EX) - 14); wr(PY, FLOOR_Y); wr(VY, 0); safe()
    frames(1)
    if rd(IAIR) == STELE then held = {}; return true end
  end
  held = {}
  return false
end

co = coroutine.create(function()
  frames(60)
  check(rd(STATE) == 2, "boot reaches overworld")
  wr16(0x308, 255)                          -- dungeons 1..8 cleared: gate 9 open
  wr16(PX, 816); wr(PY, 80)                 -- door of dungeon 9 (col 51, row 5)
  frames(30)
  hold({a = true}, 3)
  frames(20)
  check(rd(STATE) == 3 and rd(CUR) == 9, "dungeon 9 entered, state=" .. rd(STATE))
  check(rd(BANK) == 8 and rd(0x8000) ~= 0, "oni bank 8 mapped, cur_bank=" .. rd(BANK))

  -- intro: "ONI WARLORD" (O N I _ W A R L O R D = 31 28 13 0 47 37 35 44 31 35 26 at row 10, columns 10..20)
  check(rd(INTRO) > 0, "intro running")
  check(rd(EHP) == 18 and rd(PHASE) == 1 and bar() == "FFFFFFFFFF", "oni: 18 hp, phase 1, full bar")
  check(rd(EW) == 24 and rd(EH) == 32 and rd(EY) == GROUND, "oni is 24x32 on the floor, w=" .. rd(EW) .. " h=" .. rd(EH) .. " y=" .. rd(EY))
  local name = {}
  for c = 10, 20 do name[#name + 1] = ppu(0x2000 + 10 * 32 + c) end
  check(table.concat(name, ",") == "31,28,13,0,47,37,35,44,31,35,26", "name ONI WARLORD on screen: " .. table.concat(name, ","))
  check(rd(OAM_BODY + 1) == 190 and rd(OAM_BODY) < 0xEF, "oni drawn in the intro, phase 1 look (tile 190)")
  local x0 = rd(EX)
  frames(10)
  check(rd(EX) == x0 and rd(IAIR) == 0, "oni frozen during the intro")
  check(wait_until(function() return rd(INTRO) == 0 end, 100), "intro ends")
  frames(3)
  check(ppu(0x2000 + 10 * 32 + 10) == 0, "name erased")
  check(ppu(0x3F15) == 0x16, "phase 1 palette")
  check(ppu(0x3F00) == 0x0F and ppu(0x3F01) == 0x06, "own red/black dungeon palette")

  -- phase 1, standing bot (x 48): walks 1 px/frame, stops 32 px in front, attacks after 330 frames idle, hearts <= 3
  local s = watch(1200, true)
  check(s.frames == 1200, "game loop runs at 60 Hz: 1200 frames -> frame_count +" .. s.frames)
  local w1 = s.runs[1]
  check(w1.st == WALK and w1.x0 >= 150 and w1.x0 <= 160 and w1.xe == 88, "walks toward the player and stops at x 88 (front edge 32 px from the player's center), x " .. w1.x0 .. " -> " .. w1.xe)
  check(w1.n >= 320 and w1.n <= 333, "first attack after ~330 idle frames, walk run " .. w1.n)
  local seen = {}
  for _, r in ipairs(s.runs) do seen[#seen + 1] = r.st end
  print("phase 1 states: " .. table.concat(seen, ","))
  check(s.maxwave <= 1 and not s.both, "phase 1: one shockwave at a time, one direction")
  for y in pairs(s.wave_y) do check(y == 183, "shockwave on the floor (8 px above the floor line 192), y " .. y) end
  for v in pairs(s.wave_v) do check(v == -2, "phase 1 shockwave 2 px/frame toward the player, v " .. v) end
  check(s.line <= 8, "phase 1: max 8 sprites per scanline, got " .. s.line)
  check(s.tile == 190, "phase 1 body tiles")
  local t1 = full(s, STELE)
  check(t1 ~= nil and t1.n >= 28 and t1.n <= 32 and t1.hide[0] and t1.hide[2], "club telegraph ~30 frames, flickering, got " .. (t1 and t1.n))
  local lost1 = s.lost
  check(lost1 <= 3, "phase 1 standing bot loses <= 3 hearts, lost " .. lost1)

  -- reaction smash: telegraph ~30 frames (club up, flickers), smash 6 frames, shockwave from the club, recovery ~40 frames
  check(bait(120, 17), "a sword hit while it walks gets a smash in return")
  wr16(PX, 48); wr(PY, FLOOR_Y); noshots()
  s = watch(260, false)
  local st1, sm, re = first(s, STELE), first(s, SMASH), first(s, REST)
  check(st1 ~= nil and sm ~= nil and re ~= nil, "STELE, SMASH, REST seen")
  check(sm.n == 6, "smash lasts 6 frames, got " .. sm.n)
  check(re.n >= 38 and re.n <= 42, "recovery ~40 frames, got " .. re.n)
  check(re.hide[0] and re.hide[2], "recovery blinks slowly (boss_hide 0 and 2)")
  check(s.club[STELE] and s.club[SMASH] and not s.club[WALK], "club sprites only while raised / smashing")
  local sw = s.waves[1]
  check(sw ~= nil and sw.tile == SHOCK and sw.attr == 1 and sw.st == SMASH, "shockwave spawns in SMASH (tile 189, palette 1)")
  check(s.maxwave == 1, "one wave in phase 1")

  -- shockwave: standing player is hit once, a jumper is not. (bait puts the oni at x 120, wave starts at x 112 going left)
  check(bait(120, 17), "second smash")
  wr16(PX, 48); wr(PY, FLOOR_Y); wr(VY, 0); wr(HEARTS, 3); wr(INV, 0); noshots()
  check(wait_until(function() return rd(FBX) ~= 0 or rd(FBX + 1) ~= 0 end, 80), "a shockwave appears")
  check(wait_until(function() return rd(HEARTS) < 3 end, 80), "the shockwave hits a standing player")
  check(rd(HEARTS) == 2, "exactly one heart, hearts=" .. rd(HEARTS))
  check(bait(120, 17), "third smash")
  wr16(PX, 48); wr(PY, FLOOR_Y); wr(VY, 0); wr(HEARTS, 3); wr(INV, 0); noshots()
  check(wait_until(function() return rd(FBX) ~= 0 or rd(FBX + 1) ~= 0 end, 80), "a shockwave appears again")
  frames(8)
  held = {a = true}
  local gone = wait_until(function() return rd(FBX) == 0 and rd(FBX + 1) == 0 and rd(FBX + 2) == 0 end, 80)
  held = {}
  check(gone and rd(HEARTS) == 3 and rd(INV) == 0, "jumping over the shockwave avoids damage, hearts=" .. rd(HEARTS))
  frames(60)
  -- the shield blocks it from the front
  wr(ABIL, 8)
  check(bait(120, 17), "fourth smash")
  wr16(PX, 48); wr(PY, FLOOR_Y); wr(VY, 0); wr(HEARTS, 3); wr(INV, 0); noshots()
  hold({right = true}, 3)
  held = {down = true}
  check(wait_until(function() return rd(FBX) ~= 0 or rd(FBX + 1) ~= 0 end, 80), "a shockwave appears (shield)")
  local blocked = wait_until(function() return rd(FBX) == 0 and rd(FBX + 1) == 0 and rd(FBX + 2) == 0 end, 80)
  held = {}
  check(blocked and rd(HEARTS) == 3 and rd(SHIELD) == 1 and rd(INV) == 0, "the shield stops the shockwave from the front, hearts=" .. rd(HEARTS))
  wr(ABIL, 0)
  frames(10)

  -- charge, forced: 3 px/frame to the wall, then dazed 40 frames; jumpable; body contact costs a heart
  local function charge(jump)
    wait_until(function() park(); return rd(IAIR) == WALK and rd(FX) == 0 end, 400)
    wr(EX, 100); wr(EDIR, 255); wr(IAIR, CHARGE); noshots()
    wr16(PX, 48); wr(PY, FLOOR_Y); wr(VY, 0); wr(HEARTS, 3); wr(INV, 0)
    local xs = {}
    if jump then held = {a = true} end
    for _ = 1, 40 do frames(1); xs[#xs + 1] = rd(EX) end
    held = {}
    return xs
  end
  local xs = charge(false)
  check(rd(HEARTS) == 2, "a charging oni costs a heart, hearts=" .. rd(HEARTS))
  check(xs[1] == 97 and xs[2] == 94, "charge 3 px/frame, x " .. xs[1] .. "," .. xs[2])
  check(xs[#xs] == 16 and rd(IAIR) == REST, "dazed at the wall (x 16, REST), x=" .. xs[#xs] .. " iair=" .. rd(IAIR))
  frames(5)
  xs = charge(true)
  check(rd(HEARTS) == 3 and rd(INV) == 0, "jumping over the charge avoids damage, hearts=" .. rd(HEARTS))

  -- recovery window: a sword hit during REST costs exactly 1 hp (bar 17/18 = 19 half steps)
  wait_until(function() park(); return rd(IAIR) == REST end, 400)
  wait_until(function() park(); return rd(IAIR) == REST and rd(EX) > 20 end, 400)
  wr(EHP, 18); wr(EFLASH, 0)
  local hp = rd(EHP)
  local hit = false
  for _ = 1, 3 do
    held = {b = true}
    for _ = 1, 3 do wr16(PX, rd(EX) - 14); wr(PY, FLOOR_Y); safe(); frames(1) end
    held = {}
    frames(6)
    if rd(EHP) < hp then hit = true; break end
  end
  check(hit and rd(EHP) == hp - 1, "a hit in the recovery window costs 1 hp, hp " .. hp .. " -> " .. rd(EHP))
  check(bar() == "FFFFFFFFFH", "bar 17/18 = FFFFFFFFFH, got " .. bar())
  park()
  local ek = rd(EX)
  check(ek >= 16 and ek <= 80, "knocked back but still in the arena, x=" .. ek)
  wr(EHP, 18)

  -- phase 2 at hp <= 12 (70 % of 18, rounded down)
  wr(EHP, 13); wr(EFLASH, 0)
  check(strike() == 12 and rd(PHASE) == 2, "hp 12 -> phase 2, phase=" .. rd(PHASE))
  check(wait_until(function() return ppu(0x3F15) == 0x26 end, 80), "phase 2 palette")
  check(wait_until(function() return rd(FX) == 0 end, 60), "phase effect ends")
  check(bar() == "FFFFFFH...." or bar() == "FFFFFFH.." or bar():sub(1, 6) == "FFFFFF", "phase 2 bar " .. bar())
  check(rd(OAM_BODY + 1) == 200, "phase 2 look (tile 200)")
  wr(EX, 160)
  s = watch(1200, true)
  local lost2 = s.lost
  do local t = {}; for _, r in ipairs(s.runs) do t[#t + 1] = r.st end; print("phase 2 states: " .. table.concat(t, ",")) end
  check(s.frames == 1200, "60 Hz: 1200 frames -> +" .. s.frames)
  check(first(s, WALK).n >= 1, "walks again after the phase change")
  check(s.both and s.maxwave == 2, "phase 2: shockwaves in both directions, max " .. s.maxwave)
  for v in pairs(s.wave_v) do check(v == -2 or v == 2, "phase 2 shockwave 2 px/frame, v " .. v) end
  check(s.line <= 8, "phase 2: max 8 sprites per scanline, got " .. s.line)
  check(s.tile == 200, "phase 2 body tiles")
  check(lost2 <= 3, "phase 2 standing bot loses <= 3 hearts, lost " .. lost2)
  local ct = full(s, CTELE)
  if ct then
    check(ct.n >= 26 and ct.n <= 30 and ct.hide[2], "phase 2 charge telegraph ~28 frames flickering, got " .. ct.n)
    local ch = full(s, CHARGE)
    check(ch ~= nil and ch.n >= 8 and math.abs(ch.xe - ch.x0) >= 8 * 4, "charge runs at 4 px/frame")
  end

  -- phase 3 at hp <= 9
  wr(EHP, 10); wr(EFLASH, 0)
  check(strike() == 9 and rd(PHASE) == 3, "hp 9 -> phase 3, phase=" .. rd(PHASE))
  check(wait_until(function() return ppu(0x3F15) == 0x06 end, 80), "phase 3 palette")
  check(wait_until(function() return rd(FX) == 0 end, 60), "phase effect ends")
  check(rd(OAM_BODY + 1) == 210, "phase 3 look (tile 210)")
  wr(EX, 160)
  s = watch(1200, true)
  local lost3 = s.lost
  do local t = {}; for _, r in ipairs(s.runs) do t[#t + 1] = r.st end; print("phase 3 states: " .. table.concat(t, ",")) end
  check(s.tile == 210 and s.line <= 8, "phase 3 body tiles, max 8 sprites per scanline, got " .. s.line)
  check(lost3 <= 3, "phase 3 standing bot loses <= 3 hearts, lost " .. lost3)
  for v in pairs(s.wave_v) do check(v == -3 or v == 3, "phase 3 shockwave 3 px/frame, v " .. v) end

  -- double smash (provoked): STELE 26, SMASH 6, STELE 20, SMASH 6, REST; two forward shockwaves 52 frames apart
  check(bait(120, 9), "phase 3 smash")
  wr16(PX, 48); wr(PY, FLOOR_Y); noshots()
  s = watch(120, false, true)                      -- sword swinging all the time
  held = {}
  check(s.line <= 8, "double smash while the sword swings: max 8 sprites per scanline, got " .. s.line)
  local order = {}
  for _, r in ipairs(s.runs) do order[#order + 1] = r.st end
  local o = table.concat(order, ",")
  check(o:find("2,3,2,3,4", 1, true) ~= nil, "double smash STELE SMASH STELE SMASH REST, states " .. o)
  check(#s.waves == 2 and s.waves[2].fc - s.waves[1].fc >= 20 and not s.both, "two shockwaves in succession, forward only, spawns " .. #s.waves)
  check(first(s, STELE).n >= 24 and first(s, STELE).n <= 28, "first telegraph ~26 frames, got " .. first(s, STELE).n)
  local second = runs_of(s, STELE)[2]
  check(second.n >= 18 and second.n <= 22, "second telegraph ~20 frames, got " .. second.n)

  -- worst case for the sprite budget: double smash (2 shockwaves alive) while the sword swings and throws waves (ability, 3 hearts)
  check(bait(120, 9), "phase 3 smash (worst case)")
  wr(ABIL, 16)
  local pk = peak
  local w = watch(120, false, true)
  held = {}; wr(ABIL, 0); peak = pk
  wave_peak = w.line
  check(w.line <= 9, "worst case (sword wave + 2 shockwaves): max 9 sprites per scanline, got " .. w.line)

  -- leap smash (natural, 1 attack in 4): arc 63 px high toward the player, shockwaves both ways on landing, then recovery
  local leaped
  for _ = 1, 6 do
    wr(EX, 160)
    s = watch(700, false)
    leaped = first(s, LTELE) and first(s, LEAP)
    if leaped then break end
  end
  check(leaped ~= nil and leaped ~= false, "phase 3 sometimes leaps")
  local lt, lp = first(s, LTELE), first(s, LEAP)
  check(lt.n >= 24 and lt.n <= 28 and lt.hide[2], "leap telegraph ~26 frames flickering, got " .. lt.n)
  check(lp.ymin <= GROUND - 55, "leap arc ~63 px high, min y " .. lp.ymin)
  check(lp.n >= 34 and lp.n <= 45, "leap flight ~40 frames, got " .. lp.n)
  check(math.abs(lp.xe - lp.x0) >= 20, "the leap covers ground toward the player, dx " .. (lp.xe - lp.x0))
  local afterleap
  for i, r in ipairs(s.runs) do if r == lp then afterleap = s.runs[i + 1] end end
  check(afterleap == nil or afterleap.st == REST, "REST after the leap")
  if lp.xe >= 40 and lp.xe <= 192 then
    local n, land = 0, lp.fc + lp.n
    for _, w in ipairs(s.waves) do if w.fc >= land - 1 and w.fc <= land + 2 then n = n + 1 end end
    check(n == 2, "two shockwaves (both ways) on landing at x " .. lp.xe .. ", got " .. n)
  end
  check(s.line <= 8, "leap: max 8 sprites per scanline, got " .. s.line)
  wait_until(function() park(); return rd(IAIR) == WALK end, 200)
  check(rd(EY) == GROUND, "back on the floor after the leap, y " .. rd(EY))

  -- victory: hp 1 + hit -> dead, sprites gone, "VICTORY" + "GOT SWORD WAVE", overworld, mask bit 8, ability bit 4, valid save
  wr(EHP, 1); wr(EFLASH, 0)
  check(strike() == 0 and rd(DEAD) == 1, "hp 0 -> boss_dead")
  frames(3)
  check(rd(VICT) > 0 and ppu(0x2000 + 10 * 32 + 12) == 32 and ppu(0x2000 + 10 * 32 + 18) == 36, "'VICTORY' on screen")
  for i = 0, 11 do check(rd(OAM_BODY + 4 * i) == 0xFF, "dead: oni sprite " .. i .. " hidden") end
  check(rd(OAM_E) == 0xFF and nfb() == 0, "dead: no default sprites, no shockwaves")
  frames(3)
  local got = {}
  for c = 9, 22 do got[#got + 1] = ppu(0x2000 + 13 * 32 + c) end
  check(table.concat(got, ",") == "29,31,34,0,38,47,31,35,26,0,47,37,32,30", "'GOT SWORD WAVE' on screen: " .. table.concat(got, ","))
  check(wait_until(function() return rd(STATE) == 2 end, 300), "victory returns to the overworld")
  check(rd16(0x308) == 511, "dungeon 9 cleared (bit 8), mask=" .. rd16(0x308))
  check(rd(ABIL) == 16, "sword wave granted (bit 4), abilities=" .. rd(ABIL))
  check(rd16(PX) == 816 and rd(PY) == 80 and rd(CUR) == 0, "back at entrance 9")
  check(rd(0x6000) == 0x45 and rd(0x6001) == 0x48 and rd(0x6002) == 1 and rd(0x6003) == 255 and rd(0x6004) == 1
        and rd(0x6005) == 16 and rd(0x6006) == 0x9E, "autosave valid")

  print("oni test OK (hearts lost by a standing bot per phase: " .. lost1 .. " / " .. lost2 .. " / " .. lost3 ..
        ", peak sprites per scanline: " .. peak .. ", worst case with sword wave: " .. wave_peak .. ")")
  emu.stop(0)
end)

emu.addEventCallback(function() emu.setInput(held, 0, 0) end, emu.eventType.inputPolled)
emu.addEventCallback(function()
  if coroutine.status(co) == "dead" then return end
  local ok, err = coroutine.resume(co)
  if not ok then print("ERROR: " .. tostring(err)); emu.stop(1) end
end, emu.eventType.endFrame)
