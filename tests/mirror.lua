-- Mirror demon test (dungeon 6): intro name, bank 5, teleport (fade out, new spot, flicker in), untouchable while fading,
-- fake copies per phase (harmless, pop on a hit, original has other head tiles), only the original takes damage (sword and
-- player fireball), phases (look, palette, copy count), projectile, contact, sprites per scanline, standing-bot hearts,
-- victory (mask bit 5, no new ability), valid save. Addresses: docs/TECH.md "Debug-Adressen".
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
local BANK, HIDE, IAIR, PFX = 0x326, 0x327, 0x328, 0x329
local MCX, MCUR = 0x32C, 0x32F
local WALK, OUT, IN = 1, 2, 3
local FLOOR_Y = 176
local OAM_HEAD, OAM_COPY = 0x200 + 24, 0x200 + 140
local SY = {[0] = 168, 128, 128, 88}           -- demon y per spot

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
local function ncopies() local n = 0; for i = 0, 2 do if rd(MCX + i) ~= 0 then n = n + 1 end end return n end
local function safe() wr(HEARTS, 3); wr(INV, 99) end
-- y of copy k from its OAM (waits out the warn flicker, when it is not drawn)
local function copy_y(k)
  wait_until(function() safe(); wr16(PX, 48); wr(PY, FLOOR_Y); return rd(OAM_COPY + 24 * k) ~= 0xFF end, 20)
  return rd(OAM_COPY + 24 * k) + 1
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
local maxline, peak = 0, 0
-- player (facing right) just left of x, floating at height y, sword box over a demon at (x, y); no damage
local function align(x, y)
  wr16(PX, math.max(16, x - 14)); wr(PY, y); wr(0x30F, 0); safe()
end
-- wait until the demon is solid and walking, then swing at it; returns hp afterwards (retries a few times)
local function strike()
  local hp = rd(EHP)
  for _ = 1, 8 do
    wait_until(function() safe(); wr16(PX, 48); wr(PY, FLOOR_Y); return rd(IAIR) == WALK and rd(FX) == 0 and rd(EFLASH) == 0 end, 900)
    held = {b = true}
    for _ = 1, 3 do align(rd(EX), rd(EY)); frames(1); maxline = math.max(maxline, max_line()) end
    held = {}
    for _ = 1, 6 do align(rd(EX), rd(EY)); frames(1); maxline = math.max(maxline, max_line()) end
    if rd(EHP) ~= hp then break end
  end
  wr16(PX, 48); wr(PY, FLOOR_Y)
  return rd(EHP)
end
-- Watch n frames with the player parked on the floor at x = 48 and safe.
local function watch(n)
  local s = {runs = {}, starts = {}, hides = {}, spawns = 0, volley = 0, line = 0, maxfb = 0, fbdx = {}, walkd = 0, walkn = 0}
  local last, prev, ex = nil, {}, rd(EX)
  for i = 0, 2 do prev[i] = rd(FBX + i) end
  for _ = 1, n do
    frames(1)
    safe(); wr16(PX, 48); wr(PY, FLOOR_Y)
    local st, x = rd(IAIR), rd(EX)
    if rd(FX) == 0 then
      if st ~= last then
        s.runs[#s.runs + 1] = {st = st, n = 0}
        if st == WALK then s.starts[#s.starts + 1] = {spot = rd(MCUR), n = ncopies(), x = x, y = rd(EY)} end
        last = st
      end
      local r = s.runs[#s.runs]; r.n = r.n + 1
      if st == OUT or st == IN then s.hides[rd(HIDE)] = true end
      if st == WALK then
        s.hides[rd(HIDE)] = true
        if r.n > 1 then s.walkd = s.walkd + math.abs(x - ex); s.walkn = s.walkn + 1 end
      end
    end
    ex = x
    local new = 0
    for i = 0, 2 do
      local v = rd(FBX + i)
      if v ~= 0 and prev[i] == 0 then new = new + 1 end
      if v ~= 0 and prev[i] ~= 0 then s.fbdx[v - prev[i]] = true end
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
local function shortest_inner(s, st)
  local m = 999
  for i = 2, #s.runs - 1 do if s.runs[i].st == st and s.runs[i].n < m then m = s.runs[i].n end end
  return m
end
local function seq_ok(s)                      -- WALK, OUT, IN, WALK repeating
  local nxt = {[WALK] = OUT, [OUT] = IN, [IN] = WALK}
  for i = 1, #s.runs - 1 do if nxt[s.runs[i].st] ~= s.runs[i + 1].st then return false end end
  return #s.runs >= 4
end
local function spots_change(s)
  for i = 2, #s.starts do if s.starts[i].spot == s.starts[i - 1].spot then return false end end
  return #s.starts >= 3
end
-- standing bot: no input at x = 48 on the floor; hearts lost (hearts are refilled so the fight never restarts)
local function bot(n)
  local lost = 0
  wr(INV, 0); wr(HEARTS, 3)
  for _ = 1, n do
    frames(1)
    wr16(PX, 48); wr(PY, FLOOR_Y)
    if rd(HEARTS) < 3 then lost = lost + 3 - rd(HEARTS); wr(HEARTS, 3) end
    maxline = math.max(maxline, max_line())
  end
  return lost
end

co = coroutine.create(function()
  frames(10); held = {start = true}; frames(3); held = {}; frames(60)   -- boot menu: Start = NORMAL
  check(rd(STATE) == 2, "boot reaches overworld")
  wr16(0x308, 31)                         -- dungeons 1-5 cleared: gate 6 open
  wr16(PX, 528); wr(PY, 48)               -- door of dungeon 6
  frames(30)
  hold({a = true}, 3)
  frames(20)
  check(rd(STATE) == 3 and rd(CUR) == 6, "dungeon 6 entered, state=" .. rd(STATE))
  check(rd(BANK) == 5 and rd(0x8000) ~= 0, "mirror bank 5 mapped, cur_bank=" .. rd(BANK))

  -- intro: "MIRROR DEMON" = M I R R O R _ D E M O N = tiles 14 13 35 35 31 35 0 26 30 14 31 28 at row 10, columns 10..21
  check(rd(INTRO) > 0, "intro running")
  check(rd(EHP) == 14 and rd(PHASE) == 1 and bar() == "FFFFFFFFFF", "mirror demon: 14 hp, phase 1, full bar")
  local name = {}
  for c = 10, 21 do name[#name + 1] = ppu(0x2000 + 10 * 32 + c) end
  check(table.concat(name, ",") == "14,13,35,35,31,35,0,26,30,14,31,28", "name MIRROR DEMON on screen: " .. table.concat(name, ","))
  local x0, y0 = rd(EX), rd(EY)
  frames(10)
  check(rd(EX) == x0 and rd(EY) == y0 and rd(IAIR) == 0, "demon frozen during the intro")
  check(rd(0x312) == 16 and rd(0x313) == 24, "16x24 demon")
  check(wait_until(function() return rd(INTRO) == 0 end, 100), "intro ends")
  hold({right = true}, 2)                 -- face right

  -- phase 1 standing bot: <= 3 hearts per 1200 frames
  local lost1 = bot(1200)
  check(lost1 <= 3, "phase 1 standing bot loses <= 3 hearts, lost " .. lost1)

  -- phase 1: walk, fade out (20 frames, flicker, untouchable), new spot, flicker in (24 frames), one copy, a slow shot
  local s = watch(1300)
  check(seq_ok(s), "cycle WALK, OUT, IN, WALK")
  check(longest(s, OUT) >= 19 and longest(s, OUT) <= 21, "fade out ~20 frames, got " .. longest(s, OUT))
  check(shortest_inner(s, IN) >= 23 and longest(s, IN) <= 25, "flicker in ~24 frames, got " .. longest(s, IN))
  check(longest(s, WALK) >= 238 and longest(s, WALK) <= 242, "phase 1 walks ~240 frames, got " .. longest(s, WALK))
  check(s.hides[1] and s.hides[3] and s.hides[2] and s.hides[0], "flicker: boss_hide 1 and 3 while fading, 0 and 2 (warn) while walking")
  check(spots_change(s), "every teleport lands on another spot")
  for i, w in ipairs(s.starts) do
    check(w.n == 1, "phase 1: exactly 1 copy, got " .. w.n .. " at start " .. i)
    check(w.y == SY[w.spot], "original stands on its spot, y=" .. w.y .. " spot " .. w.spot)
  end
  local sp1 = s.walkd / s.walkn           -- average over all spots: platforms clamp it, so well below the 0.5 px/frame set
  check(sp1 > 0.1 and sp1 < 0.6, "phase 1 walks slowly (0.5 px/frame max), got " .. sp1)
  check(s.spawns >= 2 and s.volley == 1 and s.maxfb == 1, "phase 1 shoots single shots, spawns " .. s.spawns)
  check(s.fbdx[1] or s.fbdx[-1], "projectile is slow (1 px/frame)")
  check(not s.fbdx[2] and not s.fbdx[-2], "projectile is not faster than 1 px/frame")
  check(s.line <= 8, "max 8 sprites per scanline, got " .. s.line)

  -- the original has other head tiles than the copy (copy: dull eyes)
  check(wait_until(function() safe(); wr16(PX, 48); wr(PY, FLOOR_Y); return rd(IAIR) == WALK end, 400), "walking")
  check(rd(OAM_HEAD + 1) == 0x40 and rd(OAM_COPY + 1) == 0x40 + 18 and rd(OAM_COPY + 5) == 0x40 + 19, "original head tile 0x40, copy head tiles 0x52/0x53")
  check(rd(OAM_COPY + 9) == 0x40 + 2, "copy body uses the demon's body tiles")

  -- untouchable while fading: no damage to it, no contact damage from it
  check(wait_until(function() safe(); wr16(PX, 48); wr(PY, FLOOR_Y); return rd(IAIR) == OUT end, 400), "fading out")
  local hp = rd(EHP)
  wr(INV, 0); wr(HEARTS, 3); wr(EFLASH, 0)
  held = {b = true}
  for _ = 1, 4 do wr16(PX, math.max(16, rd(EX) - 14)); wr(PY, rd(EY)); wr(INV, 0); frames(1) end
  held = {}
  check(rd(EHP) == hp and rd(HEARTS) == 3, "fading: no damage dealt or taken, hp=" .. rd(EHP) .. " hearts=" .. rd(HEARTS))
  check(wait_until(function() return rd(IAIR) == IN end, 40), "appearing")
  wr(HEARTS, 3); wr(INV, 0); wr(EFLASH, 0)
  held = {b = true}
  for _ = 1, 4 do wr16(PX, math.max(16, rd(EX) - 14)); wr(PY, rd(EY)); wr(INV, 0); frames(1) end
  held = {}
  check(rd(EHP) == hp and rd(HEARTS) == 3, "flicker in: still untouchable, hp=" .. rd(EHP))

  -- copies are harmless and pop when hit; hp stays
  check(wait_until(function() safe(); wr16(PX, 48); wr(PY, FLOOR_Y); return rd(IAIR) == WALK end, 400), "walking again")
  wr(EFLASH, 0)
  local k = 0
  for i = 0, 2 do if rd(MCX + i) ~= 0 then k = i end end
  local cyy = copy_y(k)
  wr(INV, 0); wr(HEARTS, 3)
  for _ = 1, 4 do wr16(PX, rd(MCX + k)); wr(PY, cyy); wr(0x30F, 0); wr(INV, 0); frames(1) end
  check(rd(HEARTS) == 3, "touching a copy is harmless, hearts=" .. rd(HEARTS))
  check(ncopies() == 1, "touching does not pop a copy")
  hp = rd(EHP)
  held = {b = true}
  for _ = 1, 3 do align(rd(MCX + k), cyy); frames(1) end
  held = {}
  frames(2)
  check(ncopies() == 0 and rd(EHP) == hp and rd(HEARTS) == 3, "sword pops the copy, original hp unchanged, copies=" .. ncopies() .. " hp=" .. rd(EHP))
  check(rd(OAM_COPY + 24 * k) == 0xFF, "popped copy is not drawn")

  -- the original: a sword hit costs exactly 1 hp, bar 19 half steps
  hp = strike()
  check(hp == 13 and bar() == "FFFFFFFFFH", "sword hit on the original = exactly 1 hp, bar=" .. bar() .. " hp=" .. hp)
  check(maxline <= 8, "sword swing + overlap: max 8 sprites per scanline, got " .. maxline)

  -- player fireball (ability bit 2): pops a copy, hurts the original by exactly 1
  wr(ABIL, 4); wr(EFLASH, 0)
  check(wait_until(function() safe(); wr16(PX, 48); wr(PY, FLOOR_Y); return rd(IAIR) == OUT end, 400), "next teleport")
  check(wait_until(function() safe(); wr16(PX, 48); wr(PY, FLOOR_Y); return rd(IAIR) == WALK end, 100), "walking")
  k = 0
  for i = 0, 2 do if rd(MCX + i) ~= 0 then k = i end end
  cyy = copy_y(k)
  hp = rd(EHP)
  for _ = 1, 3 do
    wr16(PX, math.max(16, rd(MCX + k) - 40)); wr(PY, cyy); wr(0x30F, 0); safe(); frames(1)
    if rd(MCX + k) == 0 then break end
    hold({up = true, b = true}, 3)
    if rd(MCX + k) == 0 then break end
    wait_until(function() wr16(PX, math.max(16, rd(MCX + k) - 40)); wr(PY, cyy); wr(0x30F, 0); safe(); return rd(PFX) == 0 end, 60)
    if rd(MCX + k) == 0 then break end
    frames(40)
  end
  check(rd(MCX + k) == 0 and rd(EHP) == hp, "fireball pops the copy, original hp unchanged, hp=" .. rd(EHP))
  hp = rd(EHP)
  local got = false
  for _ = 1, 8 do
    wait_until(function() safe(); wr16(PX, 48); wr(PY, FLOOR_Y); return rd(IAIR) == WALK and rd(EFLASH) == 0 end, 900)
    for _ = 1, 3 do
      align(math.max(16, rd(EX) - 26), rd(EY)); frames(1)
      hold({up = true, b = true}, 3)
      wait_until(function() align(math.max(16, rd(EX) - 26), rd(EY)); return rd(PFX) == 0 end, 60)
      if rd(EHP) ~= hp then got = true; break end
      frames(40)
    end
    if got then break end
  end
  check(rd(EHP) == hp - 1, "fireball hits the original for exactly 1 hp, hp=" .. rd(EHP))
  wr(ABIL, 0)

  -- contact with the original costs exactly one heart, the invulnerability protects afterwards
  check(wait_until(function() safe(); wr16(PX, 48); wr(PY, FLOOR_Y); return rd(IAIR) == WALK and rd(EFLASH) == 0 end, 900), "walking")
  wr(INV, 0); wr(HEARTS, 3); wr16(PX, rd(EX)); wr(PY, rd(EY)); wr(0x30F, 0); frames(2)
  check(rd(HEARTS) == 2 and rd(INV) > 80, "contact costs a heart, hearts=" .. rd(HEARTS))
  wr16(PX, rd(EX)); wr(PY, rd(EY)); frames(5)
  check(rd(HEARTS) == 2, "no second loss while invulnerable")

  -- phase 2 at hp <= 9: look, palette, 2 copies, faster, standing bot
  wr(EHP, 10); wr(EFLASH, 0)
  check(strike() == 9 and rd(PHASE) == 2, "hp 9 -> phase 2, phase=" .. rd(PHASE))
  frames(2)
  check(bar() == "FFFFFFH...", "bar 13 steps at hp 9, bar=" .. bar())
  check(rd(OAM_HEAD + 1) == 0x40 + 6, "phase 2 look (boss tile 6)")
  check(wait_until(function() return ppu(0x3F15) == 0x34 end, 80), "phase 2 palette")
  check(wait_until(function() return rd(FX) == 0 end, 60), "phase effect ends")
  local lost2 = bot(1200)
  check(lost2 <= 3, "phase 2 standing bot loses <= 3 hearts, lost " .. lost2)
  s = watch(1100)
  check(seq_ok(s) and spots_change(s), "phase 2: teleports to new spots")
  for i, w in ipairs(s.starts) do check(w.n == 2, "phase 2: exactly 2 copies, got " .. w.n .. " at start " .. i) end
  check(longest(s, WALK) >= 188 and longest(s, WALK) <= 192, "phase 2 walks ~190 frames, got " .. longest(s, WALK))
  local sp = s.walkd / s.walkn
  check(sp > sp1 * 1.2 and sp < 0.8, "phase 2 walks faster (0.75 px/frame max), got " .. sp .. " vs " .. sp1)
  check(s.spawns >= 3 and s.volley == 1, "phase 2 shoots single shots, spawns " .. s.spawns)
  check(rd(OAM_COPY + 1) == 0x40 + 20 and rd(OAM_HEAD + 1) == 0x40 + 6, "phase 2: copy head boss tile 20, original 6")
  check(s.line <= 8, "phase 2: sprites per line " .. s.line)

  -- phase 3 at hp <= 7: look, palette, copies (3, or 2 when the original is on a side platform), double shots
  wr(EHP, 8); wr(EFLASH, 0)
  check(strike() == 7 and rd(PHASE) == 3, "hp 7 -> phase 3, phase=" .. rd(PHASE))
  frames(2)
  check(bar() == "FFFFF.....", "bar half at hp 7, bar=" .. bar())
  check(rd(OAM_HEAD + 1) == 0x40 + 12, "phase 3 look (boss tile 12)")
  check(wait_until(function() return ppu(0x3F15) == 0x16 end, 80), "phase 3 palette")
  check(wait_until(function() return rd(FX) == 0 end, 60), "phase effect ends")
  local lost3 = bot(1200)
  check(lost3 <= 3, "phase 3 standing bot loses <= 3 hearts, lost " .. lost3)
  s = watch(1300)
  check(seq_ok(s) and spots_change(s), "phase 3: teleports to new spots")
  local three = false
  for i, w in ipairs(s.starts) do
    local want = (w.spot == 1 or w.spot == 2) and 2 or 3
    check(w.n == want, "phase 3: " .. want .. " copies for spot " .. w.spot .. ", got " .. w.n)
    if w.n == 3 then three = true end
  end
  check(longest(s, WALK) >= 148 and longest(s, WALK) <= 152, "phase 3 walks ~150 frames, got " .. longest(s, WALK))
  check(s.volley == 2 and s.maxfb == 2, "phase 3 shoots 2 fireballs at once, volley " .. s.volley)
  check(s.line <= 8, "phase 3: sprites per line " .. s.line)
  check(rd(OAM_COPY + 1) == 0x40 + 22 and rd(OAM_HEAD + 1) == 0x40 + 12, "phase 3: copy head boss tile 22, original 12")
  -- worst case for the scanline budget: player standing on a platform, swinging all the time
  local m = 0
  for i = 1, 700 do
    held = (i % 9 < 3) and {b = true} or {}
    safe(); wr(EHP, 7); wr16(PX, i < 350 and 56 or 190); wr(PY, 136); wr(0x30F, 0)
    frames(1)
    m = math.max(m, max_line())
  end
  held = {}
  check(m <= 8, "phase 3, player on a platform swinging: max 8 sprites per scanline, got " .. m)
  peak = math.max(peak, m)

  -- victory: hp 1 + hit -> dead, copies and fireballs gone, no ability, mask bit 5, saved
  wr(EHP, 1); wr(EFLASH, 0)
  check(strike() == 0 and rd(DEAD) == 1, "hp 0 -> boss_dead")
  frames(3)
  check(rd(VICT) > 0 and ppu(0x2000 + 10 * 32 + 12) == 32 and ppu(0x2000 + 10 * 32 + 18) == 36, "'VICTORY' on screen")
  check(rd(OAM_HEAD) == 0xFF and nfb() == 0, "dead: demon and fireballs gone")
  for i = 0, 17 do check(rd(OAM_COPY + 4 * i) == 0xFF, "dead: copy sprite " .. i .. " hidden") end
  check(ppu(0x2000 + 13 * 32 + 12) == 0, "no 'GOT' text: no ability")
  check(wait_until(function() return rd(STATE) == 2 end, 300), "victory returns to the overworld")
  check(rd16(0x308) == 63, "dungeon 6 cleared (bit 5), mask=" .. rd16(0x308))
  check(rd(ABIL) == 0, "no new ability, abilities=" .. rd(ABIL))
  check(rd16(PX) == 528 and rd(PY) == 48 and rd(CUR) == 0, "back at entrance 6")
  check(rd(0x6000) == 0x45 and rd(0x6001) == 0x48 and rd(0x6002) == 1 and rd(0x6003) == 63 and rd(0x6004) == 0
        and rd(0x6005) == 0 and rd(0x6006) == 0xCD, "autosave valid")

  print("mirror test OK (hearts lost by a standing bot per phase: " .. lost1 .. " / " .. lost2 .. " / " .. lost3 ..
        ", peak sprites per scanline: " .. math.max(peak, maxline) .. ")")
  emu.stop(0)
end)

emu.addEventCallback(function() emu.setInput(held, 0, 0) end, emu.eventType.inputPolled)
emu.addEventCallback(function()
  if coroutine.status(co) == "dead" then return end
  local ok, err = coroutine.resume(co)
  if not ok then print("ERROR: " .. tostring(err)); emu.stop(1) end
end, emu.eventType.endFrame)
