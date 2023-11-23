local Scene = require("scenes.Scene")
local sceneManager = require("scenes.sceneManager")
local CharacterSelect = require("scenes.CharacterSelect")
local class = require("class")
local GameModes = require("GameModes")

--@module CharacterSelectTraining
-- 
local CharacterSelectTraining = class(
  function (self, sceneParams)
    print(dump(sceneParams))
    self.players = {{}, {}}
    self:load(sceneParams)
  end,
  CharacterSelect
)

CharacterSelectTraining.name = "CharacterSelectTraining"
sceneManager:addScene(CharacterSelectTraining)

function CharacterSelectTraining:customLoad(sceneParams)
  GAME.battleRoom = BattleRoom(GameModes.ONE_PLAYER_TRAINING)
  if sceneParams.trainingModeSettings then
    GAME.battleRoom.trainingModeSettings = sceneParams.trainingModeSettings
  end
  GAME.battleRoom.playerNames[2] = nil
end

return CharacterSelectTraining