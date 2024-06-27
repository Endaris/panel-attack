local class = require("common.lib.class")
require("table.new")

-- A specialized class that implements something like a ring buffer to facilitate the (memory) management of rollback copies
-- Precisely the goal is that components using rollback don't have to worry about pool management and deletion of stale copies
local RollbackBuffer = class(function(ring, size)
  ring.size = size
  ring.buffer = table.new(size, 0)
  ring.frames = table.new(size, 0)
  ring.currentIndex = 1
end)

function RollbackBuffer:saveCopy(frame, copy)
  self.buffer[self.currentIndex] = copy
  self.frames[self.currentIndex] = frame

  self.currentIndex = self.currentIndex + 1

  if self.currentIndex > self.size then
    self.currentIndex = 1
  end
end

-- returns the oldest copy in the buffer or a stale one
-- returns nil if the buffer is not full yet
function RollbackBuffer:getOldest()
  return self.buffer[self.currentIndex]
end

-- rolls the buffer back to the specified frame and returns the data for the frame
-- returns nil if no data for the specified frame was found
function RollbackBuffer:rollbackToFrame(frame)
  if frame < 0 then
    error("Cannot rollback to negative frame numbers")
  elseif frame > self.frames[wrap(1, self.currentIndex - 1, self.size)] then
    -- target frame is greater than our most recent non-stale frame
    return nil
  elseif frame < self.frames[self.currentIndex] then
    -- target frame is too far in the past
    return nil
  end

  for i = 1, self.size do
    self.currentIndex = wrap(1, self.currentIndex - 1, self.size)
    if not self.frames[self.currentIndex] or self.frames[self.currentIndex] == -1 then
      -- we've reached an uninitialized or stale part of the buffer, that means there is no data to find further than here
      return nil
    elseif self.frames[self.currentIndex] > frame then
      -- mark the respective data as stale 
      self.frames[self.currentIndex] = -1
      -- but we keep the data because it is still allocated memory we wish to reuse
    elseif self.frames[self.currentIndex] == frame then
      local value = self.buffer[self.currentIndex]
      self.currentIndex = wrap(1, self.currentIndex + 1, self.size)
      return value
    end
  end
end

return RollbackBuffer