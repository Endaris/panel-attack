local GameModes = {}

local Styles = { CHOOSE = 0, CLASSIC = 1, MODERN = 2}
local FileSelection = { NONE = 0, TRAINING = 1, PUZZLE = 2}
local StackInteraction = { NONE = 0, VERSUS = 1, SELF = 2, ATTACK_ENGINE = 3, HEALTH_ENGINE = 4}
local WinCondition = { NONE = 0, GAME_OVER = 1, SCORE = 2, TIME = 3}

local OnePlayerVsSelf = {
  playerCount = 1,
  selectCharacter = true,
  selectLevel = true,
  selectStage = true,
  selectPanels = true,
  selectRanked = false,
  style = Styles.MODERN,
  selectFile = FileSelection.NONE,
  selectColorRandomization = false,
  stackInteraction = StackInteraction.SELF,
  scene = "VsSelfGame",
  richPresenceLabel = loc("mm_1_vs"),
  -- temporary crutch until all checks for this are eliminated
  matchMode = "vs",
  winCondition = WinCondition.NONE,
  doCountdown = true,
  disallowAdjacentColors = true
}

local OnePlayerTimeAttack = {
  playerCount = 1,
  selectCharacter = true,
  selectLevel = true,
  selectStage = true,
  selectPanels = true,
  selectRanked = false,
  style = Styles.CHOOSE,
  selectFile = FileSelection.NONE,
  selectColorRandomization = false,
  stackInteraction = StackInteraction.NONE,
  scene = "TimeAttackGame",
  richPresenceLabel = loc("mm_1_time"),
  matchMode = "time",
  winCondition = WinCondition.NONE,
  doCountdown = true,
  timeLimit = 120,
  disallowAdjacentColors = false
}

local OnePlayerEndless = {
  playerCount = 1,
  selectCharacter = true,
  selectLevel = true,
  selectStage = true,
  selectPanels = true,
  selectRanked = false,
  style = Styles.CHOOSE,
  selectFile = FileSelection.NONE,
  selectColorRandomization = false,
  stackInteraction = StackInteraction.NONE,
  scene = "EndlessGame",
  richPresenceLabel = loc("mm_1_endless"),
  matchMode = "endless",
  winCondition = WinCondition.NONE,
  doCountdown = true,
  disallowAdjacentColors = false
}

local OnePlayerTraining = {
  playerCount = 1,
  selectCharacter = true,
  selectLevel = true,
  selectStage = true,
  selectPanels = true,
  selectRanked = false,
  style = Styles.MODERN,
  selectFile = FileSelection.TRAINING,
  selectColorRandomization = false,
  stackInteraction = StackInteraction.ATTACK_ENGINE,
  scene = "GameBase",
  richPresenceLabel = loc("mm_1_training"),
  winCondition = WinCondition.NONE,
  doCountdown = true,
  disallowAdjacentColors = true
}

local OnePlayerPuzzle = {
  playerCount = 1,
  selectCharacter = true,
  selectLevel = true,
  selectStage = true,
  selectPanels = true,
  selectRanked = false,
  style = Styles.MODERN,
  selectFile = FileSelection.PUZZLE,
  selectColorRandomization = true,
  stackInteraction = StackInteraction.NONE,
  scene = "PuzzleGame",
  matchMode = "puzzle",
  richPresenceLabel = loc("mm_1_puzzle"),
  winCondition = WinCondition.NONE,
  doCountdown = false,
  disallowAdjacentColors = false
}

local OnePlayerChallenge = {
  playerCount = 1,
  selectCharacter = true,
  selectLevel = false,
  selectStage = true,
  selectPanels = true,
  selectRanked = false,
  style = Styles.MODERN,
  selectFile = FileSelection.NONE,
  selectColorRandomization = false,
  stackInteraction = StackInteraction.HEALTH_ENGINE,
  scene = "GameBase",
  richPresenceLabel = loc("mm_1_challenge_mode"),
  winCondition = WinCondition.GAME_OVER,
  doCountdown = true,
  disallowAdjacentColors = true
}

local TwoPlayerVersus = {
  playerCount = 2,
  selectCharacter = true,
  selectLevel = true,
  selectStage = true,
  selectPanels = true,
  -- this has to be rechecked with the online flag
  selectRanked = true,
  style = Styles.MODERN,
  selectFile = FileSelection.NONE,
  selectColorRandomization = false,
  stackInteraction = StackInteraction.VERSUS,
  scene = "OnlineVsGame",
  richPresenceLabel = loc("mm_2_vs"),
  winCondition = WinCondition.GAME_OVER,
  doCountdown = true,
  disallowAdjacentColors = true
}

GameModes.Styles = Styles
GameModes.FileSelection = FileSelection
GameModes.StackInteraction = StackInteraction
GameModes.WinCondition = WinCondition

GameModes.ONE_PLAYER_VS_SELF = OnePlayerVsSelf
GameModes.ONE_PLAYER_TIME_ATTACK = OnePlayerTimeAttack
GameModes.ONE_PLAYER_ENDLESS = OnePlayerEndless
GameModes.ONE_PLAYER_TRAINING = OnePlayerTraining
GameModes.ONE_PLAYER_PUZZLE = OnePlayerPuzzle
GameModes.ONE_PLAYER_CHALLENGE = OnePlayerChallenge
GameModes.TWO_PLAYER_VS = TwoPlayerVersus

return GameModes