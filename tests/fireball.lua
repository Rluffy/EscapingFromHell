-- Fireball ability test: Up + B. Without the ability it is a normal sword swing; with it a single projectile flies in the
-- facing direction (3 px/frame, gone at the wall, cooldown 40, no sword swing), hurts bosses by exactly 1
-- through the shared hit path (phases work), and passes through an untouchable boss. Addresses: docs/TECH.md "Debug-Adressen".
local M = emu.memType.nesMemory
local held = {}
local function rd(a) return emu.read(a, M) end
local function rd16(a) return rd(a) + 256 * rd(a + 1) end
local function wr(a, v) emu.write(a, v, M) end
local function wr16(a, v) wr(a, v % 256); wr(a + 1, v // 256) end
local function ppu(a) return emu.read(a, emu.memType.nesPpuMemory) end
local STATE, PX, PY, CUR, MASK = 0x302, 0x303, 0x305, 0x30A, 0x308
local HEARTS, INV, SWORD, PAUSED = 0x30B, 0x30C, 0x30E, 0x317
local EX, EY, EHP, EFLASH = 0x310, 0x311, 0x314, 0x315
local PHASE, INTRO, FX, ABIL = 0x318, 0x31A, 0x321, 0x322
local HIDE, PFX, PFY, PFCD = 0x327, 0x329, 0x32A, 0x32B
local FLOOR_Y = 176
local OAM_PF = 0x200 + 136

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
local function enter(n, mask, px, py)        -- overworld door -> dungeon n, wait out the intro
  wr16(MASK, mask); wr16(PX, px); wr(PY, py); frames(30)
  hold({a = true}, 3); frames(20)
  check(rd(STATE) == 3 and rd(CUR) == n, "dungeon " .. n .. " entered")
  check(wait_until(function() return rd(INTRO) == 0 end, 100), "intro ends")
end
local function leave()                       -- Start, then Select
  hold({start = true}, 3); frames(5); hold({select = true}, 3); frames(10)
  check(rd(STATE) == 2, "left the dungeon")
end
local function place(px)                     -- player on the floor, safe, facing as is
  wr16(PX, px); wr(PY, FLOOR_Y); wr(HEARTS, 3); wr(INV, 99)
end
local function shoot() hold({up = true, b = true}, 3) end

co = coroutine.create(function()
  frames(10); held = {start = true}; frames(3); held = {}; frames(60)   -- boot menu: Start = NORMAL
  check(rd(STATE) == 2, "boot reaches overworld")
  check(rd(ABIL) == 0, "new game: no abilities")

  -- Imp (dungeon 1). Without the ability Up + B is a sword swing and spawns nothing.
  enter(1, 0, 48, 80)
  wr(EY, 0); place(100)                       -- imp parked at the ceiling, harmless
  hold({right = true}, 2); place(100); frames(2)
  shoot()
  check(rd(PFX) == 0 and rd(PFCD) == 0, "no ability: no projectile, pf_x=" .. rd(PFX))
  check(rd(SWORD) > 0, "no ability: Up + B swings the sword")
  frames(25)

  -- With the ability: one projectile, no sword swing.
  wr(ABIL, 4)
  wr(EY, 0); place(100); frames(2)
  check(rd(SWORD) == 0, "sword idle before the shot")
  shoot()
  check(rd(SWORD) == 0, "Up + B with the ability: no sword swing")
  local x1, y1 = rd(PFX), rd(PFY)
  check(x1 ~= 0 and y1 == FLOOR_Y + 4, "projectile spawned, x=" .. x1 .. " y=" .. y1)
  check(x1 > 112 and rd(PFCD) > 30, "starts ahead of the player, cooldown running, cd=" .. rd(PFCD))
  frames(1)
  local x2 = rd(PFX)
  check(x2 - x1 == 3, "moves 3 px/frame to the right, dx=" .. (x2 - x1))
  check(rd(OAM_PF) == y1 - 1 and rd(OAM_PF + 3) == x2 and rd(OAM_PF + 1) == 29, "projectile sprite drawn (tile 29)")
  -- max 1 on screen: a second press while it flies adds nothing and still no sword
  place(100); hold({up = true, b = true}, 3)
  check(rd(SWORD) == 0, "second press: still no sword swing")
  frames(1)
  check(rd(PFX) > x2, "only the one projectile keeps flying")
  -- despawns at the wall
  check(wait_until(function() place(100); return rd(PFX) == 0 end, 60), "gone at the right wall")
  check(rd(OAM_PF) == 0xFF, "sprite hidden when gone")
  frames(30)

  -- cooldown: at the wall the projectile dies after ~5 frames, the cooldown still blocks the next one
  place(200); frames(2)
  shoot()
  check(rd(PFX) ~= 0, "shot at the right wall")
  check(wait_until(function() place(200); return rd(PFX) == 0 end, 10), "gone right at the wall")
  place(200); frames(10)
  check(rd(PFCD) > 0, "cooldown still running, cd=" .. rd(PFCD))
  shoot()
  check(rd(PFX) == 0 and rd(SWORD) == 0, "cooldown blocks the shot and no sword swing either")
  check(wait_until(function() place(200); return rd(PFCD) == 0 end, 60), "cooldown ends (40 frames)")
  shoot()
  check(rd(PFX) ~= 0, "next shot after the cooldown")
  wait_until(function() place(200); return rd(PFX) == 0 end, 10)
  frames(45)

  -- facing left: projectile flies left, gone at the left wall
  hold({left = true}, 2); place(100); frames(2)
  shoot()
  x1 = rd(PFX); frames(1)
  check(x1 ~= 0 and x1 < 100 and rd(PFX) - x1 == -3, "flies left at 3 px/frame, x " .. x1 .. " -> " .. rd(PFX))
  check(wait_until(function() place(100); return rd(PFX) == 0 end, 60), "gone at the left wall")
  frames(45)
  -- plain B still swings the sword with the ability
  place(100); hold({b = true}, 2)
  check(rd(SWORD) > 0 and rd(PFX) == 0, "B without Up: sword swing, no projectile")
  frames(20)

  -- boss hit: exactly 1 hp, flash, shared phase path (hp 8 -> 7 = phase 2 effect), projectile consumed
  hold({right = true}, 2)
  wr(EHP, 10); wr(EFLASH, 0); wr(EX, 140); wr(EY, FLOOR_Y); place(100)
  shoot()
  check(wait_until(function() return rd(EHP) < 10 end, 30), "projectile hits the imp")
  check(rd(EHP) == 9 and rd(EFLASH) > 0 and rd(PFX) == 0 and rd(PHASE) == 1, "exactly 1 hp, flash, consumed, hp=" .. rd(EHP))
  frames(45)
  place(100); wr(EHP, 8); wr(EFLASH, 0); wr(EX, 140); wr(EY, FLOOR_Y)
  shoot()
  check(wait_until(function() return rd(EHP) < 8 end, 30), "second hit")
  check(rd(EHP) == 7 and rd(PHASE) == 2 and rd(FX) > 0, "hp 7 = phase 2 with the phase effect, phase=" .. rd(PHASE))
  frames(45)
  wr(EFLASH, 0); wr(FX, 0)
  leave()

  -- untouchable boss: Lava snake submerged (boss_hide bit 0) - the projectile passes through
  enter(4, 7, 336, 48)
  check(wait_until(function() place(100); return rd(HIDE) == 3 end, 400), "snake submerged")
  local hp = rd(EHP)
  local sx = rd(EX)
  wr(EFLASH, 0)
  shoot()
  check(wait_until(function() place(100); return rd(PFX) == 0 end, 80), "projectile flew to the wall")
  check(rd(EHP) == hp, "untouchable: hp unchanged, hp=" .. rd(EHP))
  leave()

  print("fireball test OK")
  emu.stop(0)
end)

emu.addEventCallback(function() emu.setInput(held, 0, 0) end, emu.eventType.inputPolled)
emu.addEventCallback(function()
  if coroutine.status(co) == "dead" then return end
  local ok, err = coroutine.resume(co)
  if not ok then print("ERROR: " .. tostring(err)); emu.stop(1) end
end, emu.eventType.endFrame)
