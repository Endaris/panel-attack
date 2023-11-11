local Request = require("network.Request")

local ClientRequests = {}

-- players are challenged by their current name on the server
function ClientRequests.challengePlayer(name)
  local playerChallengeRequest =
  {
    game_request =
    {
      sender = config.name,
      receiver = name
    }
  }

  Request(playerChallengeRequest):send()
end

function ClientRequests.requestSpectate(roomNumber)
  assert(GAME.pendingNetRequests["requestSpectate"] == nil, "don't request another spectate while waiting to join a room")

  local spectateRequest =
  {
    spectate_request =
    {
      sender = config.name,
      roomNumber = roomNumber
    }
  }

  local request = Request(spectateRequest, "spectate_request_granted")
  GAME.pendingNetRequests["requestSpectate"] = request
  request:send()
end

function ClientRequests.requestLeaderboard()
  assert(GAME.pendingNetRequests["requestLeaderboard"] == nil, "don't request a leaderboard while one is on its way")
  local leaderboardRequest =
  {
    leaderboard_request = true
  }

  local request = Request(leaderboardRequest, "leaderboard_report")
  GAME.pendingNetRequests["requestLeaderboard"] = request
  request:send()
end

function ClientRequests.requestLogin()
  assert(GAME.pendingNetRequests["login"] == nil, "don't request another login while one is being processed")
  local loginMessage =
  {
    login_request = true,
    user_id = my_user_id
  }

  local request = Request(loginMessage, "login_successful", "login_denied")
  GAME.pendingNetRequests["login"] = request
  request:send()
  return request
end

function ClientRequests.logout()
  local logoutMessage =
  {
    logout = true
  }

  Request(logoutMessage):send()
end



return ClientRequests