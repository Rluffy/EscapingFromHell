local frames = 0
-- Boot shows the start menu (state 1); Start picks NEW GAME, a second Start skips the intro.
emu.addEventCallback(function() emu.setInput({start = (frames >= 30 and frames < 33) or (frames >= 56 and frames < 59)}, 0, 0) end, emu.eventType.inputPolled)
emu.addEventCallback(function()
  frames = frames + 1
  if frames < 160 then return end
  local fc = emu.read(0x0300, emu.memType.nesMemory) + 256 * emu.read(0x0301, emu.memType.nesMemory)
  local gs = emu.read(0x0302, emu.memType.nesMemory)
  print("frame_count=" .. fc .. " game_state=" .. gs)
  if gs == 2 and fc >= 90 then emu.stop(0) else emu.stop(1) end
end, emu.eventType.endFrame)
