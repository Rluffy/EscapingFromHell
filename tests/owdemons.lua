-- Overworld demons (v1.1 package 2, docs/TECH.md "Overworld-Figuren (v1.1)"): every demon sits on the roof of its temple (4 sprites in OAM
-- 4..15), off-screen ones are culled, a cleared dungeon shows a skull, the sprite palettes follow the demons in view, <= 8 sprites per
-- scanline everywhere, the demon sheet is back in R3..R5 after a dungeon, all 10 doors still work. Temple grid: door col 6n-3, row 5 / 3.
local M, P, C = emu.memType.nesMemory, emu.memType.nesPpuMemory, emu.memType.nesChrRom
local held = {}
local function rd(a) return emu.read(a, M) end
local function rd16(a) return rd(a) + 256 * rd(a + 1) end
local function wr(a, v) emu.write(a, v, M) end
local function wr16(a, v) wr(a, v % 256); wr(a + 1, v // 256) end
local STATE, PX, PY, CAM, MASK, CUR, BCHR = 0x302, 0x303, 0x305, 0x306, 0x308, 0x30A, 0x337
local PAL = {{0x0A,0x2A,0x38}, {0x22,0x30,0x0F}, {0x08,0x37,0x2A}, {0x07,0x27,0x30}, {0x04,0x24,0x30},    -- phase-1 palettes of the demons
             {0x01,0x21,0x30}, {0x09,0x1A,0x26}, {0x03,0x13,0x2A}, {0x06,0x26,0x38}, {0x06,0x16,0x28}}
local SKULL = 0x40 + 40

local co
local function frames(n) for _ = 1, n do coroutine.yield() end end
local function hold(keys, n) held = keys; frames(n); held = {} end
local function press(keys) hold(keys, 3); frames(5) end
local function check(cond, msg)
  if not cond then print("FAIL: " .. msg); emu.stop(1); coroutine.yield() end
end
local function door(n) return (6 * n - 3) * 16, (n % 2 == 1) and 80 or 48 end
local function goto_xy(x, y, wait) wr16(PX, x); wr(PY, y); frames(wait or 12) end
local function oam(i) return rd(0x200 + 4 * i), rd(0x201 + 4 * i), rd(0x202 + 4 * i), rd(0x203 + 4 * i) end   -- y, tile, attr, x
local function visible()                      -- demon sprites (OAM 4..15) that are on screen
  local t = {}
  for i = 4, 15 do local y, tile, attr, x = oam(i); if y < 0xEF then t[#t + 1] = {i = i, y = y, tile = tile, attr = attr, x = x} end end
  return t
end
local function demon_sprites(n)               -- the 4 sprites of demon n, or nil
  local base, t = 0x40 + 4 * (n - 1), {}
  for _, s in ipairs(visible()) do if s.tile >= base and s.tile < base + 4 then t[s.tile - base] = s end end
  return t[0] and t[1] and t[2] and t[3] and t
end
local function lines_max()                    -- most sprites on one scanline over all 64 OAM entries (8x8 sprites)
  local cnt, worst = {}, 0
  for i = 0, 63 do
    local y = rd(0x200 + 4 * i)
    if y < 0xEF then for l = y + 1, y + 8 do cnt[l] = (cnt[l] or 0) + 1; worst = math.max(worst, cnt[l]) end end
  end
  return worst
end
local function chr_same(a, kb)                -- PPU window a (1 KB) = CHR-ROM bank kb, first 64 bytes
  for i = 0, 63 do if emu.read(a + i, P) ~= emu.read(kb * 1024 + i, C) then return false end end
  return true
end

co = coroutine.create(function()
  frames(30); held = {start = true}; frames(3); held = {}; frames(20); held = {start = true}; frames(3); held = {}; frames(60)   -- NEW GAME, skip the intro
  check(rd(STATE) == 2, "overworld reached, state=" .. rd(STATE))
  check(rd(BCHR) == 48 and chr_same(0x1400, 48) and chr_same(0x1800, 49) and chr_same(0x1C00, 50), "R3..R5 = demon sheet (CHR banks 48..50)")

  -- (a) every demon on its roof, in its own colours, hidden ones are culled
  for n = 1, 10 do
    local x, y = door(n)
    goto_xy(x, y, 30)
    local d = demon_sprites(n)
    check(d, "demon " .. n .. ": its 4 tiles are in OAM")
    local cam, sx = rd16(CAM), x - rd16(CAM)
    local ty = (n % 2 == 1) and 51 or 19
    check(d[0].x == sx and d[2].x == sx and d[1].x == sx + 8 and d[3].x == sx + 8, "demon " .. n .. ": x on the temple, sx=" .. sx .. " got " .. d[0].x)
    check(d[0].y >= ty and d[0].y <= ty + 1 and d[2].y == d[0].y + 8, "demon " .. n .. ": y on the roof, y=" .. d[0].y)
    local slot = (n - 1) % 3 + 1
    check(d[0].attr & 3 == slot, "demon " .. n .. ": sprite palette " .. slot .. ", attr=" .. d[0].attr)
    for i = 1, 3 do check(emu.read(0x3F11 + 4 * slot + i - 1 + 0, P) == PAL[n][i], string.format("demon %d: palette colour %d is %02X, want %02X", n, i, emu.read(0x3F11 + 4 * slot + i - 1, P), PAL[n][i])) end
    local vis = #visible()
    check(vis % 4 == 0 and vis >= 8 and vis <= 12, "demon " .. n .. ": 2..3 figures on screen, sprites=" .. vis)
    for m = 1, 10 do
      local px = (6 * m - 3) * 16
      local on = px - cam > -16 and px - cam < 256
      check((demon_sprites(m) ~= nil) == on, string.format("demon %d at world x %d with cam %d: on screen = %s", m, px, cam, tostring(on)))
    end
  end
  check(not demon_sprites(1), "far right: demon 1 is culled")
  goto_xy(48, 80, 30)
  check(not demon_sprites(10), "far left: demon 10 is culled")

  -- (b) half-visible figure at the left edge: the column that would wrap to the right edge is hidden
  goto_xy(172, 112, 30)                       -- cam 52, demon 1 at screen x -4
  check(rd16(CAM) == 52, "cam=" .. rd16(CAM))
  local y0, _, _, _ = oam(4)
  local y1, _, _, x1 = oam(5)
  check(y0 == 0xFF and y1 < 0xEF and x1 == 4, "left edge: left column hidden, right column at x=4 (" .. y0 .. "," .. y1 .. "," .. x1 .. ")")

  -- (c) idle animation: the figure bobs between two y values
  local seen = {}
  goto_xy(144, 48, 30)
  for _ = 1, 100 do frames(1); seen[rd(0x200 + 16)] = true end
  local cnt = 0; for _ in pairs(seen) do cnt = cnt + 1 end
  check(cnt == 2, "demon bobs between 2 positions, saw " .. cnt)

  -- (d) cleared dungeons show a skull, the others stay
  wr16(MASK, 1)
  goto_xy(144, 48, 30)                        -- dungeon 1 cleared: demon 1 (screen x 48 - 24) off, demon 2 / 3 alive
  goto_xy(96, 80, 30)                         -- cam 0
  local s = nil
  for _, v in ipairs(visible()) do if v.tile == SKULL then s = v end end
  check(s and s.attr & 3 == 0, "dungeon 1 cleared: skull marker with palette 0 at the temple")
  check(not demon_sprites(1) and demon_sprites(2), "demon 1 gone, demon 2 still there")
  wr16(MASK, 1023)
  goto_xy(528, 80, 30)
  local skulls, alive = 0, 0
  for _, v in ipairs(visible()) do if v.tile == SKULL then skulls = skulls + 1 end end
  for m = 1, 10 do if demon_sprites(m) then alive = alive + 1 end end
  check(skulls >= 2 and skulls == #visible() // 4 and alive == 0, "all cleared: only skulls, skull sprites=" .. skulls .. " alive=" .. alive)
  wr16(MASK, 0)

  -- (e) 8 sprites per scanline: sweep the whole map over the demon rows, hero on top of the figures and beside them
  local worst = 0
  for x = 12, 996, 12 do
    for _, y in ipairs({16, 24, 40, 56, 72}) do
      wr16(PX, x); wr(PY, y); frames(3)
      local l = lines_max()
      worst = math.max(worst, l)
      check(l <= 8, string.format("scanline sprites %d at x=%d y=%d", l, x, y))
    end
  end
  check(worst >= 4, "the sweep sees figure + hero lines, worst=" .. worst)
  -- and walking (camera streaming columns while the sprites move)
  wr16(PX, 12); wr(PY, 144); frames(10)
  for i = 1, 600 do held = {right = true}; frames(1); check(lines_max() <= 8, "walking: > 8 sprites on a line at frame " .. i) end
  held = {}
  for i = 1, 600 do held = {left = true, up = i % 2 == 0}; frames(1); check(lines_max() <= 8, "walking back: > 8 sprites on a line at frame " .. i) end
  held = {}

  -- (f) every door still enters; the demon sheet is back in R3..R5 afterwards
  wr16(MASK, 1023)
  for n = 1, 10 do
    local x, y = door(n)
    goto_xy(x, y, 30)
    press({a = true}); frames(20)
    check(rd(STATE) == 3 and rd(CUR) == n, "door " .. n .. " enters dungeon " .. n)
    press({start = true}); press({select = true}); frames(30)
    check(rd(STATE) == 2 and rd16(PX) == x and rd(PY) == y, "back at door " .. n)
    check(rd(BCHR) == 48 and chr_same(0x1400, 48), "after dungeon " .. n .. ": demon sheet in R3")
    check(#visible() >= 8, "after dungeon " .. n .. ": figures drawn")
  end
  print("owdemons test OK, worst scanline " .. worst)
  emu.stop(0)
end)

emu.addEventCallback(function() emu.setInput(held, 0, 0) end, emu.eventType.inputPolled)
emu.addEventCallback(function()
  if coroutine.status(co) == "dead" then return end
  local ok, err = coroutine.resume(co)
  if not ok then print("ERROR: " .. tostring(err)); emu.stop(1) end
end, emu.eventType.endFrame)
