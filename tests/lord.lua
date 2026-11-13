-- Hell lord test (dungeon 10, the final boss): intro name, bank 9, 32x32 own sprites, teleport (fade = untouchable, telegraph =
-- untouchable and harmless, then a long solid window), aimed fireball, phase 2 (flying swoop with telegraph and a rest window,
-- 3-way spread), phase 3 (invisibility: untouchable and not drawn, fireballs still visible; shockwaves on landing; faster),
-- looks, contact, shield, sprites per scanline, 60 Hz loop, standing-bot hearts per phase, victory (mask 1023, valid save).
-- Addresses: docs/TECH.md "Debug-Adressen".
local M = emu.memType.nesMemory
local held = {}
local function rd(a) return emu.read(a, M) end
local function rd16(a) return rd(a) + 256 * rd(a + 1) end
local function wr(a, v) emu.write(a, v, M) end
local function wr16(a, v) wr(a, v % 256); wr(a + 1, v // 256) end
local function ppu(a) return emu.read(a, emu.memType.nesPpuMemory) end
local STATE, PX, PY, CUR = 0x302, 0x303, 0x305, 0x30A
local HEARTS, INV, VY = 0x30B, 0x30C, 0x30F
local EX, EY, EW, EH, EHP, EFLASH = 0x310, 0x311, 0x312, 0x313, 0x314, 0x315
local PHASE, DEAD, INTRO, FBX, FBY, FX = 0x318, 0x319, 0x31A, 0x31B, 0x31E, 0x321
local ABIL, VICT = 0x322, 0x325
local AACT = 0x343                      -- abilities active in this dungeon (set on entry from the demons before it; `abilities` $322 is only the saved progress)
local BANK, HIDE, IAIR, SHIELD = 0x326, 0x327, 0x328, 0x331
local IDLE, FTELE, FADE, GONE, APPEAR, RISE, HOVER, STELE, DIVE, REST = 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
local FLOOR_Y, GROUND = 176, 160
local OAM_FB, OAM_E, OAM_BODY = 0x200 + 52, 0x200 + 24, 0x200 + 72
local FIREBALL, SHOCK = 28, 17          -- SHOCK: common sheet

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
local function body_drawn() local n = 0; for i = 0, 11 do if rd(OAM_BODY + 4 * i) < 0xEF then n = n + 1 end end return n end
local peak = 0

-- one sword hit at the lord (player beside it on its left, no damage); waits for a solid idle moment; returns hp afterwards
local function strike()
  local hp = rd(EHP)
  for _ = 1, 12 do
    wait_until(function() safe(); return rd(IAIR) == IDLE and rd(FX) == 0 and rd(EFLASH) == 0 end, 900)
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
local function watch(n, bot, swing, follow)
  local s = {runs = {}, line = 0, lost = 0, fbs = {}, maxfb = 0, gone_fb = false, gone_hidden = true, gone_n = 0, fc0 = rd16(0x300)}
  local last, pf, rec = nil, {}, {}
  if bot then wr(HEARTS, 3); wr(INV, 0) end
  for i = 1, n do
    if swing then held = {b = i % 16 < 3} end
    if follow then wr(EHP, 13) end                -- the swings hit it: keep it in phase 3
    wr16(PX, follow and math.max(16, rd(EX) - 14) or 48); wr(PY, FLOOR_Y); wr(VY, 0)
    if not bot then safe() end
    frames(1)
    if bot then
      local h = rd(HEARTS)
      if h < 3 then s.lost = s.lost + 3 - h; wr(HEARTS, 3) end
    end
    local st, x, y = rd(IAIR), rd(EX), rd(EY)
    if rd(FX) == 0 then
      if st ~= last then s.runs[#s.runs + 1] = {st = st, n = 0, x0 = x, y0 = y, ymin = y, ymax = y, hide = {}, fc = rd16(0x300),
                                                  maxdy = 0, drawn = false, hidden = false}; last = st end
      local r = s.runs[#s.runs]
      r.n = r.n + 1; r.xe = x; r.ye = y; r.ymin = math.min(r.ymin, y); r.ymax = math.max(r.ymax, y)
      if r.n > 1 then r.hide[rd(HIDE)] = true end     -- the first frame of a state still carries the previous state's boss_hide
      if r.py then r.maxdy = math.max(r.maxdy, y - r.py) end
      r.py = y
      local bd = body_drawn()
      if bd > 0 then r.drawn = true end
      if bd == 0 then r.hidden = true end
      if st == GONE and r.n > 1 then
        s.gone_n = s.gone_n + 1
        if bd > 0 then s.gone_hidden = false end
        if nfb() > 0 then
          for k = 0, 2 do if rd(FBX + k) ~= 0 and rd(OAM_FB + 4 * k) < 0xEF then s.gone_fb = true end end
        end
      end
    end
    local c = 0
    for k = 0, 2 do
      local fx = rd(FBX + k)
      if fx ~= 0 then
        c = c + 1
        if not pf[k] then
          rec[k] = {st = st, x = fx, y = rd(FBY + k), tile = rd(OAM_FB + 4 * k + 1), fc = rd16(0x300), lx = x}
          s.fbs[#s.fbs + 1] = rec[k]
        elseif not rec[k].v then rec[k].v = fx - pf[k] end
        pf[k] = fx
      else pf[k] = nil end
    end
    s.maxfb = math.max(s.maxfb, c)
    local m = max_line(); s.line = math.max(s.line, m); peak = math.max(peak, m)
  end
  s.frames = rd16(0x300) - s.fc0
  return s
end
local function runs_of(s, st) local t = {}; for _, r in ipairs(s.runs) do if r.st == st then t[#t + 1] = r end end return t end
local function first(s, st) return runs_of(s, st)[1] end
-- the first complete run of st that is neither the first nor the last of the watch
local function full(s, st) for _, r in ipairs(runs_of(s, st)) do if r ~= s.runs[1] and r ~= s.runs[#s.runs] then return r end end end
local function only(r, ...) local ok = {}; for _, v in ipairs({...}) do ok[v] = true end; for h in pairs(r.hide) do if not ok[h] then return false end end return true end
local function states(s) local t = {}; for _, r in ipairs(s.runs) do t[#t + 1] = r.st end return table.concat(t, ",") end

-- A sword swing at the lord's position (player overlaps it, hearts safe): returns hp afterwards
local function swing_at(n)
  local hp = rd(EHP)
  held = {b = true}
  for _ = 1, n or 6 do wr16(PX, math.max(16, rd(EX) - 14)); wr(PY, FLOOR_Y); wr(VY, 0); safe(); frames(1) end
  held = {}
  for _ = 1, 4 do wr16(PX, math.max(16, rd(EX) - 14)); wr(PY, FLOOR_Y); wr(VY, 0); safe(); frames(1) end
  return rd(EHP), hp
end
-- Overlap the player with the lord with full hearts, no protection; returns hearts after 4 frames
local function touch()
  wr16(PX, rd(EX) + 8); wr(PY, rd(EY) + 16 > FLOOR_Y and FLOOR_Y or rd(EY) + 16); wr(HEARTS, 3); wr(INV, 0); wr(VY, 0)
  frames(4)
  return rd(HEARTS)
end

co = coroutine.create(function()
  frames(30); held = {start = true}; frames(3); held = {}; frames(20); held = {start = true}; frames(3); held = {}; frames(60)   -- boot menu: Start = NEW GAME (CONTINUE with a save), second Start skips the intro
  check(rd(STATE) == 2, "boot reaches overworld")
  wr16(0x308, 511)                          -- dungeons 1..9 cleared: gate 10 open
  wr16(PX, 912); wr(PY, 48)                 -- door of dungeon 10 (col 57, row 3)
  frames(30)
  hold({a = true}, 3)
  frames(20)
  check(rd(STATE) == 3 and rd(CUR) == 10, "dungeon 10 entered, state=" .. rd(STATE))
  check(rd(BANK) == 9 and rd(0x8000) ~= 0, "hell lord bank 9 mapped, cur_bank=" .. rd(BANK))

  -- intro: "HELL LORD" (H E L L _ L O R D = 39 30 44 44 0 44 31 35 26 at row 10, columns 11..19)
  check(rd(INTRO) > 0, "intro running")
  check(rd(EHP) == 26 and rd(PHASE) == 1 and bar() == "FFFFFFFFFF", "lord: 26 hp, phase 1, full bar")
  check(rd(EW) == 32 and rd(EH) == 32 and rd(EY) == GROUND, "lord is 32x32 on the floor, w=" .. rd(EW) .. " h=" .. rd(EH) .. " y=" .. rd(EY))
  local name = {}
  for c = 11, 19 do name[#name + 1] = ppu(0x2000 + 10 * 32 + c) end
  check(table.concat(name, ",") == "39,30,44,44,0,44,31,35,26", "name HELL LORD on screen: " .. table.concat(name, ","))
  check(body_drawn() == 12 and rd(OAM_BODY + 1) == 0x40 and rd(OAM_BODY + 2) == 1 and rd(OAM_BODY + 6) == 0x41, "lord drawn in the intro: 12 sprites, mirrored halves, boss tile 0")
  check(rd(OAM_E) == 0xFF, "no default boss sprites (own drawing)")
  local x0 = rd(EX)
  frames(10)
  check(rd(EX) == x0 and rd(IAIR) == 0, "lord frozen during the intro")
  check(wait_until(function() return rd(INTRO) == 0 end, 100), "intro ends")
  frames(3)
  check(ppu(0x2000 + 10 * 32 + 11) == 0, "name erased")
  check(ppu(0x3F16) == 0x16, "phase 1 palette")
  check(ppu(0x3F00) == 0x0F and ppu(0x3F01) == 0x05 and ppu(0x3F03) == 0x38, "own deep red / black / yellow dungeon palette")

  -- phase 1, standing bot (x 48): teleport + single aimed fireballs, hearts <= 3
  local s = watch(1200, true)
  check(s.frames == 1200, "game loop runs at 60 Hz: 1200 frames -> frame_count +" .. s.frames)
  print("phase 1 states: " .. states(s))
  local ft, fd, ap, id = full(s, FTELE), full(s, FADE), full(s, APPEAR), full(s, IDLE)
  check(ft and ft.n >= 20 and ft.n <= 24 and ft.hide[0] and ft.hide[2] and only(ft, 0, 2), "fireball warning ~22 frames, flickers, hittable (boss_hide 0 and 2), got " .. (ft and ft.n))
  check(fd and fd.n >= 18 and fd.n <= 22 and only(fd, 1, 3) and fd.hide[3], "teleport fade ~20 frames, untouchable (boss_hide 1 / 3), got " .. (fd and fd.n))
  check(ap and ap.n >= 28 and ap.n <= 32 and only(ap, 1, 3) and ap.drawn and ap.hidden, "reappear telegraph ~30 frames, flickers, untouchable and harmless, got " .. (ap and ap.n))
  check(id and id.n >= 128 and id.n <= 132 and only(id, 0) and id.drawn and not id.hidden, "solid window ~130 frames after every action, got " .. (id and id.n))
  local moved = false
  for _, r in ipairs(runs_of(s, FADE)) do
    local a = runs_of(s, APPEAR)
    for _, q in ipairs(a) do if q.fc > r.fc and q.fc - r.fc <= 25 and math.abs(q.x0 - r.xe) >= 24 then moved = true end end
  end
  check(moved, "the teleport lands on a different spot")
  for _, r in ipairs(runs_of(s, APPEAR)) do
    check(r.x0 + 16 - 56 >= 56 or 56 - (r.x0 + 16) >= 56, "teleport never lands within 56 px of the player, x " .. r.x0)
    check(r.y0 == GROUND, "lands on the floor")
  end
  check(s.maxfb <= 1, "phase 1: one fireball at a time")
  check(#s.fbs >= 2, "phase 1 fires aimed fireballs, got " .. #s.fbs)
  for _, f in ipairs(s.fbs) do
    check(f.st == IDLE or f.st == FTELE, "fireball leaves after the warning")
    check(f.tile == FIREBALL and f.v == -3 and f.y >= 170 and f.y <= 182, "aimed fireball: tile 28, 3 px/frame toward the bot, on its height, got v=" .. tostring(f.v) .. " y=" .. f.y)
  end
  check(s.line <= 8, "phase 1: max 8 sprites per scanline, got " .. s.line)
  local lost1 = s.lost
  check(lost1 <= 4, "phase 1 standing bot loses <= 4 hearts, lost " .. lost1)

  -- untouchable while fading / reappearing, harmless then; hittable while it warns; contact costs exactly one heart
  for _, st in ipairs({FADE, APPEAR}) do
    wait_until(function() park(); return rd(IAIR) == st and rd(FX) == 0 end, 900)
    wr(EFLASH, 0)
    local hp1, hp0 = swing_at(6)
    check(hp1 == hp0, "state " .. st .. ": a sword swing does nothing, hp " .. hp0 .. " -> " .. hp1)
    wr(EFLASH, 0)
    check(touch() == 3, "state " .. st .. ": no contact damage, hearts=" .. rd(HEARTS))
    park()
  end
  wait_until(function() park(); return rd(IAIR) == FTELE end, 900)
  wr(EFLASH, 0)
  local hp1, hp0 = swing_at(6)
  check(hp1 == hp0 - 1, "warning flicker is hittable: exactly 1 hp, hp " .. hp0 .. " -> " .. hp1)
  wr(EHP, 26); wr(EFLASH, 0)
  wait_until(function() park(); return rd(IAIR) == IDLE and rd(EFLASH) == 0 end, 300)
  check(touch() == 2 and rd(INV) > 80, "contact costs exactly one heart and starts invulnerability, hearts=" .. rd(HEARTS))
  for _ = 1, 30 do wr16(PX, rd(EX) + 8); frames(1) end
  check(rd(HEARTS) == 2, "no second loss while invulnerable, hearts=" .. rd(HEARTS))
  park()
  check(bar() == "FFFFFFFFFF", "bar full at 26 hp, got " .. bar())

  -- the shield stops its fireball from the front
  wr(AACT, 8)
  wait_until(function() park(); return rd(IAIR) == FTELE and rd(FX) == 0 end, 900)
  noshots()
  hold({right = true}, 3)
  held = {down = true}
  safe(); wr(INV, 0); wr(HEARTS, 3)
  local seen = wait_until(function() wr16(PX, 48); wr(PY, FLOOR_Y); wr(INV, 0); return nfb() > 0 end, 80)
  check(seen, "fireball leaves (shield test)")
  local blocked = wait_until(function() wr16(PX, 48); wr(PY, FLOOR_Y); wr(INV, 0); return nfb() == 0 end, 120)
  held = {}
  check(blocked and rd(HEARTS) == 3 and rd(SHIELD) == 1 and rd(INV) == 0, "the shield stops the aimed fireball from the front, hearts=" .. rd(HEARTS))
  wr(AACT, 0)
  frames(5)

  -- phase 2 at hp <= 18 (70 % of 26)
  wr(EHP, 19); wr(EFLASH, 0)
  check(strike() == 18 and rd(PHASE) == 2, "hp 18 -> phase 2, phase=" .. rd(PHASE))
  check(wait_until(function() return ppu(0x3F16) == 0x15 end, 80), "phase 2 palette")
  check(wait_until(function() return rd(FX) == 0 end, 60), "phase effect ends")
  check(bar() == "FFFFFFF..." or bar():sub(1, 7) == "FFFFFFF", "phase 2 bar (18/26) " .. bar())
  check(rd(OAM_BODY + 1) == 0x46, "phase 2 look (boss tile 6)")
  s = watch(1200, true)
  local lost2 = s.lost
  print("phase 2 states: " .. states(s))
  check(s.frames == 1200, "60 Hz: 1200 frames -> +" .. s.frames)
  check(s.line <= 8, "phase 2: max 8 sprites per scanline, got " .. s.line)
  check(lost2 <= 4, "phase 2 standing bot loses <= 4 hearts, lost " .. lost2)
  local ri, ho, st, dv, rs = full(s, RISE), full(s, HOVER), full(s, STELE), full(s, DIVE), full(s, REST)
  check(ri and ho and st and dv and rs, "swoop states RISE HOVER STELE DIVE REST seen (" .. states(s) .. ")")
  check(ri.y0 == GROUND or ri.y0 >= 100, "the swoop starts from the floor, y " .. ri.y0)
  check(ho.n >= 43 and ho.n <= 47 and ho.ymin >= 56 and ho.ymax <= 64, "hovers ~45 frames in the upper half (y 56..63), got n=" .. ho.n .. " y " .. ho.ymin .. ".." .. ho.ymax)
  check(st.n >= 26 and st.n <= 30 and st.hide[0] and st.hide[2] and only(st, 0, 2), "swoop warning ~28 frames, flickers, hittable, got " .. st.n)
  check(dv.maxdy == 6 and dv.ye >= GROUND - 6 and rs.y0 == GROUND and dv.n >= 15 and dv.n <= 24, "dive 6 px/frame down to the floor, maxdy " .. dv.maxdy .. " n " .. dv.n)
  check(math.abs(dv.xe - 40) <= 4, "the dive lands on the player's x (bot at 48 -> lord x 40), x " .. dv.xe)
  check(rs.n >= 32 and rs.n <= 36 and only(rs, 0, 2) and rs.hide[2] and rs.y0 == GROUND, "rests ~34 frames on the floor, blinking slowly, hittable, got " .. rs.n)
  check(s.maxfb >= 3, "phase 2 fires a 3-way spread, max fireballs at once " .. s.maxfb)
  local sp = {}
  for _, f in ipairs(s.fbs) do if f.st == IDLE or f.st == FTELE then sp[f.fc] = sp[f.fc] or {}; table.insert(sp[f.fc], f) end end
  local spread
  for _, t in pairs(sp) do if #t == 3 then spread = t end end
  check(spread ~= nil, "three fireballs leave in the same frame")
  local ys = {}
  for _, f in ipairs(spread) do ys[f.y] = true end
  check(ys[spread[1].y] and #spread == 3 and (function() local n = 0; for _ in pairs(ys) do n = n + 1 end return n end)() == 3, "the spread starts on three different scanline groups")

  -- a hit in the rest window costs exactly 1 hp; a hit while it dives or hovers is allowed too (only fade/appear are untouchable)
  wr(EHP, 18); wr(EFLASH, 0)
  wait_until(function() park(); return rd(IAIR) == REST and rd(FX) == 0 end, 900)
  wr(EFLASH, 0)
  hp1, hp0 = swing_at(4)
  check(hp1 == hp0 - 1, "a hit in the rest window costs 1 hp, hp " .. hp0 .. " -> " .. hp1)
  wr(EHP, 18); wr(EFLASH, 0)
  -- a diving lord costs a heart
  wait_until(function() park(); return rd(IAIR) == STELE and rd(FX) == 0 end, 1500)
  wait_until(function() park(); return rd(IAIR) == DIVE end, 60)
  wr16(PX, rd(EX) + 8); wr(PY, FLOOR_Y); wr(HEARTS, 3); wr(INV, 0)
  frames(30)
  check(rd(HEARTS) == 2, "the dive hits a player below it, hearts=" .. rd(HEARTS))
  park()

  -- phase 3 at hp <= 13
  wr(EHP, 14); wr(EFLASH, 0)
  check(strike() == 13 and rd(PHASE) == 3, "hp 13 -> phase 3, phase=" .. rd(PHASE))
  check(wait_until(function() return ppu(0x3F16) == 0x06 end, 80), "phase 3 palette")
  check(wait_until(function() return rd(FX) == 0 end, 60), "phase effect ends")
  check(rd(OAM_BODY + 1) == 0x4C, "phase 3 look (boss tile 12)")
  s = watch(1200, true)
  local lost3 = s.lost
  print("phase 3 states: " .. states(s))
  check(s.frames == 1200, "60 Hz: 1200 frames -> +" .. s.frames)
  check(s.line <= 9, "phase 3: max 9 sprites per scanline, got " .. s.line)
  check(lost3 <= 4, "phase 3 standing bot loses <= 4 hearts, lost " .. lost3)
  local gn = full(s, GONE)
  check(gn and gn.n >= 108 and gn.n <= 112 and only(gn, 3), "invisible ~110 frames, untouchable (boss_hide 3), got " .. (gn and gn.n))
  check(s.gone_hidden and s.gone_n > 0, "while invisible no body sprite is drawn")
  check(s.gone_fb, "its fireballs still show while it is invisible")
  local ap3 = full(s, APPEAR)
  check(ap3 and ap3.n >= 28 and ap3.n <= 32 and only(ap3, 1, 3) and ap3.drawn and ap3.hidden, "telegraph before it reappears, flickers, untouchable")
  local d3, r3 = full(s, DIVE), full(s, REST)
  check(d3 and d3.maxdy == 7 and r3, "phase 3 dive 7 px/frame, maxdy " .. (d3 and d3.maxdy))
  local waves, wl, wr_ = 0, false, false
  for _, f in ipairs(s.fbs) do
    if f.tile == SHOCK then
      waves = waves + 1
      check(f.y == 183 and (f.v == 4 or f.v == -4), "shockwave low on the floor, 4 px/frame, y " .. f.y .. " v " .. tostring(f.v))
      if f.v == 4 then wr_ = true else wl = true end
    else check(f.v == nil or f.v == 4 or f.v == -4 or f.v == 1 or f.v == -1, "fireball 4 px/frame in phase 3, v " .. tostring(f.v)) end
  end
  check(waves >= 2 and wl and wr_, "landing sends a shockwave both ways, waves " .. waves)

  -- invisible = untouchable: a swing and contact at its spot do nothing
  wait_until(function() park(); return rd(IAIR) == GONE and rd(FX) == 0 end, 1200)
  wr(EFLASH, 0)
  hp1, hp0 = swing_at(6)
  check(hp1 == hp0, "invisible: a sword swing does nothing, hp " .. hp0 .. " -> " .. hp1)
  check(touch() == 3, "invisible: no contact damage, hearts=" .. rd(HEARTS))
  park()
  -- shockwave: a player standing on the floor is hit, a jumper is not (the lord is held at x 200, the player waits at x 30)
  local function landing()                       -- wait for the next dive and hold the lord far away; returns at the first REST frame
    wait_until(function() park(); return rd(IAIR) == STELE and rd(FX) == 0 end, 1200)
    wait_until(function() park(); return rd(IAIR) == DIVE end, 60)
    while rd(IAIR) == DIVE do wr(EX, 200); wr16(PX, 30); wr(PY, FLOOR_Y); wr(VY, 0); safe(); frames(1) end
    check(rd(IAIR) == REST, "dive ends")
    wr(HEARTS, 3); wr(INV, 0)
  end
  landing()
  local hit = wait_until(function() wr16(PX, 30); wr(PY, FLOOR_Y); return rd(HEARTS) < 3 end, 80)
  check(hit, "a shockwave hits a player standing on the floor")
  park()
  landing()
  local sawwave, jumped = false, 0
  for _ = 1, 80 do
    for i = 0, 2 do if rd(FBX + i) ~= 0 then sawwave = true; if rd(FBX + i) < 80 and jumped == 0 then jumped = 1 end end end
    if jumped > 0 and jumped < 24 then jumped = jumped + 1 end
    held = {a = jumped > 0 and jumped < 24}              -- A held: a full jump
    frames(1)
  end
  held = {}
  check(sawwave and jumped > 0 and rd(HEARTS) == 3, "jumping the shockwave avoids damage, hearts=" .. rd(HEARTS))
  park(); noshots()

  -- worst case for the sprite budget: the player glued to the lord's side, sword swinging all the time, through spreads, waves, swoops
  local pk = peak
  s = watch(900, false, true, true)
  held = {}
  check(s.line <= 9, "worst case (sword + shockwaves + fireballs): max 9 sprites per scanline, got " .. s.line)
  local worst = s.line
  peak = pk
  park(); frames(30)                        -- the last swing of the worst-case run is over (it would kill the lord at 1 hp)

  -- victory: hp 1 + hit -> dead, sprites gone, "VICTORY" and no ability, overworld, all 10 dungeons cleared (mask 1023), valid save
  wr(EHP, 1); wr(EFLASH, 0)
  check(strike() == 0 and rd(DEAD) == 1, "hp 0 -> boss_dead")
  frames(3)
  check(rd(VICT) > 0 and ppu(0x2000 + 10 * 32 + 12) == 32 and ppu(0x2000 + 10 * 32 + 18) == 36, "'VICTORY' on screen")
  for i = 0, 11 do check(rd(OAM_BODY + 4 * i) == 0xFF, "dead: lord sprite " .. i .. " hidden") end
  check(rd(OAM_E) == 0xFF and nfb() == 0, "dead: no default sprites, no fireballs")
  frames(3)
  for c = 9, 22 do check(ppu(0x2000 + 13 * 32 + c) == 0, "no 'GOT' text: the last demon gives no ability") end
  check(wait_until(function() return rd(STATE) == 4 end, 300), "victory of dungeon 10 shows the ending screen")
  emu.write(0x336, 100, emu.memType.nesMemory); hold({start = true}, 3)
  check(wait_until(function() return rd(STATE) == 2 end, 20), "Start leaves the ending screen")
  check(rd16(0x308) == 1023, "all 10 dungeons cleared, mask=" .. rd16(0x308))
  check(rd(ABIL) == 0, "no ability granted, abilities=" .. rd(ABIL))
  check(rd16(PX) == 912 and rd(PY) == 48 and rd(CUR) == 0, "back at entrance 10")
  check(rd(0x6000) == 0x45 and rd(0x6001) == 0x48 and rd(0x6002) == 1 and rd(0x6003) == 255 and rd(0x6004) == 0x83
        and rd(0x6005) == 0 and rd(0x6006) == 0x10, "autosave valid")

  print("lord test OK (hearts lost by a standing bot per phase: " .. lost1 .. " / " .. lost2 .. " / " .. lost3 ..
        ", peak sprites per scanline: " .. peak .. ", worst case: " .. worst .. ")")
  emu.stop(0)
end)

emu.addEventCallback(function() emu.setInput(held, 0, 0) end, emu.eventType.inputPolled)
emu.addEventCallback(function()
  if coroutine.status(co) == "dead" then return end
  local ok, err = coroutine.resume(co)
  if not ok then print("ERROR: " .. tostring(err)); emu.stop(1) end
end, emu.eventType.endFrame)
