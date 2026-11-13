-- Music test (src/music.s, assets/songs.txt): the right song plays in every scene, the APU registers (pulse 1, pulse 2, noise,
-- triangle) really change, effects mute and then hand back their channel without disturbing the timeline, songs loop,
-- pause silences and resumes, phase 3 is faster, music_update stays cheap. Addresses: docs/TECH.md "Debug-Adressen", "Musik (v1.1)".
local M = emu.memType.nesMemory
local held = {}
local function rd(a) return emu.read(a, M) end
local function rd16(a) return rd(a) + 256 * rd(a + 1) end
local function wr(a, v) emu.write(a, v, M) end
local function wr16(a, v) wr(a, v % 256); wr(a + 1, v // 256) end
local STATE, PX, PY, MASK, CUR = 0x302, 0x303, 0x305, 0x308, 0x30A
local HEARTS, INV, PAUSED = 0x30B, 0x30C, 0x317
local EX, EY, EHP, EFLASH = 0x310, 0x311, 0x314, 0x315
local INTRO, DEAD, PHASE = 0x31A, 0x319, 0x318
local ID = 0x33A                                  -- sfx_id: pulse 1, pulse 2, noise
local SONG, LOOPS, MUTE, ROWS, TEMPO = 0x344, 0x345, 0x346, 0x347, 0x349
local TITLE, OVERWORLD, BOSS, FINAL, VICTORY, ENDING = 1, 2, 3, 4, 5, 6
local FLOOR_Y = 176

local co
local function frames(n) for _ = 1, n do coroutine.yield() end end
local function hold(keys, n) held = keys; frames(n); held = {} end
local function press(keys) hold(keys, 3); frames(5) end
local function check(cond, msg)
  if not cond then print("FAIL: " .. msg); emu.stop(1); coroutine.yield() end
end
local function wait_until(f, max)
  for _ = 1, max do if f() then return true end frames(1) end
  return f()
end

-- per-frame APU sampling
local VOL = { "apu.square1.envelope.volume", "apu.square2.envelope.volume", "apu.noise.envelope.volume" }
local PER = { "apu.square1.realPeriod", "apu.square2.realPeriod", "apu.noise.timer.period", "apu.triangle.timer.period" }
local seen, tri_on, tri_off, bad = {}, false, false, nil
local function reset_seen() seen = { {}, {}, {}, {} }; tri_on = false; tri_off = false end
reset_seen()
local last = {}
local function sample()
  local s = emu.getState()
  for ch = 1, 4 do
    local p = s[PER[ch]]
    if ch < 4 then
      local v = s[VOL[ch]]
      if rd(ID + ch - 1) == 0 and v > 8 then bad = "channel " .. ch .. " volume " .. v end      -- music is quieter than the effects (up to 10)
      if v > 0 and rd(ID + ch - 1) == 0 then seen[ch][p] = true end
    elseif s["apu.triangle.linearCounterReload"] == 127 then seen[4][p] = true; tri_on = true
    elseif s["apu.triangle.linearCounterReload"] == 0 then tri_off = true end
  end
  last = s
  return s
end
local function nseen(ch) local n = 0; for _ in pairs(seen[ch]) do n = n + 1 end return n end

-- cost of music_update: from its first instruction (lda $0344; beq) to the instruction after the jsr in the main loop
local c0, cmax, csum, cn, cwhere = 0, 0, 0, 0, ""
local function cycles() return emu.getState()["cpu.cycleCount"] end
local function find_update()                     -- after boot: the banks are mapped
  local UPD, RET
  for a = 0xA000, 0xBFF0 do
    if rd(a) == 0xAD and rd(a + 1) == 0x44 and rd(a + 2) == 0x03 and rd(a + 3) == 0xF0 then UPD = a; break end
  end
  if not UPD then print("FAIL: music_update not found in the music bank"); emu.stop(1); coroutine.yield() end
  for a = 0xC000, 0xFFF0 do
    if rd(a) == 0x20 and rd(a + 1) == UPD % 256 and rd(a + 2) == UPD // 256 then RET = a + 3; break end
  end
  if not RET then print("FAIL: the main loop does not call music_update"); emu.stop(1); coroutine.yield() end
  emu.addMemoryCallback(function() c0 = cycles() end, emu.callbackType.exec, UPD)
  emu.addMemoryCallback(function()
    local c = cycles() - c0
    if c > cmax then cmax = c; cwhere = rd(SONG) .. " row " .. rd16(ROWS) end
    csum = csum + c; cn = cn + 1
  end, emu.callbackType.exec, RET)
end

local pin = function() end
local function enter(n)
  wr16(PX, (6 * n - 3) * 16); wr(PY, (n % 2 == 1) and 80 or 48); frames(30)
  press({a = true}); frames(20)
  check(rd(STATE) == 3 and rd(CUR) == n, "dungeon " .. n .. " entered, state=" .. rd(STATE))
  check(wait_until(function() return rd(INTRO) == 0 end, 100), "intro ends")
end
local function safe() wr16(PX, 100); wr(PY, FLOOR_Y); wr(HEARTS, 3); wr(INV, 99) end
local function kill_boss()                      -- boss next to the player with 1 hp, swing until it dies
  pin = function() safe(); wr(EX, 114); wr(EY, FLOOR_Y); wr(EFLASH, 0) end
  wr(EHP, 1); frames(2)
  check(wait_until(function() held = { b = rd(0x300) % 2 == 0 }; return rd(DEAD) == 1 end, 600), "boss killed")
  held = {}
end

co = coroutine.create(function()
  -- the music bank stays at $A000 (apu_base table 0, 4, 12, 8) in every scene
  local function bank_ok() return rd(0xA000) == 0 and rd(0xA001) == 4 and rd(0xA002) == 12 and rd(0xA003) == 8 end

  -- title: song 1, all four channels sound and change
  frames(20)
  find_update()
  check(rd(STATE) == 1, "boot shows the start menu")
  check(rd(SONG) == TITLE, "title plays song TITLE, got " .. rd(SONG))
  check(emu.getState()["apu.triangle.lengthCounter.enabled"], "$4015 enables the triangle")
  check(bank_ok(), "music bank at $A000 on the title screen")
  reset_seen()
  frames(400)
  check(nseen(1) >= 3 and nseen(2) >= 3, "pulse 1 / pulse 2 change pitch: " .. nseen(1) .. "/" .. nseen(2))
  check(nseen(3) >= 1, "noise plays: " .. nseen(3))
  check(nseen(4) >= 2 and tri_on and tri_off, "triangle ($4008) plays and gates: " .. nseen(4))
  check(rd(LOOPS) == 0 and rd16(ROWS) >= 38 and rd16(ROWS) <= 42, "rows count frames / 10: " .. rd16(ROWS))
  check(rd(TEMPO) == 10, "title tempo 10, got " .. rd(TEMPO))

  -- menu to intro to overworld: the title music goes on through the intro, then OVERWORLD
  hold({ down = true }, 3); frames(15)
  local r0 = rd16(ROWS)
  hold({ a = true }, 3)
  check(wait_until(function() return rd(STATE) == 5 end, 60), "intro shows")
  frames(30)
  check(rd(SONG) == TITLE and rd16(ROWS) > r0, "the intro keeps the title song running (no restart)")
  hold({ start = true }, 3)
  check(wait_until(function() return rd(STATE) == 2 end, 60), "overworld reached")
  frames(5)                                      -- game_state is set before the redraw (a few frames), the song starts with it
  check(rd(SONG) == OVERWORLD and rd(TEMPO) == 9, "overworld plays OVERWORLD, got " .. rd(SONG))
  reset_seen()
  frames(300)
  check(nseen(1) >= 3 and nseen(2) >= 3 and nseen(3) >= 1 and nseen(4) >= 2, "overworld channels play")
  check(bank_ok(), "music bank at $A000 on the overworld")

  -- dungeon 1: BOSS from the top, tempo 7
  wr16(MASK, 0x3FF)
  enter(1)
  pin = function() safe(); wr(EY, 0) end
  check(rd(SONG) == BOSS and rd(TEMPO) == 7, "dungeon 1 plays BOSS at tempo 7, got " .. rd(SONG) .. "/" .. rd(TEMPO))
  check(bank_ok(), "music bank at $A000 in a dungeon (boss bank at $8000)")
  check(rd16(ROWS) < 30, "BOSS restarted on entry: rows " .. rd16(ROWS))
  reset_seen()
  frames(300)
  check(nseen(1) >= 3 and nseen(2) >= 3 and nseen(3) >= 2 and nseen(4) >= 3, "boss song channels play")

  -- an effect on pulse 1 mutes the music there, keeps its timeline, and gives the channel back
  pin = function() wr16(PX, 100); wr(PY, FLOOR_Y); wr(HEARTS, 3); wr(EX, 100); wr(EY, FLOOR_Y); wr(EFLASH, 0) end
  wr(INV, 0)
  local f0, rows0, muted, muted_vol = rd16(0x300), rd16(ROWS), false, nil
  for _ = 1, 20 do
    local s = sample()
    if rd(ID) ~= 0 and rd(MUTE) & 1 == 1 then muted = true; muted_vol = s[VOL[1]] end
    frames(1)
  end
  check(muted, "pulse 1 effect (hurt) sets the mute bit")
  check(rd(MUTE) & 1 == 0 and rd(ID) == 0, "effect over: mute bit cleared")
  pin = function() safe(); wr(EY, 0) end
  reset_seen()
  frames(60)
  check(nseen(1) >= 1 and next(seen[1]) ~= nil, "music resumed on pulse 1 after the effect")
  local dr, df = rd16(ROWS) - rows0, rd16(0x300) - f0
  check(math.abs(dr - df // 7) <= 1, "timeline kept while muted: " .. dr .. " rows in " .. df .. " frames")

  -- pause: silence, rows stand still; unpause: the song goes on (same song, no restart)
  local rows1 = rd16(ROWS)
  press({ start = true }); frames(5)
  check(rd(PAUSED) == 1, "paused")
  local s = emu.getState()
  check(s[VOL[1]] == 0 and s[VOL[2]] == 0 and s[VOL[3]] == 0 and s["apu.triangle.linearCounterReload"] == 0, "pause silences all four channels")
  local rows2 = rd16(ROWS)
  frames(40)
  check(rd16(ROWS) == rows2 and rd(SONG) == BOSS, "rows stand still while paused")
  press({ start = true })
  frames(30)
  check(rd(PAUSED) == 0 and rd16(ROWS) > rows2 and rd16(ROWS) < rows2 + 40 and rd(SONG) == BOSS, "unpaused: the song goes on")

  -- loop: pulse 1 jumps back after 256 rows, the song never stops
  local lrows
  check(wait_until(function() sample(); if rd(LOOPS) >= 1 and not lrows then lrows = rd16(ROWS) end return lrows ~= nil end, 2500), "BOSS loops")
  check(lrows >= 255 and lrows <= 258, "one loop = 256 rows: " .. tostring(lrows))
  reset_seen()
  frames(300)
  check(rd(SONG) == BOSS and nseen(1) >= 3 and nseen(2) >= 3 and nseen(4) >= 3, "keeps playing after the loop")
  check(rd(LOOPS) >= 1 and bad == nil, "no stray volume: " .. tostring(bad))

  -- phase 3: faster tempo (3/4), same song
  pin = function() safe(); wr(EX, 114); wr(EY, FLOOR_Y); wr(EFLASH, 0) end
  wr(EHP, 6); wr(PHASE, 1); frames(3)
  rows0 = rd16(ROWS)
  held = { b = true }; frames(3); held = {}
  check(wait_until(function() return rd(PHASE) == 3 end, 30), "boss in phase 3")
  frames(3)
  check(rd(TEMPO) == 6 and rd(SONG) == BOSS, "phase 3: tempo 7 -> 6, got " .. rd(TEMPO))
  rows0 = rd16(ROWS); f0 = rd16(0x300)
  frames(120)
  local fast = rd16(ROWS) - rows0
  check(fast >= 19 and fast <= 21, "120 frames at tempo 6 = 20 rows: " .. fast)

  -- victory: the fanfare starts with the C-E-G-C arpeggio on pulse 1, pulse 2 is muted by the SFX jingle meanwhile, then OVERWORLD
  local periods, mute2 = {}, false
  pin = function() safe(); wr(EX, 114); wr(EY, FLOOR_Y); wr(EFLASH, 0) end
  wr(EHP, 1); frames(2)
  check(wait_until(function() held = { b = rd(0x300) % 2 == 0 }; return rd(DEAD) == 1 end, 600), "boss killed")
  held = {}
  pin = function() end
  check(wait_until(function() return rd(SONG) == VICTORY end, 30), "victory plays VICTORY, got " .. rd(SONG))
  check(rd(TEMPO) == 4 and rd16(ROWS) <= 2, "VICTORY from the top at tempo 4")
  for _ = 1, 30 do
    local s = sample()
    if rd(ID + 1) == 8 and rd(MUTE) & 2 == 2 then mute2 = true end
    if s[VOL[1]] > 0 then periods[s[PER[1]]] = true end
    frames(1)
  end
  check(periods[213] and periods[169] and periods[142] and periods[106], "fanfare arpeggio C5 E5 G5 C6 on pulse 1")
  check(mute2, "pulse 2 muted while SFX_VICTORY plays")
  check(wait_until(function() return rd(STATE) == 2 end, 400), "back on the overworld")
  frames(5)
  check(rd(SONG) == OVERWORLD, "overworld song again, got " .. rd(SONG))

  -- dungeon 10: FINAL; victory over the last demon: VICTORY, then the ending screen plays ENDING, then the overworld
  enter(10)
  check(rd(SONG) == FINAL and rd(TEMPO) == 6, "dungeon 10 plays FINAL at tempo 6, got " .. rd(SONG))
  reset_seen()
  frames(300)
  check(nseen(1) >= 3 and nseen(2) >= 3 and nseen(3) >= 2 and nseen(4) >= 3, "final song channels play")
  pin = function() safe(); wr(EX, 114); wr(EY, FLOOR_Y); wr(EFLASH, 0) end
  wr(EHP, 1)
  check(wait_until(function() held = { b = rd(0x300) % 2 == 0 }; return rd(DEAD) == 1 end, 900), "last boss killed")
  held = {}; pin = function() end
  check(wait_until(function() return rd(SONG) == VICTORY end, 30), "last victory plays VICTORY")
  check(wait_until(function() return rd(STATE) == 4 end, 400), "ending screen")
  check(rd(SONG) == ENDING and rd(TEMPO) == 8, "ending plays ENDING at tempo 8, got " .. rd(SONG))
  reset_seen()
  frames(200)
  check(nseen(1) >= 3 and nseen(4) >= 3, "ending channels play")
  frames(200)
  check(rd(STATE) == 4 and rd(SONG) == ENDING, "ending screen and song stay until Start")
  wr(0x336, 100); press({start = true})
  check(wait_until(function() return rd(STATE) == 2 end, 20), "back on the overworld")
  frames(5)
  check(rd(SONG) == OVERWORLD, "overworld song after the ending, got " .. rd(SONG))
  check(bad == nil, "music never louder than 8 while no effect plays: " .. tostring(bad))

  -- cost
  print(string.format("music_update: max %d cycles (song %s), mean %.0f over %d frames", cmax, cwhere, csum / cn, cn))
  check(cmax < 1500, "music_update max " .. cmax .. " cycles (limit 1500)")
  print("music test OK")
  emu.stop(0)
end)

emu.addEventCallback(function() emu.setInput(held, 0, 0) end, emu.eventType.inputPolled)
emu.addEventCallback(function()
  if coroutine.status(co) == "dead" then return end
  sample()
  pin()
  local ok, err = coroutine.resume(co)
  if not ok then print("ERROR: " .. tostring(err)); emu.stop(1) end
end, emu.eventType.endFrame)
