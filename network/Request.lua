local class = require("class")

-- how many tries (read: frames) it takes for a request to give up waiting for a response
local REQUEST_TIMEOUT = 10 * 60

local function createRequestCoroutine(messageContent, ...)
  local a, b = ...
  local cr = coroutine.create(
    function ()
      json_send(messageContent)

      if a then
        local response
        local frameCount = 0

        while not response and frameCount < REQUEST_TIMEOUT do
          coroutine.yield()
          response = server_queue:pop_next_with(a, b)
          frameCount = frameCount + 1
        end

        return response
      end
    end
  )

  return cr
end

-- A  simple coroutine wrapper for requests to the server that allows to get the response from the request itself
local Request = class(function(self, messageContent, ...)
  self.coFunc = createRequestCoroutine(messageContent, ...)
  self.awaitingResponse = false
  self.done = false
end)

-- resumes the coroutine to see if a response arrived
-- if a response arrived, returns true and the response, if the timeout was reached, the response is nil
-- if no response arrived, returns false
function Request:tryGetResponse()
  assert(self.awaitingResponse and not self.done, "you're not supposed to try and get a response from this")
  local success, returnValues = coroutine.resume(self.coFunc)
  if not success then
    GAME.crashTrace = debug.traceback(self.coFunc)
    error(returnValues)
  else
    if coroutine.status(self.coFunc) ~= "dead" then
      return false
    else
      self.done = true
      self.awaitingResponse = false
      return true, returnValues
    end
  end
end

-- sends the request, updates awaitingResponse status field
function Request:send()
  local success, returnValues = coroutine.resume(self.coFunc)
  if not success then
    GAME.crashTrace = debug.traceback(self.coFunc)
    error(returnValues)
  elseif coroutine.status(self.coFunc) ~="dead" then
    self.awaitingResponse = true
  else
    self.awaitingResponse = false
    self.done = true
  end
end

return Request