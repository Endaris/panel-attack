local RollbackBuffer = require("common.engine.RollbackBuffer")

local function testNormalRollback()
  local buffer = RollbackBuffer(250)

  for i = 1, 300 do
    buffer:saveCopy(i, { i = i})
  end

  local rollbackCopy = buffer:rollbackToFrame(147)
  assert(rollbackCopy, "Should have been able to rollback 103 frames")
  assert(rollbackCopy.i == 147, "Rolled back to frame " .. rollbackCopy.i .. " instead of 147")
end

local function testStaleMarking()
  local buffer = RollbackBuffer(250)

  for i = 1, 300 do
    buffer:saveCopy(i, { i = i})
  end

  local rollbackCopy = buffer:rollbackToFrame(147)
  rollbackCopy = buffer:rollbackToFrame(150)
  assert(rollbackCopy == nil, "Rollback copies in the future should no longer be available via the accessor")
  rollbackCopy = buffer.buffer[buffer.currentIndex + 3]
  assert(rollbackCopy, "copies for stale frames should not get discarded")
  assert(rollbackCopy.i, "the copy for frame 150 should still be available here, instead it is the copy for " .. rollbackCopy.i)
end

local function testFrameTooOld()
  local buffer = RollbackBuffer(250)

  for i = 1, 300 do
    buffer:saveCopy(i, { i = i})
  end

  local rollbackCopy = buffer:rollbackToFrame(20)
  assert(rollbackCopy == nil, "Buffer should have only saved the last 250 copies")
end

local function testPostRollbackWrite()
  local buffer = RollbackBuffer(250)

  for i = 1, 300 do
    buffer:saveCopy(i, { i = i})
  end

  buffer:rollbackToFrame(147)
  buffer:saveCopy(148, { i = "148new"})
  assert(buffer.frames[buffer.currentIndex - 2] == 147, "the frame we rollback to is not discarded but kept")
end

testNormalRollback()
testStaleMarking()
testFrameTooOld()
testPostRollbackWrite()