local class = require("class")

local StageTrack = class(function(stageTrack, normalMusic, dangerMusic)
  assert(normalMusic, "A stage track needs at least a normal music!")
  stageTrack.normalMusic = normalMusic
  stageTrack.dangerMusic = dangerMusic
  stageTrack.currentMusic = nil
  stageTrack.state = "normal"
end)

function StageTrack:changeMusic(useDangerMusic)
  if self.dangerMusic then
    self:stop()
    if useDangerMusic then
      self.state = "danger"
    else
      self.state = "normal"
    end
    self:play()
  end
end

function StageTrack:update()
  if self.currentMusic then
    self.currentMusic:update()
  end
end

function StageTrack:play()
  if self.state == "normal" then
    self.currentMusic = self.normalMusic
  else
    self.currentMusic = self.dangerMusic
  end

  self.currentMusic:play()
end

function StageTrack:isPlaying()
  if self.currentMusic then
    return self.currentMusic:isPlaying()
  else
    return false
  end
end

function StageTrack:stop()
  self.normalMusic:stop()
  if self.dangerMusic then
    self.dangerMusic:stop()
  end

  self.currentMusic = nil
end

-- pauses the currently running music
function StageTrack:pause()
  if self.currentMusic then
    self.currentMusic:pause()
  end
end

-- sets the volume of the track in % relative to the configured music volume
function StageTrack:setVolume(volume)
  self.normalMusic:setVolume(volume)
  if self.dangerMusic then
    self.dangerMusic:setVolume(volume)
  end
end

-- returns the volume of the track in % relative to the configured music volume
function StageTrack:getVolume()
  return self.normalMusic:getVolume()
end

return StageTrack