-- Lava snake test (dungeon 4): intro name, bank 3, rise/up/sink cycle, submerged = untouchable + not drawn, telegraph
-- before emerging, alternating pools, head hit, body contact (no hit), fireballs, phases 2/3, sprites per scanline,
-- victory without ability. Addresses: docs/TECH.md "Debug-Adressen".
local M = emu.memType.nesMemory
local held = {}
local function rd(a) return emu.read(a, M) end
local function rd16(a) return rd(a) + 256 * rd(a + 1) end
local function wr(a, v) emu.write(a, v, M) end
local function wr16(a, v) wr(a, v % 256); wr(a + 1, v // 256) end
local function ppu(a) return emu.read(a, emu.memType.nesPpuMemory) end
local STATE, PX, PY, CUR = 0x302, 0x303, 0x305, 0x30A
local HEARTS, INV, VY = 0x30B, 0x30C, 0x30F
local EX, EY, EW, EHP, EFLASH = 0x310, 0x311, 0x312, 0x314, 0x315
local PHASE, DEAD, INTRO, FBX, FX = 0x318, 0x319, 0x31A, 0x31B, 0x321
local ABIL, VICT = 0x322, 0x325
local BANK, HIDE, IAIR = 0x326, 0x327, 0x328   -- cur_bank; boss_hide; snake state
local INIT, HID, TELE, RISE, UP, SINK = 0, 1, 2, 3, 4, 5
local FLOOR_Y = 176
local OAM_HEAD, OAM_BODY = 0x200 + 24, 0x200 + 72

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
local function body_sprites()
  local n = 0
  for j = 0, 7 do if rd(OAM_BODY + 8 * j) < 0xEF then n = n + 1 end end
  return n
end
local maxline, peak = 0, 0
local function safe() wr(HEARTS, 3); wr(INV, 99) end
-- player (facing right) at the head's left side, sword box over it; no damage
local function align()
  wr16(PX, math.max(16, rd(EX) - 14)); wr(PY, rd(EY)); wr(VY, 0); safe()
end
-- one sword swing at the head (it must be touchable); returns hp afterwards
local function strike()
  local hp = rd(EHP)
  for _ = 1, 8 do
    wait_until(function() return rd(HIDE) & 1 == 0 and rd(FX) == 0 and rd(EFLASH) == 0 and rd(EY) < FLOOR_Y end, 600)
    held = {b = true}
    for _ = 1, 3 do align(); frames(1); maxline = math.max(maxline, max_line()) end
    held = {}
    for _ = 1, 20 do align(); frames(1); maxline = math.max(maxline, max_line()) end
    if rd(EHP) ~= hp then break end
  end
  wr16(PX, 100); wr(PY, FLOOR_Y)
  return rd(EHP)
end
-- Watch n frames with the player parked on the floor at x = px and safe. Returns state runs and statistics.
local function watch(n, px)
  local s = {runs = {}, mxr = 0, mxs = 0, minx = 255, maxx = 0, miny = 255, line = 0, spawns = 0, maxspawn = 0,
             maxfb = 0, volley = 0, hides = {}, maxbody = 0, tele_x = {}}
  local last, ex, ey, visit, prev = nil, rd(EX), rd(EY), 0, {}
  for i = 0, 2 do prev[i] = rd(FBX + i) end
  for _ = 1, n do
    frames(1)
    safe(); wr16(PX, px); wr(PY, FLOOR_Y)
    local x, y, st = rd(EX), rd(EY), rd(IAIR)
    if rd(FX) == 0 then
      if st == RISE and last == RISE then s.mxr = math.max(s.mxr, ey - y) end
      if st == SINK and last == SINK then s.mxs = math.max(s.mxs, y - ey) end
    end
    ex, ey = x, y
    if st ~= last then
      s.runs[#s.runs + 1] = {st = st, n = 0}
      if st == UP then visit = 0 end
      if st == TELE then s.tele_x[#s.tele_x + 1] = x end
      last = st
    end
    local r = s.runs[#s.runs]; r.n = r.n + 1
    if st == TELE then s.hides[rd(HIDE)] = true end
    if st == UP then s.minx = math.min(s.minx, x); s.maxx = math.max(s.maxx, x); s.miny = math.min(s.miny, y) end
    local new = 0
    for i = 0, 2 do
      local v = rd(FBX + i)
      if v ~= 0 and prev[i] == 0 then new = new + 1; visit = visit + 1 end
      prev[i] = v
    end
    s.spawns = s.spawns + new
    s.maxspawn = math.max(s.maxspawn, visit)
    s.volley = math.max(s.volley, new)
    s.maxfb = math.max(s.maxfb, nfb())
    s.maxbody = math.max(s.maxbody, body_sprites())
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
local function order_ok(s)       -- ... HIDE, TELE, RISE, UP, SINK, HIDE ... somewhere in the run list
  local seq = {HID, TELE, RISE, UP, SINK, HID}
  for i = 1, #s.runs - 5 do
    local ok = true
    for k = 1, 6 do if s.runs[i + k - 1].st ~= seq[k] then ok = false end end
    if ok then return true end
  end
  return false
end

co = coroutine.create(function()
  frames(10); held = {start = true}; frames(3); held = {}; frames(60)   -- boot menu: Start = NORMAL
  check(rd(STATE) == 2, "boot reaches overworld")
  wr16(0x308, 7)                          -- dungeons 1-3 cleared: gate 4 open
  wr16(PX, 336); wr(PY, 48)               -- door of dungeon 4
  frames(30)
  hold({a = true}, 3)
  frames(20)
  check(rd(STATE) == 3 and rd(CUR) == 4, "dungeon 4 entered, state=" .. rd(STATE))
  check(rd(BANK) == 3 and rd(0x8000) ~= 0, "snake bank 3 mapped, cur_bank=" .. rd(BANK))
  -- lava pools (tile 3) in the floor row at both walls
  check(ppu(0x2000 + 24 * 32 + 2) == 3 and ppu(0x2000 + 24 * 32 + 29) == 3 and ppu(0x2000 + 24 * 32 + 16) == 11, "lava pools in the floor")

  -- intro: "LAVA SNAKE" (L A V A _ S N A K E = tiles 44 37 32 37 0 38 28 37 46 30 at row 10, columns 11..20)
  check(rd(INTRO) > 0, "intro running")
  check(rd(EHP) == 14 and rd(PHASE) == 1 and bar() == "FFFFFFFFFF", "snake: 14 hp, phase 1, full bar")
  local name = {}
  for c = 11, 20 do name[#name + 1] = ppu(0x2000 + 10 * 32 + c) end
  check(table.concat(name, ",") == "44,37,32,37,0,38,28,37,46,30", "name LAVA SNAKE on screen: " .. table.concat(name, ","))
  local x0, y0 = rd(EX), rd(EY)
  frames(10)
  check(rd(EX) == x0 and rd(EY) == y0 and rd(IAIR) == INIT, "snake frozen during the intro")
  check(wait_until(function() return rd(INTRO) == 0 end, 100), "intro ends")
  hold({right = true}, 2)                 -- face right

  -- phase 1: full cycle, ~30 frame telegraph with flicker (still untouchable), 1 px/frame rise, pools alternate
  local s = watch(900, 100)
  check(order_ok(s), "cycle HIDE, TELE, RISE, UP, SINK, HIDE")
  check(longest(s, TELE) >= 28 and longest(s, TELE) <= 32, "telegraph ~30 frames, got " .. longest(s, TELE))
  check(s.hides[1] and s.hides[3], "telegraph flickers (boss_hide 1 and 3)")
  check(s.mxr == 1 and s.mxs == 1, "phase 1 rises and sinks 1 px/frame, got " .. s.mxr .. "/" .. s.mxs)
  check(longest(s, HID) >= 98 and longest(s, HID) <= 102, "phase 1 submerged ~100 frames, got " .. longest(s, HID))
  check(s.miny >= 124 and s.miny < 130 and s.maxx - s.minx >= 30, "up: hovers at y 124.., leans/sways, x " .. s.minx .. ".." .. s.maxx)
  check(#s.tele_x >= 2 and math.abs(s.tele_x[1] - s.tele_x[2]) > 150, "re-emerges at the other pool: " .. table.concat(s.tele_x, ","))
  check(s.maxbody >= 4, "body segments drawn while up, got " .. s.maxbody)
  check(s.maxspawn == 1 and s.maxfb >= 1, "phase 1 spits once per visit, got " .. s.maxspawn)
  check(s.line <= 8, "max 8 sprites per scanline, got " .. s.line)

  -- submerged: not drawn, untouchable (no sword hit, no contact), body gone
  check(wait_until(function() return rd(IAIR) == HID end, 700), "submerged again")
  local hp, flash = rd(EHP), rd(HEARTS)
  check(rd(HIDE) == 3 and rd(OAM_HEAD) == 0xFF and body_sprites() == 0, "submerged: head and body not drawn, hide=" .. rd(HIDE))
  held = {b = true}
  for _ = 1, 6 do wr16(PX, rd(EX)); wr(PY, rd(EY)); wr(HEARTS, 3); wr(INV, 0); frames(1) end
  held = {}
  check(rd(EHP) == hp and rd(HEARTS) == 3, "submerged: sword and contact do nothing, hp=" .. rd(EHP) .. " hearts=" .. rd(HEARTS))
  -- telegraph: untouchable too, but drawn at times
  check(wait_until(function() return rd(IAIR) == TELE end, 150), "telegraph starts")
  local drawn = false
  for _ = 1, 25 do
    wr16(PX, rd(EX)); wr(PY, rd(EY)); wr(HEARTS, 3); wr(INV, 0); frames(1)
    if rd(OAM_HEAD) < 0xEF then drawn = true end
    check(rd(HEARTS) == 3 and rd(EHP) == hp, "telegraph: untouchable and harmless")
  end
  check(drawn, "telegraph flicker draws the head at times")

  -- up: contact with the head costs exactly one heart (then the invulnerability protects), body contact too
  local function up() return wait_until(function() safe(); wr16(PX, 100); wr(PY, FLOOR_Y); return rd(IAIR) == UP and rd(EFLASH) == 0 end, 400) end
  check(up(), "up")
  frames(10)
  wr(INV, 0); wr(HEARTS, 3); wr16(PX, rd(EX)); wr(PY, rd(EY)); frames(2)
  check(rd(HEARTS) == 2 and rd(INV) > 80, "head contact costs a heart, hearts=" .. rd(HEARTS))
  wr16(PX, rd(EX)); frames(5)
  check(rd(HEARTS) == 2, "no second loss while invulnerable")
  wait_until(function() return rd(INV) == 0 or rd(IAIR) ~= UP end, 130)
  check(up(), "up again")
  frames(10)
  wr(INV, 0); wr(HEARTS, 3)
  local bx, by = rd(OAM_BODY + 16 + 3), rd(OAM_BODY + 16) + 1       -- body segment 2
  wr16(PX, bx + 3); wr(PY, by + 2); frames(1)
  check(rd(HEARTS) == 2, "body contact costs a heart, hearts=" .. rd(HEARTS))
  -- the body cannot be hit: sword over a body segment does nothing
  safe(); wr16(PX, 100); wr(PY, FLOOR_Y)
  wait_until(function() return rd(INV) == 99 end, 5)
  hp = rd(EHP)
  held = {b = true}
  for _ = 1, 3 do
    bx, by = rd(OAM_BODY + 16 + 3), rd(OAM_BODY + 16) + 1
    wr16(PX, math.max(16, bx - 14)); wr(PY, by - 6); wr(VY, 0); safe(); frames(1)
  end
  held = {}
  frames(15)
  check(rd(EHP) == hp, "body is not hittable, hp=" .. rd(EHP))

  -- head hit: exactly 1 hp, bar 19 half steps, sprites per line with the swing
  wr(EFLASH, 0)
  hp = strike()
  check(hp == 13 and bar() == "FFFFFFFFFH", "hit = exactly 1 hp, bar=" .. bar() .. " hp=" .. hp)
  check(maxline <= 8, "sword swing + overlap: max 8 sprites per scanline, got " .. maxline)

  -- phase 2 at hp <= 9: look, palette, faster, two spits per visit
  wr(EHP, 10); wr(EFLASH, 0)
  check(strike() == 9 and rd(PHASE) == 2, "hp 9 -> phase 2, phase=" .. rd(PHASE))
  frames(2)
  check(bar() == "FFFFFFH...", "bar 13 steps at hp 9, bar=" .. bar())
  check(rd(OAM_HEAD + 1) == 74, "phase 2 look (head tile 74)")
  check(wait_until(function() return ppu(0x3F15) == 0x16 end, 80), "phase 2 palette")
  check(wait_until(function() return rd(FX) == 0 end, 60), "phase effect ends")
  s = watch(700, 100)
  check(rd(OAM_BODY + 1) == 78, "phase 2 body tile 78")
  check(s.mxr == 2 and s.mxs == 2, "phase 2 rises and sinks 2 px/frame, got " .. s.mxr .. "/" .. s.mxs)
  check(s.maxspawn >= 2, "phase 2 spits twice per visit, got " .. s.maxspawn)
  check(longest(s, HID) >= 68 and longest(s, HID) <= 72, "phase 2 submerged ~70 frames, got " .. longest(s, HID))
  check(s.line <= 8, "phase 2: sprites per line " .. s.line)

  -- phase 3 at hp <= 7: look, spread of 3, shorter submerged time
  wr(EHP, 8); wr(EFLASH, 0)
  check(strike() == 7 and rd(PHASE) == 3, "hp 7 -> phase 3, phase=" .. rd(PHASE))
  frames(2)
  check(bar() == "FFFFF.....", "bar half at hp 7, bar=" .. bar())
  check(rd(OAM_HEAD + 1) == 80, "phase 3 look (head tile 80)")
  check(wait_until(function() return ppu(0x3F15) == 0x28 end, 80), "phase 3 palette")
  check(wait_until(function() return rd(FX) == 0 end, 60), "phase effect ends")
  s = watch(800, 100)
  check(rd(OAM_BODY + 1) == 84, "phase 3 body tile 84")
  check(s.volley == 3 and s.maxfb == 3, "phase 3 spits a spread of 3, volley " .. s.volley)
  check(longest(s, HID) >= 38 and longest(s, HID) <= 42, "phase 3 submerged ~40 frames, got " .. longest(s, HID))
  check(s.line <= 8, "phase 3: sprites per line " .. s.line)

  -- victory: hp 1 + hit -> dead, body gone, overworld, bit 3 set, no ability, saved
  wr(EHP, 1); wr(EFLASH, 0)
  check(strike() == 0 and rd(DEAD) == 1, "hp 0 -> boss_dead")
  frames(3)
  check(rd(VICT) > 0 and ppu(0x2000 + 10 * 32 + 12) == 32 and ppu(0x2000 + 10 * 32 + 18) == 36, "'VICTORY' on screen")
  check(body_sprites() == 0 and rd(OAM_HEAD) == 0xFF, "dead: head and body gone")
  local got = 0
  for c = 8, 22 do got = got + ppu(0x2000 + 13 * 32 + c) end
  check(got == 0, "no ability text")
  check(wait_until(function() return rd(STATE) == 2 end, 300), "victory returns to the overworld")
  check(rd16(0x308) == 15, "dungeon 4 cleared (bit 3), mask=" .. rd16(0x308))
  check(rd(ABIL) == 0, "no new ability, abilities=" .. rd(ABIL))
  check(rd16(PX) == 336 and rd(PY) == 48 and rd(CUR) == 0, "back at entrance 4")
  check(rd(0x6000) == 0x45 and rd(0x6001) == 0x48 and rd(0x6002) == 1 and rd(0x6003) == 15 and rd(0x6004) == 0
        and rd(0x6005) == 0 and rd(0x6006) == 0x9D, "autosave valid")

  print("snake test OK (peak sprites per scanline: " .. math.max(peak, maxline) .. ")")
  emu.stop(0)
end)

emu.addEventCallback(function() emu.setInput(held, 0, 0) end, emu.eventType.inputPolled)
emu.addEventCallback(function()
  if coroutine.status(co) == "dead" then return end
  local ok, err = coroutine.resume(co)
  if not ok then print("ERROR: " .. tostring(err)); emu.stop(1) end
end, emu.eventType.endFrame)
