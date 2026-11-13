-- Spider queen test (dungeon 8): intro name, bank 7, crawls on the ceiling, telegraph then descent on a thread, low hang window
-- (hit with jump + sword), climb back, webs slow the player (half walk speed, no dash, no heart), the shield stops them, spiderlings
-- (phase 3) cost a heart, contact costs a heart, phases (look, palette, speeds), sprites per scanline, 60 Hz loop, standing-bot
-- hearts, victory without an ability (mask bit 7, valid save). Addresses: docs/TECH.md "Debug-Adressen".
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
local ABIL, DASHT, VICT = 0x322, 0x323, 0x325
local BANK, HIDE, IAIR, SLOW = 0x326, 0x327, 0x328, 0x332
local CRAWL, TELE, DESC, HANG, CLIMB = 1, 2, 3, 4, 5
local FLOOR_Y, CEIL, HANGY = 176, 32, 144
local OAM_THREAD, OAM_FB, OAM_E = 0x200 + 72, 0x200 + 52, 0x200 + 24
local WEB, LING, THREAD = 187, 188, 186

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
local function nthread() local n = 0; for i = 0, 13 do if rd(OAM_THREAD + 4 * i) < 0xEF then n = n + 1 end end return n end
local function safe() wr(HEARTS, 3); wr(INV, 99) end
local function park() safe(); wr16(PX, 48); wr(PY, FLOOR_Y); wr(VY, 0) end
local peak = 0
local function line() local m = max_line(); peak = math.max(peak, m); return m end

-- sword box beside the hanging spider, no damage to the player
local function align() wr16(PX, rd(EX) - 14); wr(PY, 140); wr(VY, 0); safe() end
-- one sword hit at the spider while it hangs low; returns hp afterwards
local function strike()
  local hp = rd(EHP)
  for _ = 1, 10 do
    wait_until(function()
      park(); return rd(FX) == 0 and rd(EFLASH) == 0 and rd(IAIR) == HANG and rd(EY) == HANGY
    end, 900)
    wr(EX, 120)
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
  local s = {runs = {}, line = 0, maxfb = 0, fc0 = rd16(0x300), webst = {}, webdx = 0, webdy = 0, ling = 0, thr_bad = 0, hide = {}, crawlx = {}}
  local last, py, pfb = nil, nil, {}
  for _ = 1, n do
    frames(1)
    park()
    local st, x, y = rd(IAIR), rd(EX), rd(EY)
    if rd(FX) == 0 then
      if st ~= last then s.runs[#s.runs + 1] = {st = st, n = 0, x0 = x, y0 = y, dx = 0, dy = 0, hide = {}}; last = st; py = y end
      local r = s.runs[#s.runs]; r.n = r.n + 1
      r.dx = math.max(r.dx, math.abs(x - r.x0))
      r.dy = math.max(r.dy, math.abs(y - py)); py = y
      r.ye = y; r.xe = x
      r.hide[rd(HIDE)] = true
      local nt = nthread()
      if nt ~= (y - CEIL + 7) // 8 then s.thr_bad = s.thr_bad + 1 end
      if nt > 0 and (rd(OAM_THREAD + 3) ~= x + 8 or rd(OAM_THREAD + 1) ~= THREAD) then s.thr_bad = s.thr_bad + 1 end
      if st == CRAWL then s.crawlx[#s.crawlx + 1] = x end
    end
    for k = 0, 2 do
      local fx, fy = rd(FBX + k), rd(FBY + k)
      if fx ~= 0 then
        local t = rd(OAM_FB + 4 * k + 1)
        if not pfb[k] then s.webst[st] = true end        -- spawn state
        if t == LING then s.ling = s.ling + 1 end
        if pfb[k] and t == WEB then s.webdx = math.max(s.webdx, math.abs(fx - pfb[k][1])); s.webdy = math.max(s.webdy, math.abs(fy - pfb[k][2])) end
        pfb[k] = {fx, fy}
      else pfb[k] = nil end
    end
    s.maxfb = math.max(s.maxfb, nfb())
    s.line = math.max(s.line, line())
  end
  s.frames = rd16(0x300) - s.fc0
  return s
end
local function runs_of(s, st) local t = {}; for _, r in ipairs(s.runs) do if r.st == st then t[#t + 1] = r end end return t end
local function first(s, st) return runs_of(s, st)[1] end
local function maxn(s, st) local m = 0; for _, r in ipairs(runs_of(s, st)) do m = math.max(m, r.n) end return m end
local function minn(s, st, skip) local m = 9999; for i, r in ipairs(runs_of(s, st)) do if i > (skip or 0) then m = math.min(m, r.n) end end return m end
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
local function until_state(st, max)
  return wait_until(function() park(); return rd(IAIR) == st and rd(FX) == 0 end, max)
end
-- wait for a web (tile 187) to exist, return its slot
local function wait_web(max)
  local k
  wait_until(function()
    park()
    for i = 0, 2 do if rd(FBX + i) ~= 0 and rd(OAM_FB + 4 * i + 1) == WEB then k = i end end
    return k ~= nil
  end, max)
  return k
end

co = coroutine.create(function()
  frames(60)
  check(rd(STATE) == 2, "boot reaches overworld")
  wr16(0x308, 127)                          -- dungeons 1..7 cleared: gate 8 open
  wr16(PX, 720); wr(PY, 48)                 -- door of dungeon 8 (col 45, row 3)
  frames(30)
  hold({a = true}, 3)
  frames(20)
  check(rd(STATE) == 3 and rd(CUR) == 8, "dungeon 8 entered, state=" .. rd(STATE))
  check(rd(BANK) == 7 and rd(0x8000) ~= 0, "spider bank 7 mapped, cur_bank=" .. rd(BANK))

  -- intro: "SPIDER QUEEN" (S P I D E R _ Q U E E N = 38 15 13 26 30 35 0 49 27 30 30 28 at row 10, columns 10..21)
  check(rd(INTRO) > 0, "intro running")
  check(rd(EHP) == 16 and rd(PHASE) == 1 and bar() == "FFFFFFFFFF", "spider: 16 hp, phase 1, full bar")
  check(rd(EW) == 24 and rd(EH) == 16 and rd(EY) == CEIL, "spider is 24x16 on the ceiling, w=" .. rd(EW) .. " y=" .. rd(EY))
  local name = {}
  for c = 10, 21 do name[#name + 1] = ppu(0x2000 + 10 * 32 + c) end
  check(table.concat(name, ",") == "38,15,13,26,30,35,0,49,27,30,30,28", "name SPIDER QUEEN on screen: " .. table.concat(name, ","))
  check(ppu(0x2000 + 3 * 32 + 2) == 10 and ppu(0x2000 + 3 * 32 + 29) == 10 and ppu(0x2000 + 3 * 32 + 1) == 10 and ppu(0x2000 + 3 * 32 + 30) == 10,
        "ceiling row 3 drawn")
  check(rd(OAM_E + 1) == 168, "phase 1 look (tile 168)")
  local x0 = rd(EX)
  frames(10)
  check(rd(EX) == x0 and rd(IAIR) == 0, "spider frozen during the intro")
  check(wait_until(function() return rd(INTRO) == 0 end, 100), "intro ends")

  -- phase 1 cycle: crawl ~200 frames, telegraph ~30, descent 2 px/frame to y 144, hang ~55, climb 2 px/frame, crawl again
  local s = watch(900)
  check(s.frames == 900, "game loop runs at 60 Hz: 900 frames -> frame_count +" .. s.frames)
  local order, ok = {}, true
  for i, r in ipairs(s.runs) do order[i] = r.st end
  for i = 2, #order do if order[i] ~= order[i - 1] % 5 + 1 then ok = false end end
  check(ok and #order >= 6, "cycle CRAWL TELE DESC HANG CLIMB CRAWL, states " .. table.concat(order, ","))
  local c1, t1, d1, h1, u1 = first(s, CRAWL), first(s, TELE), first(s, DESC), first(s, HANG), first(s, CLIMB)
  check(c1.y0 == CEIL and c1.dy == 0, "crawls on the ceiling (y 32, no vertical movement)")
  check(maxn(s, CRAWL) >= 196 and maxn(s, CRAWL) <= 204, "crawl ~200 frames, got " .. maxn(s, CRAWL))
  local xmin, xmax, step = 255, 0, 0
  for i, x in ipairs(s.crawlx) do
    xmin = math.min(xmin, x); xmax = math.max(xmax, x)
    if i > 1 and math.abs(x - s.crawlx[i - 1]) <= 4 then step = math.max(step, math.abs(x - s.crawlx[i - 1])) end
  end
  check(xmax - xmin >= 100 and xmin >= 16 and xmax <= 216, "crawls left and right inside the arena, x " .. xmin .. ".." .. xmax)
  check(step == 1, "phase 1 crawl speed 1 px/frame, step " .. step)
  check(t1.n >= 28 and t1.n <= 32 and t1.hide[0] and t1.hide[2] and t1.dy == 0, "telegraph ~30 frames, flickers (hide 0 and 2), stays on the ceiling, n=" .. t1.n)
  check(d1.dx == 0 and d1.dy == 2 and d1.ye >= HANGY - 2, "descent: x fixed, 2 px/frame, down to y 144, dy=" .. d1.dy .. " ye=" .. d1.ye)
  check(h1.n >= 53 and h1.n <= 57 and h1.dx == 0 and h1.dy == 0 and h1.y0 == HANGY, "hangs ~55 frames at y 144, n=" .. h1.n)
  check(u1.dy == 2 and u1.ye <= CEIL + 2, "climbs back 2 px/frame to y 32")
  check(not s.webst[TELE] and not s.webst[DESC] and not s.webst[HANG] and not s.webst[CLIMB] and s.webst[CRAWL], "webs are shot while crawling only")
  check(s.maxfb == 1 and s.ling == 0, "phase 1: one web at a time, no spiderlings, max " .. s.maxfb)
  check(s.webdx <= 1 and s.webdy <= 4, "web is slow (1 px/frame sideways, at most 2 px/frame down), dx " .. s.webdx .. " dy " .. s.webdy)
  check(s.thr_bad == 0, "thread sprites match the body position (tile 186, x + 8), mismatches " .. s.thr_bad)
  check(s.line <= 8, "phase 1: max 8 sprites per scanline, got " .. s.line)
  local lost1 = bot(1200)
  check(lost1 <= 3, "phase 1 standing bot loses <= 3 hearts, lost " .. lost1)

  -- the telegraph slides the spider over the player (x 48): descent lands above him
  check(until_state(DESC, 900), "descent")
  check(math.abs(rd(EX) + 4 - 48) <= 4, "descends over the player, x=" .. rd(EX))

  -- webs: a web on the player slows (1 px/frame, no dash, no heart), then it wears off
  local k = wait_web(900)
  check(k ~= nil, "a web was shot")
  check(rd(OAM_FB + 4 * k + 1) == WEB and rd(OAM_FB + 4 * k + 2) == 1, "web sprite: tile 187, palette 1")
  wr(ABIL, 1); wr(HEARTS, 3); wr(INV, 0); wr16(PX, 48); wr(PY, FLOOR_Y)
  wr(FBX + k, 52); wr(FBY + k, FLOOR_Y + 4)
  frames(1)
  check(rd(FBX + k) == 0, "web consumed")
  check(rd(HEARTS) == 3 and rd(INV) == 0, "web costs no heart, hearts=" .. rd(HEARTS))
  check(rd(SLOW) >= 88 and rd(SLOW) <= 90, "slowed for ~90 frames, slow=" .. rd(SLOW))
  check(rd(0x200 + 2) == 3, "webbed player drawn in the icy palette, attr=" .. rd(0x200 + 2))
  wr(INV, 99)
  local xa = rd16(PX)
  hold({right = true}, 20)
  local xb = rd16(PX)
  check(xb - xa == 20, "webbed: walks 1 px/frame, dx=" .. (xb - xa))
  hold({select = true}, 3)
  check(rd(DASHT) == 0, "webbed: no dash")
  check(wait_until(function() wr(HEARTS, 3); wr(INV, 99); return rd(SLOW) == 0 end, 100), "web wears off")
  xa = rd16(PX); hold({left = true}, 10); xb = rd16(PX)
  check(xa - xb == 20, "after the web: 2 px/frame again, dx=" .. (xa - xb))
  wr(INV, 0); frames(40)
  hold({select = true}, 3)
  check(rd(DASHT) > 0 or rd(0x324) > 0, "dash works again")
  wr(ABIL, 0)

  -- shield stops a web from the front: no heart, no slow
  wr(ABIL, 8)
  k = wait_web(900)
  wr(INV, 0); wr16(PX, 100)
  hold({right = true}, 3)                    -- face right (the shield is on the right)
  held = {down = true}
  wr(HEARTS, 3); wr(INV, 0); wr(SLOW, 0); wr16(PX, 100); wr(PY, FLOOR_Y); wr(VY, 0)
  frames(2)
  check(rd(0x331) == 1, "shield up")
  wr(FBX + k, 112); wr(FBY + k, FLOOR_Y + 4)             -- in the shield box (x + 12, 8 x 16)
  frames(1)
  held = {}
  check(rd(FBX + k) == 0 and rd(HEARTS) == 3 and rd(SLOW) == 0, "shield: the web dies at the shield, no heart, no slow, slow=" .. rd(SLOW))
  wr(ABIL, 0)
  until_state(CRAWL, 900)

  -- contact with the hanging spider costs a heart
  check(until_state(HANG, 900), "spider hangs")
  wr(HEARTS, 3); wr(INV, 0); wr16(PX, rd(EX) + 6); wr(PY, 150); wr(VY, 0)
  frames(2)
  check(rd(HEARTS) == 2 and rd(INV) > 80, "contact costs a heart, hearts=" .. rd(HEARTS))
  frames(2)
  check(rd(HEARTS) == 2, "no second loss while invulnerable")
  park()

  -- real play: jump from the floor and swing the sword at the hanging spider (it hangs 40..60 frames)
  check(until_state(CRAWL, 900), "back on the ceiling")
  check(wait_until(function() park(); return rd(IAIR) == HANG end, 900), "spider hangs again")
  wr(EFLASH, 0)
  local hp = rd(EHP)
  wr(EX, 120)
  hold({right = true}, 2)
  local hit = false
  for i = 1, 70 do
    wr(HEARTS, 3); wr(INV, 99)
    if rd(PY) == FLOOR_Y or i == 1 then wr16(PX, 100) end
    held = {a = i < 30, b = (i % 6) < 2}
    frames(1)
    if rd(EHP) < hp then hit = true; break end
  end
  held = {}
  check(hit and rd(EHP) == hp - 1, "jump + sword from the floor hits the hanging spider, hp " .. hp .. " -> " .. rd(EHP))
  park()

  -- sword hit on the body: exactly 1 hp more, bar ceil(15*20/16) = 19 half steps, <= 8 sprites per line with the sword out
  wr(EHP, 16); wr(EFLASH, 0)
  local hp = strike()
  check(hp == 15, "hit = exactly 1 hp, hp=" .. hp)
  check(bar() == "FFFFFFFFFH", "bar after one hit, bar=" .. bar())
  check(peak <= 8, "sword + spider + player: max 8 sprites per scanline, got " .. peak)

  -- phase 2 at hp <= 11: look, palette, faster descent, shorter hang and crawl, two webs
  wr(EHP, 12); wr(EFLASH, 0)
  check(strike() == 11 and rd(PHASE) == 2, "hp 11 -> phase 2, phase=" .. rd(PHASE))
  frames(2)
  check(bar() == "FFFFFFF...", "bar 14 half steps at hp 11, bar=" .. bar())
  check(wait_until(function() return ppu(0x3F15) == 0x2A end, 80), "phase 2 palette")
  check(wait_until(function() return rd(FX) == 0 end, 60), "phase effect ends")
  check(rd(OAM_E + 1) == 174, "phase 2 look (tile 174)")
  s = watch(1300)
  local d2, h2 = runs_of(s, DESC)[2], runs_of(s, HANG)[2]
  check(d2.dy == 3 and d2.dx == 0, "phase 2 descends 3 px/frame, dy=" .. d2.dy)
  check(h2.n >= 43 and h2.n <= 47, "phase 2 hangs ~45 frames, got " .. h2.n)
  check(maxn(s, CRAWL) >= 146 and maxn(s, CRAWL) <= 154, "phase 2 crawl ~150 frames, got " .. maxn(s, CRAWL))
  check(s.maxfb >= 2 and s.ling == 0, "phase 2: two webs per volley (volleys overlap), no spiderlings, max " .. s.maxfb)
  check(s.thr_bad == 0, "phase 2 thread matches")
  check(s.line <= 8, "phase 2: max 8 sprites per scanline, got " .. s.line)
  local lost2 = bot(1200)
  check(lost2 <= 3, "phase 2 standing bot loses <= 3 hearts, lost " .. lost2)

  -- phase 3 at hp <= 8: look, palette, faster crawl + descent, three webs and spiderlings (a heart each)
  wr(EHP, 9); wr(EFLASH, 0)
  check(strike() == 8 and rd(PHASE) == 3, "hp 8 -> phase 3, phase=" .. rd(PHASE))
  frames(2)
  check(bar() == "FFFFF.....", "bar half at hp 8, bar=" .. bar())
  check(wait_until(function() return ppu(0x3F15) == 0x16 end, 80), "phase 3 palette")
  check(wait_until(function() return rd(FX) == 0 end, 60), "phase effect ends")
  check(rd(OAM_E + 1) == 180, "phase 3 look (tile 180)")
  s = watch(1300)
  local d3, h3 = runs_of(s, DESC)[2], runs_of(s, HANG)[2]
  check(d3.dy == 4 and d3.dx == 0, "phase 3 descends 4 px/frame, dy=" .. d3.dy)
  check(h3.n >= 38 and h3.n <= 42, "phase 3 hangs ~40 frames, got " .. h3.n)
  check(maxn(s, CRAWL) >= 106 and maxn(s, CRAWL) <= 114, "phase 3 crawl ~110 frames, got " .. maxn(s, CRAWL))
  local step3 = 0
  for i = 2, #s.crawlx do if math.abs(s.crawlx[i] - s.crawlx[i - 1]) <= 4 then step3 = math.max(step3, math.abs(s.crawlx[i] - s.crawlx[i - 1])) end end
  check(step3 == 2, "phase 3 crawls 2 px/frame, step " .. step3)
  check(s.maxfb == 3 and s.ling > 0, "phase 3: three webs and spiderlings, max " .. s.maxfb .. " ling " .. s.ling)
  check(s.thr_bad == 0, "phase 3 thread matches")
  check(s.line <= 8, "phase 3: max 8 sprites per scanline, got " .. s.line)
  local lost3 = bot(1200)
  check(lost3 <= 3, "phase 3 standing bot loses <= 3 hearts, lost " .. lost3)
  -- a spiderling falls straight down and costs a heart
  local kl
  wait_until(function()
    park()
    for i = 0, 2 do if rd(FBX + i) ~= 0 and rd(OAM_FB + 4 * i + 1) == LING then kl = i end end
    return kl ~= nil
  end, 900)
  check(kl ~= nil, "spiderlings drop in phase 3")
  local lx, ly = rd(FBX + kl), rd(FBY + kl)
  frames(8)
  check(rd(FBX + kl) == lx and rd(FBY + kl) > ly + 8, "spiderling falls straight down, y " .. ly .. " -> " .. rd(FBY + kl))
  wr(HEARTS, 3); wr(INV, 0); wr(SLOW, 0); wr16(PX, lx - 4); wr(PY, FLOOR_Y); wr(VY, 0)
  wr(FBX + kl, lx); wr(FBY + kl, FLOOR_Y + 4)
  frames(1)
  check(rd(HEARTS) == 2 and rd(SLOW) == 0, "spiderling costs a heart (and does not web), hearts=" .. rd(HEARTS))
  park()

  -- victory: hp 1 + hit -> dead, thread and body gone, no ability text, overworld, mask bit 7, nothing granted, valid save
  wr(EHP, 1); wr(EFLASH, 0)
  check(strike() == 0 and rd(DEAD) == 1, "hp 0 -> boss_dead")
  frames(3)
  check(rd(VICT) > 0 and ppu(0x2000 + 10 * 32 + 12) == 32 and ppu(0x2000 + 10 * 32 + 18) == 36, "'VICTORY' on screen")
  for i = 0, 13 do check(rd(OAM_THREAD + 4 * i) == 0xFF, "dead: thread sprite " .. i .. " hidden") end
  check(rd(OAM_E) == 0xFF and nfb() == 0, "dead: body and webs gone")
  local got = 0
  for c = 8, 24 do got = got + ppu(0x2000 + 13 * 32 + c) end
  check(got == 0, "no 'GOT' text (no ability)")
  check(wait_until(function() return rd(STATE) == 2 end, 300), "victory returns to the overworld")
  check(rd16(0x308) == 255, "dungeon 8 cleared (bit 7), mask=" .. rd16(0x308))
  check(rd(ABIL) == 0, "no ability granted, abilities=" .. rd(ABIL))
  check(rd16(PX) == 720 and rd(PY) == 48 and rd(CUR) == 0, "back at entrance 8")
  check(rd(0x6000) == 0x45 and rd(0x6001) == 0x48 and rd(0x6002) == 1 and rd(0x6003) == 255 and rd(0x6004) == 0
        and rd(0x6005) == 0 and rd(0x6006) == 0x8D, "autosave valid")

  print("spider test OK (hearts lost by a standing bot per phase: " .. lost1 .. " / " .. lost2 .. " / " .. lost3 ..
        ", peak sprites per scanline: " .. peak .. ")")
  emu.stop(0)
end)

emu.addEventCallback(function() emu.setInput(held, 0, 0) end, emu.eventType.inputPolled)
emu.addEventCallback(function()
  if coroutine.status(co) == "dead" then return end
  local ok, err = coroutine.resume(co)
  if not ok then print("ERROR: " .. tostring(err)); emu.stop(1) end
end, emu.eventType.endFrame)
