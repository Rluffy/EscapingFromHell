-- Overworld + dungeon entry/exit test. One coroutine drives the whole run.
-- Addresses: docs/TECH.md "Debug-Adressen". Temple grid: door col 6n-3, door row 5 (odd n) / 3 (even n).
local M = emu.memType.nesMemory
local held = {}
local function rd(a) return emu.read(a, M) end
local function rd16(a) return rd(a) + 256 * rd(a + 1) end
local function wr(a, v) emu.write(a, v, M) end
local function wr16(a, v) wr(a, v % 256); wr(a + 1, v // 256) end
local STATE, PX, PY, CAM, MASK, CUR = 0x302, 0x303, 0x305, 0x306, 0x308, 0x30A

local co
local function frames(n) for _ = 1, n do coroutine.yield() end end
local function hold(keys, n) held = keys; frames(n); held = {} end
local function press(keys) hold(keys, 3); frames(5) end
local function check(cond, msg)
  if not cond then print("FAIL: " .. msg); emu.stop(1); coroutine.yield() end
end
local function teleport(n, below_gate)  -- onto door n, or on the path cell below its gate
  local dr = (n % 2 == 1) and 5 or 3
  wr16(PX, (6 * n - 3) * 16)
  wr(PY, (dr + (below_gate and 2 or 0)) * 16)
  frames(30)                              -- the camera jump triggers a full redraw
end
local function gate_tile(n)                -- background tile drawn at the gate of dungeon n
  local dr = (n % 2 == 1) and 5 or 3
  local col = (6 * n - 3) * 2             -- left tile column; both nametables hold distinct columns
  return emu.read(0x2000 + ((col // 32) % 2) * 0x400 + (dr + 1) * 2 * 32 + col % 32, emu.memType.nesPpuMemory)
end

co = coroutine.create(function()
  frames(10); held = {start = true}; frames(3); held = {}; frames(60)   -- boot menu: Start = NORMAL
  check(rd(STATE) == 2, "(a) boot reaches overworld, state=" .. rd(STATE))

  local x0, c0 = rd16(PX), rd16(CAM)
  hold({right = true}, 80)
  check(rd16(PX) > x0 + 100, "(b) player x grows, x=" .. rd16(PX))
  check(rd16(CAM) > c0, "(b) camera x grows, cam=" .. rd16(CAM))

  check(rd16(MASK) == 0, "mask starts at 0")
  teleport(2, true)
  check(gate_tile(2) == 7, "(c) locked gate tile drawn, tile=" .. gate_tile(2))
  hold({up = true}, 40)
  check(rd(STATE) == 2 and rd(PY) >= 70, "(c) locked gate blocks, y=" .. rd(PY))
  teleport(2, false)
  press({a = true})
  check(rd(STATE) == 2, "(c) A on locked entrance does nothing")

  teleport(1, false)
  press({a = true})
  frames(20)                              -- building the arena takes a few frames
  check(rd(STATE) == 3 and rd(CUR) == 1, "(d) dungeon 1 entered, state=" .. rd(STATE) .. " cur=" .. rd(CUR))
  frames(10)
  press({b = true})
  check(rd(STATE) == 3, "(d) B does not leave the dungeon")
  press({select = true})
  check(rd(STATE) == 3, "(d) Select alone does not leave")
  press({start = true})
  press({select = true})
  check(rd(STATE) == 2 and rd(CUR) == 0, "(d) Start+Select returns to overworld")
  check(rd16(PX) == 48 and rd(PY) == 80, "(d) player at entrance 1, x=" .. rd16(PX))

  teleport(2, true)
  wr16(MASK, 1)                           -- dungeon 1 cleared
  frames(30)
  check(gate_tile(2) == 8, "(e) gate redrawn open after mask change, tile=" .. gate_tile(2))
  hold({up = true}, 40)
  check(rd(PY) >= 36 and rd(PY) <= 51, "(e) player walked through the open gate, y=" .. rd(PY))
  press({a = true})
  frames(20)
  check(rd(STATE) == 3 and rd(CUR) == 2, "(e) dungeon 2 entered, state=" .. rd(STATE) .. " cur=" .. rd(CUR))
  press({start = true})
  press({select = true})
  check(rd(STATE) == 2 and rd16(PX) == 144 and rd(PY) == 48, "(e) Select returns to entrance 2")

  print("overworld test OK")
  emu.stop(0)
end)

emu.addEventCallback(function() emu.setInput(held, 0, 0) end, emu.eventType.inputPolled)
emu.addEventCallback(function()
  if coroutine.status(co) == "dead" then return end
  local ok, err = coroutine.resume(co)
  if not ok then print("ERROR: " .. tostring(err)); emu.stop(1) end
end, emu.eventType.endFrame)
