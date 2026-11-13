-- Sword wave ability test (bit 4, dungeon 9 reward): with the ability and all 3 hearts a sword swing (B) also throws a wave
-- (player projectile pf_*, tile 222, 3 px/frame, 1 damage once, gone at the wall). Without the ability, with fewer hearts, or
-- while another projectile flies: sword only. Up + B stays the fireball (tile 29). Uses the Imp (dungeon 1, pinned).
-- Addresses: docs/TECH.md "Debug-Adressen".
local M = emu.memType.nesMemory
local held = {}
local function rd(a) return emu.read(a, M) end
local function rd16(a) return rd(a) + 256 * rd(a + 1) end
local function wr(a, v) emu.write(a, v, M) end
local function wr16(a, v) wr(a, v % 256); wr(a + 1, v // 256) end
local STATE, PX, PY, CUR, MASK = 0x302, 0x303, 0x305, 0x30A, 0x308
local HEARTS, INV, SWORD = 0x30B, 0x30C, 0x30E
local EX, EY, EHP, EFLASH = 0x310, 0x311, 0x314, 0x315
local INTRO, ABIL = 0x31A, 0x322
local PFX, PFY, PFCD = 0x329, 0x32A, 0x32B
local FLOOR_Y = 176
local OAM_PF = 0x200 + 136
local WAVE, FIRE = 222, 29

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
local pin = 0          -- imp parked: 0 = at the ceiling (harmless), else at the floor at x = pin
local function place(px, hearts)               -- player on the floor, safe; the imp stays where `pin` says
  wr16(PX, px); wr(PY, FLOOR_Y); wr(HEARTS, hearts or 3); wr(INV, 99)
  if pin == 0 then wr(EY, 0) else wr(EX, pin); wr(EY, FLOOR_Y) end
end
local function swing(n) held = {b = true}; for _ = 1, n or 3 do frames(1) end; held = {} end
local function face(dir, px)                    -- 0 right, 1 left
  held = dir == 1 and {left = true} or {right = true}
  for _ = 1, 3 do place(px); frames(1) end
  held = {}; place(px); frames(2)
end

co = coroutine.create(function()
  frames(10); held = {start = true}; frames(3); held = {}; frames(60)   -- boot menu: Start = NORMAL
  check(rd(STATE) == 2, "boot reaches overworld")
  wr16(MASK, 0); wr16(PX, 48); wr(PY, 80); frames(30)
  hold({a = true}, 3); frames(20)
  check(rd(STATE) == 3 and rd(CUR) == 1, "dungeon 1 entered")
  check(wait_until(function() return rd(INTRO) == 0 end, 100), "intro ends")

  -- no ability: a swing is only a swing
  wr(ABIL, 0)
  face(0, 100)
  swing(); frames(2)
  check(rd(PFX) == 0 and rd(SWORD) > 0, "no ability: sword swings, no wave")
  frames(25); place(100)

  -- ability + 3 hearts: the swing throws a wave in the facing direction
  wr(ABIL, 16)
  face(0, 100)
  held = {b = true}; place(100); frames(1); held = {}
  place(100); frames(1)
  check(rd(PFX) ~= 0, "ability + 3 hearts: a wave is thrown, pf_x=" .. rd(PFX))
  check(rd(SWORD) > 0, "the sword swings as well")
  check(rd(PFX) >= 112 and rd(PFX) <= 118 and rd(PFY) == FLOOR_Y + 8, "wave starts in front of the player (x " .. rd(PFX) .. ", y " .. rd(PFY) .. ")")
  check(rd(OAM_PF + 1) == WAVE and rd(OAM_PF + 2) == 3 and rd(OAM_PF) == rd(PFY) - 1, "wave sprite: tile 222, palette 3, at pf_y")
  check(rd(PFCD) == 0, "no fireball cooldown from a wave")
  local x0 = rd(PFX)
  place(100); frames(1)
  check(rd(PFX) == x0 + 3, "wave flies 3 px/frame, x " .. x0 .. " -> " .. rd(PFX))
  -- Up + B while the wave flies: no fireball (shared projectile)
  local xb = rd(PFX)
  hold({up = true, b = true}, 3)
  place(100)
  check(rd(OAM_PF + 1) == WAVE and rd(PFX) > xb, "a flying wave blocks a fireball (shared projectile)")
  -- despawns at the right wall
  check(wait_until(function() place(100); return rd(PFX) == 0 end, 100), "the wave is gone at the wall")
  check(rd(OAM_PF) == 0xFF, "wave sprite hidden")

  -- facing left: the wave flies left and the sprite is flipped
  face(1, 150)
  held = {b = true}; place(150); frames(1); held = {}
  place(150); frames(1)
  check(rd(PFX) ~= 0 and rd(PFX) < 150 and rd(OAM_PF + 2) == (3 | 0x40), "facing left: wave flies left, sprite flipped, pf_x=" .. rd(PFX))
  local xl = rd(PFX)
  place(150); frames(1)
  check(rd(PFX) == xl - 3, "left wave -3 px/frame")
  check(wait_until(function() place(150); return rd(PFX) == 0 end, 100), "the wave is gone at the left wall")
  frames(10); place(150)

  -- 2 hearts: sword only
  face(0, 100)
  held = {b = true}; place(100, 2); frames(1); held = {}
  place(100, 2); frames(3)
  check(rd(PFX) == 0 and rd(SWORD) > 0, "2 hearts: sword only, no wave")
  frames(20); place(100)

  -- the fireball is unchanged (Up + B, tile 29, cooldown 40) with both abilities; the swing afterwards waves only when it is gone
  wr(ABIL, 20)
  face(0, 100)
  held = {up = true, b = true}; place(100); frames(1); held = {}
  place(100); frames(1)
  check(rd(PFX) ~= 0 and rd(OAM_PF + 1) == FIRE and rd(PFCD) > 30, "Up + B still throws the fireball (tile 29, cooldown)")
  frames(10); place(100)
  swing(); place(100); frames(1)
  check(rd(OAM_PF + 1) == FIRE, "a swing while the fireball flies throws no wave")
  check(wait_until(function() place(100); return rd(PFX) == 0 end, 100), "fireball gone")
  frames(20); place(100)
  swing(); place(100); frames(1)
  check(rd(PFX) ~= 0 and rd(OAM_PF + 1) == WAVE, "after the fireball a swing throws the wave again (tile back to 222)")
  check(wait_until(function() place(100); return rd(PFX) == 0 end, 100), "wave gone")

  -- a wave hits the boss: exactly 1 hp, wave consumed, hit blink (shared hit path)
  wr(ABIL, 16)
  pin = 200
  face(0, 48)
  place(48)
  local hp = rd(EHP)
  held = {b = true}; place(48); frames(1); held = {}
  local gone = wait_until(function() place(48); return rd(PFX) == 0 end, 100)
  check(gone, "the wave ends at the imp")
  check(rd(EHP) == hp - 1 and rd(EFLASH) > 0, "wave hit: hp " .. hp .. " -> " .. rd(EHP) .. ", hit blink " .. rd(EFLASH))
  for _ = 1, 40 do place(48); frames(1) end
  check(rd(EHP) == hp - 1, "only once per wave, hp=" .. rd(EHP))

  print("sword wave test OK")
  emu.stop(0)
end)

emu.addEventCallback(function() emu.setInput(held, 0, 0) end, emu.eventType.inputPolled)
emu.addEventCallback(function()
  if coroutine.status(co) == "dead" then return end
  local ok, err = coroutine.resume(co)
  if not ok then print("ERROR: " .. tostring(err)); emu.stop(1) end
end, emu.eventType.endFrame)
