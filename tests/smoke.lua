local frames = 0
emu.addEventCallback(function()
  frames = frames + 1
  if frames < 120 then return end
  local fc = emu.read(0x0300, emu.memType.nesMemory) + 256 * emu.read(0x0301, emu.memType.nesMemory)
  local gs = emu.read(0x0302, emu.memType.nesMemory)
  print("frame_count=" .. fc .. " game_state=" .. gs)
  if gs == 1 and fc >= 100 then emu.stop(0) else emu.stop(1) end
end, emu.eventType.endFrame)
