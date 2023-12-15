local consts = require("consts")
local logger = require("logger")
local input = require("inputManager")
local NetworkProtocol = require("network.NetworkProtocol")
local TouchDataEncoding = require("engine.TouchDataEncoding")
local ClientRequests = require("network.ClientProtocol")
require("TimeQueue")
local class = require("class")

local TcpClient = class(function(tcpClient, server, ip)
  tcpClient.socket = socket.tcp()
end)

-- setup the network connection on the given IP and port
function TcpClient:connectToServer(ip, network_port)
  self.socket:settimeout(7)
  local result, err = self.socket:connect(ip, network_port or 49569)
  if not result then
    return err == "already connected"
  end
  self.socket:setoption("tcp-nodelay", true)
  self.socket:settimeout(0)
  return true
end

-- Expected length for each message type
local leftovers = "" -- Everything currently in the data queue

function TcpClient:network_connected()
  return self.socket:getpeername() ~= nil
end

-- Grabs data from the socket
-- returns false if something went wrong
function TcpClient:flush_socket()
  if not self.socket then
    return
  end
  local junk, err, data = self.socket:receive("*a")
  -- lol, if it returned successfully then that's bad!
  if not err then
    -- Return false, so we know things went badly
    return false
  end
  leftovers = leftovers .. data
  -- When done, return true, so we know things went okay
  return true
end

function TcpClient:resetNetwork()
  logged_in = 0
  connection_up_time = 0
  GAME.connected_server_ip = ""
  GAME.connected_server_port = nil
  current_server_supports_ranking = false
  match_type = ""
  if self.socket then
    self.socket:close()
  end
  self.socket = nil
end

function TcpClient:processDataToSend(stringData)
  if self.socket then
    local fullMessageSent, error, partialBytesSent = self.socket:send(stringData)
    if fullMessageSent then
      --logger.trace("json bytes sent in one go: " .. tostring(fullMessageSent))
    else
      logger.error("Error sending network message: " .. (error or "") .. " only sent " .. (partialBytesSent or "0") .. "bytes")
    end
  end
end

function TcpClient:processDataToReceive(data)
  self:queue_message(data[1], data[2])
end

function updateNetwork(dt)
  GAME.sendNetworkQueue:update(dt, processDataToSend)
  GAME.receiveNetworkQueue:update(dt, processDataToReceive)
end

local sendMinLag = 0
local sendMaxLag = 0
local receiveMinLag = 3
local receiveMaxLag = receiveMinLag

-- send the given message through
function TcpClient:net_send(stringData)
  if not self.socket then
    return false
  end
  if not STONER_MODE then
    self:processDataToSend(stringData)
  else
    local lagSeconds = (math.random() * (sendMaxLag - sendMinLag)) + sendMinLag
    GAME.sendNetworkQueue:push(stringData, lagSeconds)
  end
  return true
end

-- Cleans up "stonermode" used for testing laggy sends
function undo_stonermode()
  GAME.sendNetworkQueue:clearAndProcess(processDataToSend)
  GAME.receiveNetworkQueue:clearAndProcess(processDataToReceive)
  STONER_MODE = false
end


-- list of spectators
function spectator_list_string(list)
  local str = ""
  for k, v in ipairs(list) do
    str = str .. v
    if k < #list then
      str = str .. "\n"
    end
  end
  if str ~= "" then
    str = loc("pl_spectators") .. "\n" .. str
  end
  return str
end

-- Adds the message to the network queue or processes it immediately in a couple cases
function TcpClient:queue_message(type, data)
  if type == NetworkProtocol.serverMessageTypes.opponentInput.prefix or type == NetworkProtocol.serverMessageTypes.secondOpponentInput.prefix then
    local dataMessage = {}
    dataMessage[type] = data
    logger.debug("Queuing: " .. type .. " with data:" .. data)
    GAME.server_queue:push(dataMessage)
  elseif type == NetworkProtocol.serverMessageTypes.versionCorrect.prefix then
    -- make responses to client H messages processable via GAME.server_queue
    GAME.server_queue:push({versionCompatible = true})
  elseif type == NetworkProtocol.serverMessageTypes.versionWrong.prefix then
    -- make responses to client H messages processable via GAME.server_queue
    GAME.server_queue:push({versionCompatible = false})
  elseif type == NetworkProtocol.serverMessageTypes.ping.prefix then
    self:net_send(NetworkProtocol.clientMessageTypes.acknowledgedPing.prefix)
    connection_up_time = connection_up_time + 1 --connection_up_time counts "E" messages, not seconds
  elseif type == NetworkProtocol.serverMessageTypes.jsonMessage.prefix then
    local current_message = json.decode(data)
    if not current_message then
      error(loc("nt_msg_err", (data or "nil")))
    end
    logger.debug("Queuing JSON: " .. dump(current_message))
    GAME.server_queue:push(current_message)
  end
end

-- Drops all "game data" messages prior to the next server "J" message.
function drop_old_data_messages()
  while true do
    local message = GAME.server_queue:top()
    if not message then
      break
    end

    if not message[NetworkProtocol.serverMessageTypes.opponentInput.prefix] and not message[NetworkProtocol.serverMessageTypes.secondOpponentInput.prefix] then
      break -- Found a non user input message. Stop. Future data is for next game
    else
      GAME.server_queue:pop() -- old data, drop it
    end
  end
end

-- Process all game data messages in the queue
function process_all_data_messages()
  local messages = GAME.server_queue:pop_all_with(NetworkProtocol.serverMessageTypes.opponentInput.prefix, NetworkProtocol.serverMessageTypes.secondOpponentInput.prefix)
  for _, msg in ipairs(messages) do
    for type, data in pairs(msg) do
      logger.debug("Processing: " .. type .. " with data:" .. data)
      process_data_message(type, data)
    end
  end
end

-- Handler for the various "game data" message types
function process_data_message(type, data)
  if type == NetworkProtocol.serverMessageTypes.secondOpponentInput.prefix then
    GAME.battleRoom.match.P1:receiveConfirmedInput(data)
  elseif type == NetworkProtocol.serverMessageTypes.opponentInput.prefix then
    GAME.battleRoom.match.P2:receiveConfirmedInput(data)
  end
end

function send_error_report(errorData)
  TCP_sock = socket.tcp()
  TCP_sock:settimeout(7)
  if not TCP_sock:connect(consts.SERVER_LOCATION, 59569) then
    return false
  end
  TCP_sock:settimeout(0)
  ClientRequests.sendErrorReport(errorData)
  TcpClient.resetNetwork(TCP_sock)
  return true
end

-- Processes messages that came in from the server
-- Returns false if the connection is broken.
function TcpClient:do_messages()
  if not self:flush_socket() then
    -- Something went wrong while receiving data.
    -- Bail out and return.
    return false
  end
  while true do
    local type, message, remaining = NetworkProtocol.getMessageFromString(leftovers, true)
    if type then
      if not STONER_MODE then
        self:queue_message(type, message)
      else
        local lagSeconds = (math.random() * (receiveMaxLag - receiveMinLag)) + receiveMinLag
        GAME.receiveNetworkQueue:push({type, message}, lagSeconds)
      end
      leftovers = remaining
    else
      break
    end
  end
  -- Return true when finished successfully.
  return true
end

function Stack.handle_input_taunt(self)

  if input.isDown["TauntUp"] and self:can_taunt() and #characters[self.character].sounds.taunt_up > 0 then
    self.taunt_up = math.random(#characters[self.character].sounds.taunt_up)
    if TCP_sock then
      ClientRequests.sendTaunt("up", self.taunt_up)
    end
  elseif input.isDown["TauntDown"] and self:can_taunt() and #characters[self.character].sounds.taunt_down > 0 then
    self.taunt_down = math.random(#characters[self.character].sounds.taunt_down)
    if TCP_sock then
      ClientRequests.sendTaunt("down", self.taunt_down)
    end
  end
end

local touchIdleInput = TouchDataEncoding.touchDataToLatinString(false, 0, 0, 6)
function Stack.idleInput(self) 
  return (self.inputMethod == "touch" and touchIdleInput) or base64encode[1]
end

function Stack.send_controls(self)
  if self.is_local and TCP_sock and #self.confirmedInput > 0 and self.opponentStack and #self.opponentStack.confirmedInput == 0 then
    -- Send 1 frame at clock time 0 then wait till we get our first input from the other player.
    -- This will cause a player that got the start message earlierer than the other player to wait for the other player just once.
    -- print("self.confirmedInput="..(self.confirmedInput or "nil"))
    -- print("self.input_buffer="..(self.input_buffer or "nil"))
    -- print("send_controls returned immediately")
    return
  end

  local playerNumber = self.which
  local to_send
  if self.inputMethod == "controller" then
    to_send = base64encode[
      ((input.isDown["Raise1"] or input.isDown["Raise2"] or input.isPressed["Raise1"] or input.isPressed["Raise2"]) and 32 or 0) + 
      ((input.isDown["Swap1"] or input.isDown["Swap2"]) and 16 or 0) + 
      ((input.isDown["Up"] or input.isPressed["Up"]) and 8 or 0) + 
      ((input.isDown["Down"] or input.isPressed["Down"]) and 4 or 0) + 
      ((input.isDown["Left"] or input.isPressed["Left"]) and 2 or 0) + 
      ((input.isDown["Right"] or input.isPressed["Right"]) and 1 or 0) + 1
    ]
  elseif self.inputMethod == "touch" then
    to_send = self.touchInputController:encodedCharacterForCurrentTouchInput()
  end
  if TCP_sock then
    local message = NetworkProtocol.markedMessageForTypeAndBody(NetworkProtocol.clientMessageTypes.playerInput.prefix, to_send)
    net_send(message)
  end

  self:handle_input_taunt()

  self:receiveConfirmedInput(to_send)
end

return TcpClient