-- Shield test (ability bit 3): hold Down on the ground. Without the ability Down does nothing. With it the player stands still
-- facing the same way, boss projectiles from the front are destroyed without damage, contact from the front only pushes
-- back, hits from behind still cost a heart, no sword while the shield is up, the shield sprite sits in front, and dash,
-- jump, double jump and the fireball still work. Uses the Imp (dungeon 1, parked at the right wall).
-- Addresses: docs/TECH.md "Debug-Adressen".
local M = emu.memType.nesMemory
local held = {}
local function rd(a) return emu.read(a, M) end
local function rd16(a) return rd(a) + 256 * rd(a + 1) end
local function wr(a, v) emu.write(a, v, M) end
local function wr16(a, v) wr(a, v % 256); wr(a + 1, v // 256) end
local STATE, PX, PY, CUR, MASK = 0x302, 0x303, 0x305, 0x30A, 0x308
local HEARTS, INV, ONG, SWORD, VY = 0x30B, 0x30C, 0x30D, 0x30E, 0x30F
local EX, EY, EHP = 0x310, 0x311, 0x314
local INTRO, FBX, FBY = 0x31A, 0x31B, 0x31E
local ABIL, DASH, PFX = 0x322, 0x323, 0x329
local SHIELD = 0x331
local FLOOR_Y = 176
local OAM_SH = 0x200 + 16                       -- the sword's two sprites: shield when it is up

local co
local pin = false                              -- keep the imp parked at the right wall every frame
local function frames(n) for _ = 1, n do coroutine.yield() end end
local function hold(keys, n) held = keys; frames(n); held = {} end
local function check(cond, msg)
  if not cond then print("FAIL: " .. msg); emu.stop(1); coroutine.yield() end
end
local function wait_until(f, max)
  for _ = 1, max do if f() then return true end frames(1) end
  return f()
end
local function signed(v) return v >= 128 and v - 256 or v end
local function noshots() wr(FBX, 0); wr(FBX + 1, 0); wr(FBX + 2, 0) end

local function enter()
  wr16(PX, 48); wr(PY, 80); wr16(MASK, 0); frames(30)
  hold({a = true}, 3); frames(20)
  check(rd(STATE) == 3 and rd(CUR) == 1, "dungeon 1 entered")
  check(wait_until(function() return rd(INTRO) == 0 end, 100), "intro ends")
end
-- player on the floor at x, facing right (0) or left (1), safe state reset
local function stand(x, face)
  wr16(PX, x); wr(PY, FLOOR_Y); wr(VY, 0); wr(HEARTS, 3); wr(INV, 0)
  hold(face == 1 and {left = true} or {right = true}, 1)
  wr16(PX, x); wr(PY, FLOOR_Y); frames(2)
end
-- the imp stays parked at the right wall (harmless) unless told otherwise
local function park_imp() wr(EX, 200); wr(EY, FLOOR_Y) end
-- wait for a shot from the imp, return the x where it vanished (the player keeps Down held in `keys`)
local function shot(keys, px)
  held = keys
  local lastx = 0
  check(wait_until(function() park_imp(); return rd(FBX) ~= 0 end, 500), "the imp spits")
  for _ = 1, 200 do
    park_imp()
    frames(1)
    local x = rd(FBX)
    if x == 0 then break end
    lastx = x
    if rd(HEARTS) < 3 then break end
  end
  held = {}
  return lastx
end

co = coroutine.create(function()
  frames(60)
  check(rd(STATE) == 2, "boot reaches overworld")
  enter()
  pin = true
  local function reset_fight() wr(HEARTS, 3); wr(INV, 0); noshots() end

  -- no ability: Down does nothing (the player still walks, no shield, no sprite); a shot hits
  wr(ABIL, 0)
  stand(100, 0)
  local x0 = rd16(PX)
  hold({down = true, right = true}, 10)
  check(rd(SHIELD) == 0 and rd16(PX) == x0 + 20, "no ability: Down + Right walks, shield 0, dx=" .. (rd16(PX) - x0))
  check(rd(OAM_SH) == 0xFF, "no ability: no shield sprite")
  stand(100, 0)
  shot({down = true}, 100)
  check(rd(HEARTS) == 2, "no ability: the imp's fireball hits, hearts=" .. rd(HEARTS))
  wait_until(function() return rd(INV) == 0 end, 130)

  -- with the ability: Down on the ground = stand still, shield in front
  wr(ABIL, 8)
  stand(100, 0)
  x0 = rd16(PX)
  hold({down = true, right = true}, 10)
  check(rd(SHIELD) == 1 and rd16(PX) == x0, "shield: Down + Right does not move, dx=" .. (rd16(PX) - x0))
  stand(100, 0)
  held = {down = true}; frames(2)
  check(rd(OAM_SH + 1) == 30 and rd(OAM_SH + 5) == 31 and rd(OAM_SH + 2) & 3 == 3 and rd(OAM_SH + 3) == 112 and rd(OAM_SH + 7) == 112,
        "shield sprite: tiles 30/31, palette 3, 12 px in front")
  check(rd(OAM_SH) == rd(PY) - 1 and rd(OAM_SH + 4) == rd(PY) + 7, "shield sprite is 16 px tall, level with the player")
  held = {}
  -- no sword while the shield is up
  held = {down = true}; frames(1); hold({down = true, b = true}, 3)
  check(rd(SWORD) == 0, "shield: B does not swing the sword")
  -- releasing Down: shield gone, the sword works again
  frames(2)                                  -- B must be released first: swings start on the press
  hold({b = true}, 3)
  check(rd(SHIELD) == 0 and rd(SWORD) > 0, "released: the sword works again")
  frames(20)
  -- a swing in progress is cut off when the shield goes up
  frames(2)
  hold({b = true}, 2)
  hold({down = true}, 2)
  check(rd(SHIELD) == 1 and rd(SWORD) == 0, "shield cuts off a swing")

  -- from the front: the fireball is destroyed at the shield, no heart, no invulnerability
  stand(100, 0)
  reset_fight()
  local lx = shot({down = true}, 100)
  check(rd(HEARTS) == 3 and rd(INV) == 0, "shield: fireball from the front costs nothing, hearts=" .. rd(HEARTS))
  check(lx >= 108 and lx <= 120, "the fireball died at the shield (x 112..119), last x=" .. lx)

  -- from behind: facing left, the fireball comes from the right and hits
  stand(100, 1)
  reset_fight()
  shot({down = true}, 100)
  check(rd(HEARTS) == 2, "shield: fireball from behind still costs a heart, hearts=" .. rd(HEARTS))
  check(rd(OAM_SH + 3) == 96 and rd(OAM_SH + 2) & 0x40 ~= 0, "facing left: shield sprite 4 px left of the player, flipped")
  wait_until(function() return rd(INV) == 0 end, 130)

  -- contact from the front: no damage, a small push back
  local function contact(dx, keys)       -- imp overlapping the player at imp x = player x + dx, a few frames
    frames(8)                            -- let a leftover push end
    stand(100, 0)
    reset_fight()
    held = keys
    local p0 = rd16(PX)
    pin = false
    for _ = 1, 6 do wr(EX, rd16(PX) + dx); wr(EY, FLOOR_Y); noshots(); frames(1) end
    pin = true
    held = {}
    return p0, rd16(PX)
  end
  local p0, p1 = contact(11, {down = true})
  check(rd(HEARTS) == 3 and rd(INV) == 0, "shield: contact from the front costs nothing, hearts=" .. rd(HEARTS))
  check(p1 < p0 - 6 and p1 >= p0 - 20, "pushed back a little: " .. p0 .. " -> " .. p1)
  p0, p1 = contact(11, {})
  check(rd(HEARTS) == 2, "Down released: the same contact costs a heart, hearts=" .. rd(HEARTS))
  wait_until(function() return rd(INV) == 0 end, 130)
  -- contact from behind
  p0, p1 = contact(-10, {down = true})
  check(rd(HEARTS) == 2, "shield: contact from behind costs a heart, hearts=" .. rd(HEARTS))
  wait_until(function() return rd(INV) == 0 end, 130)

  -- in the air Down does nothing; the shield comes back on landing; jump from the shield works
  stand(100, 0); reset_fight(); park_imp()
  held = {down = true}; frames(2)
  hold({down = true, a = true}, 3)
  check(signed(rd(VY)) < 0 and rd(ONG) == 0, "Down + A jumps, vy=" .. signed(rd(VY)))
  held = {down = true}
  check(rd(SHIELD) == 0, "no shield in the air")
  check(wait_until(function() park_imp(); noshots(); return rd(ONG) == 1 end, 80), "lands")
  frames(2)
  check(rd(SHIELD) == 1, "shield back after landing with Down held")
  held = {}

  -- dash still works (and ends the shield for its duration), also double jump and fireball with all abilities
  wr(ABIL, 8 | 1 | 2 | 4)
  stand(100, 0); reset_fight(); park_imp(); noshots()
  held = {down = true}; frames(2)
  x0 = rd16(PX)
  hold({down = true, select = true}, 2)
  held = {down = true}
  frames(1)
  check(rd(DASH) > 0 and rd(SHIELD) == 0, "dash from the shield works")
  frames(12)
  check(rd16(PX) - x0 >= 36, "dash covers ~40 px, dx=" .. (rd16(PX) - x0))
  held = {}
  stand(100, 0); park_imp(); noshots()
  hold({a = true}, 12)
  check(wait_until(function() return signed(rd(VY)) >= 0 end, 40), "jump apex")
  local apex = rd(PY)
  hold({a = true}, 2)
  check(signed(rd(VY)) < 0 and rd(PY) < apex, "double jump works with the shield ability")
  check(wait_until(function() park_imp(); noshots(); return rd(ONG) == 1 end, 80), "lands")
  stand(100, 0); park_imp(); noshots()
  hold({up = true, b = true}, 3)
  check(rd(PFX) ~= 0 and rd(SWORD) == 0, "fireball (Up + B) works with the shield ability")

  print("shield test OK")
  emu.stop(0)
end)

emu.addEventCallback(function() emu.setInput(held, 0, 0) end, emu.eventType.inputPolled)
emu.addEventCallback(function()
  if coroutine.status(co) == "dead" then return end
  if pin then wr(EX, 200); wr(EY, FLOOR_Y) end
  local ok, err = coroutine.resume(co)
  if not ok then print("ERROR: " .. tostring(err)); emu.stop(1) end
end, emu.eventType.endFrame)
