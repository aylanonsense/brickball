local simulsim = require 'https://raw.githubusercontent.com/bridgs/simulsim/3eabb5511ad651328db423d7143602f32d7afdd0/simulsim.lua'

local GAME_WIDTH = 279
local GAME_HEIGHT = 145

local game = simulsim.defineGame()

function game.load(self)
  self:spawnEntity({
    id = 'ball-1',
    type = 'ball',
    x = GAME_WIDTH / 2 - 4,
    y = GAME_HEIGHT / 2 - 4,
    width = 8,
    height = 8,
    vx = 0,
    vy = 0,
    freezeFrames = 0,
    isBeingHeld = false
  })
  for r = 1, 10 do
    for team = 1, 2 do
      for c = 1, 5 do
        self:spawnEntity({
          id = 'brick-' .. c .. 'x' .. r .. '-' .. team,
          type = 'brick',
          x = 6 * (c - 1) * (team == 1 and 1 or -1) + (team == 1 and 12 or GAME_WIDTH - 18),
          y = 12 + 12 * (r - 1),
          width = 6,
          height = 12,
          color = c,
          team = team
        })
      end
    end
  end
end

-- Update the game's state every frame by moving each entity
function game.update(self, dt, isRenderable)
  self:forEachEntity(function(entity)
    if entity.type == 'player' then
      local inputs = self:getInputsForClient(entity.clientId) or {}
      local moveX = (inputs.right and 1 or 0) - (inputs.left and 1 or 0)
      local moveY = (inputs.down and 1 or 0) - (inputs.up and 1 or 0)
      local diagonalMult = moveX ~= 0 and moveY ~= 0 and 0.707 or 1.00
      local speed
      if entity.throwPhase == 'charging' then
        speed = 20
      elseif entity.throwPhase == 'aiming' then
        speed = 5
      else
        speed = 60
      end
      entity.vx = 0.7 * entity.vx + 0.3 * (speed * diagonalMult * moveX)
      entity.vy = 0.7 * entity.vy + 0.3 * (speed * 0.9 * diagonalMult * moveY)
      entity.x = entity.x + entity.vx * dt
      entity.y = entity.y + entity.vy * dt
      entity.isMoving = moveX ~= 0 or moveY ~= 0
      if entity.isMoving then
        entity.facingX, entity.facingY = moveX, moveY
        entity.moveFrames = entity.moveFrames + 1
        entity.stillFrames = 0
      else
        entity.stillFrames = entity.stillFrames + 1
        entity.moveFrames = 0
      end
      if entity.team == 1 then
        self:checkForBounds(entity, 2, 3, GAME_WIDTH / 2 - 2, GAME_HEIGHT - 2, -1.0, true)
      else
        self:checkForBounds(entity, GAME_WIDTH / 2, 3, GAME_WIDTH / 2 - 2, GAME_HEIGHT - 2, -1.0, true)
      end
      self:forEachEntity(function(entity2)
        -- Try to pick up balls
        if entity2.type == 'ball' then
          if not entity.heldBall and not entity2.isBeingHeld and entity2.vx == 0 and entity2.vy == 0 and self:entitiesOverlapping(entity, entity2) then
            entity.heldBall = entity2.id
            entity2.isBeingHeld = true
            entity2.clientId = entity.clientId
          end
        -- See if there have been collisions with any bricks
        elseif entity2.type == 'brick' then
          local dir, x, y, vx, vy = self:checkForEntityCollision(entity, entity2, 0.0, true)
        end
      end)
    elseif entity.type == 'ball' then
      if entity.freezeFrames > 0 then
        entity.freezeFrames = entity.freezeFrames - 1
      else
        entity.x = entity.x + entity.vx * dt
        entity.y = entity.y + entity.vy * dt
        self:checkForBounds(entity, 0, 0, GAME_WIDTH, GAME_HEIGHT, -1.0, true)
        local xNew, yNew
        local vxOld, vyOld = entity.vx, entity.vy
        -- See if there have been collisions with any bricks
        self:forEachEntity(function(entity2)
          if entity2.type == 'brick' then
            local dir, x, y, vx, vy = self:checkForEntityCollision(entity, entity2, -1.0, false)
            if dir then
              xNew, yNew = x, y
              entity.vx, entity.vy = vx, vy
              if entity.vx ~= vxOld or entity.vy ~= vyOld then
                entity2.scheduledForDespawn = true
                entity.freezeFrames = 3
              end
            end
          end
        end)
        -- Update the ball's position as a result of colliding with a brick
        if xNew and yNew then
          entity.x, entity.y = xNew, yNew
        end
      end
    end
  end)
  for i = #self.entities, 1, -1 do
    local entity = self.entities[i]
    if entity.scheduledForDespawn then
      -- self:despawnEntity(entity)
    end
  end
end

-- Handle events that the server and client fire, which may end up changing the game state
function game.handleEvent(self, eventType, eventData)
  -- Spawn a new player entity for a client
  if eventType == 'spawn-player' then
    self:spawnEntity({
      id = 'player-' .. eventData.clientId,
      type = 'player',
      clientId = eventData.clientId,
      x = eventData.x - 5,
      y = eventData.y - 4,
      vx = 0,
      vy = 0,
      team = eventData.team,
      facingX = 1,
      facingY = -1,
      width = 10,
      height = 8,
      isMoving = false,
      moveFrames = 0,
      stillFrames = 0,
      heldBall = nil,
      throwPhase = nil
    })
  -- Despawn a player
  elseif eventType == 'despawn-player' then
    self:despawnEntity(self:getEntityWhere({ clientId = eventData.clientId }))
  elseif eventType == 'charge-throw' or eventType == 'aim-throw' or eventType == 'throw' then
    local player = self:getEntityById(eventData.playerId)
    if player and player.heldBall then
      if eventType == 'charge-throw' and not player.throwPhase then
        player.throwPhase = 'charging'
      elseif eventType == 'aim-throw' and player.throwPhase == 'charging' then
        player.throwPhase = 'aiming'
      elseif eventType == 'throw' and player.throwPhase == 'aiming' then
        local ball = self:getEntityById(player.heldBall)
        player.throwPhase = nil
        player.heldBall = nil
        if ball then
          ball.isBeingHeld = false
          ball.x = player.x + player.width / 2 - ball.width / 2
          ball.y = player.y + player.height / 2 - ball.height / 2
          ball.vx = 30
        end
      end
    end
  end
end

function game.checkForBounds(self, entity, x, y, width, height, velocityMult, applyChanges)
  velocityMult = velocityMult or 0.0
  local dir
  local xAdjusted, yAdjusted = entity.x, entity.y
  local vxAdjusted, vyAdjusted = entity.vx, entity.vy
  if entity.x > x + width - entity.width then
    dir = 'right'
    xAdjusted = x + width - entity.width
    if velocityMult < 0 then
      vxAdjusted = velocityMult * (entity.vx > 0 and entity.vx or -entity.vx)
    else
      vxAdjusted = velocityMult * entity.vx
    end
  elseif entity.x < x then
    dir = 'left'
    xAdjusted = x
    if velocityMult < 0 then
      vxAdjusted = velocityMult * (entity.vx < 0 and entity.vx or -entity.vx)
    else
      vxAdjusted = velocityMult * entity.vx
    end
  end
  if entity.y > y + height - entity.height then
    dir = 'down'
    yAdjusted = y + height - entity.height
    if velocityMult < 0 then
      vyAdjusted = velocityMult * (entity.vy > 0 and entity.vy or -entity.vy)
    else
      vyAdjusted = velocityMult * entity.vy
    end
  elseif entity.y < y then
    dir = 'up'
    yAdjusted = y
    if velocityMult < 0 then
      vyAdjusted = velocityMult * (entity.vy < 0 and entity.vy or -entity.vy)
    else
      vyAdjusted = velocityMult * entity.vy
    end
  end
  if applyChanges then
    entity.x, entity.y = xAdjusted, yAdjusted
    entity.vx, entity.vy = vxAdjusted, vyAdjusted
  end
  return dir, xAdjusted, yAdjusted, vxAdjusted, vyAdjusted
end

function game.rectsOverlapping(self, x1, y1, w1, h1, x2, y2, w2, h2)
  return x1 + w1 > x2 and x2 + w2 > x1 and y1 + h1 > y2 and y2 + h2 > y1
end

function game.entitiesOverlapping(self, a, b)
  return self:rectsOverlapping(a.x, a.y, a.width, a.height, b.x, b.y, b.width, b.height)
end

-- Checks to see if a (moving) is colliding with b (stationary) and if so from which direction
function game.checkForEntityCollision(self, a, b, velocityMult, applyChanges, padding)
  velocityMult = velocityMult or 0.0
  local x1, y1, w1, h1, x2, y2, w2, h2 = a.x, a.y, a.width, a.height, b.x, b.y, b.width, b.height
  local p = padding or math.min(math.max(1, math.floor((math.min(w1, h1) - 1) / 2)), 5)
  local dir
  local xAdjusted, yAdjusted = x1, y1
  local vxAdjusted, vyAdjusted = a.vx, a.vy
  if self:rectsOverlapping(x1 + p, y1 + h1 / 2, w1 - 2 * p, h1 / 2, x2, y2, w2, h2) then
    dir = 'down'
    yAdjusted = y2 - h1
    if velocityMult < 0 then
      vyAdjusted = velocityMult * (a.vy > 0 and a.vy or -a.vy)
    else
      vyAdjusted = velocityMult * a.vy
    end
  elseif self:rectsOverlapping(x1, y1 + p, w1 / 2, h1 - 2 * p, x2, y2, w2, h2) then
    dir = 'left'
    xAdjusted = x2 + w2
    if velocityMult < 0 then
      vxAdjusted = velocityMult * (a.vx < 0 and a.vx or -a.vx)
    else
      vxAdjusted = velocityMult * a.vx
    end
  elseif self:rectsOverlapping(x1 + w1 / 2, y1 + p, w1 / 2, h1 - 2 * p, x2, y2, w2, h2) then
    dir = 'right'
    xAdjusted = x2 - w1
    if velocityMult < 0 then
      vxAdjusted = velocityMult * (a.vx > 0 and a.vx or -a.vx)
    else
      vxAdjusted = velocityMult * a.vx
    end
  elseif self:rectsOverlapping(x1 + p, y1, w1 - 2 * p, h1 / 2, x2, y2, w2, h2) then
    dir = 'up'
    yAdjusted = y2 + h2
    if velocityMult < 0 then
      vyAdjusted = velocityMult * (a.vy < 0 and a.vy or -a.vy)
    else
      vyAdjusted = velocityMult * a.vy
    end
  end
  if applyChanges then
    a.x, a.y = xAdjusted, yAdjusted
    a.vx, a.vy = vxAdjusted, vyAdjusted
  end
  return dir, xAdjusted, yAdjusted, vxAdjusted, vyAdjusted
end

-- Create a client-server network for the game to run on
local network, server, client = simulsim.createGameNetwork(game, {
  exposeGameWithoutPrediction = true,
  width = GAME_WIDTH,
  height = GAME_HEIGHT,
  numClients = 4,
  latency = 300
})

function server.load(self)
  self.numTeam1Players = 0
  self.numTeam2Players = 0
end

-- When a client connects to the server, spawn a playable entity for them to control
function server.clientconnected(self, client)
  -- Pick a team for the client to start on
  local team
  if self.numTeam1Players < self.numTeam2Players then
    team = 1
  elseif self.numTeam1Players > self.numTeam2Players then
    team = 2
  else
    team = math.random(1, 2)
  end
  -- Update the player counts
  if team == 1 then
    self.numTeam1Players = self.numTeam1Players + 1
  elseif team == 2 then
    self.numTeam2Players = self.numTeam2Players + 1
  end
  -- Spawn a player for the client
  local x = math.random(80, 120)
  local y = GAME_HEIGHT / 2 + math.random(-55, 55)
  self:fireEvent('spawn-player', {
    clientId = client.clientId,
    x = team == 1 and x or GAME_WIDTH - x,
    y = y,
    team = team
  })
end

-- When a client disconnects from the server, despawn their player entity
function server.clientdisconnected(self, client)
  -- Update the player counts
  local player = self.game:getEntityWhere({ type = 'player', clientId = client.clientId })
  if player then
    if player.team == 1 then
      self.numTeam1Players = self.numTeam1Players - 1
    elseif player.team == 2 then
      self.numTeam2Players = self.numTeam2Players - 1
    end
  end
  -- Despawn the client's player
  self:fireEvent('despawn-player', { clientId = client.clientId })
end

function client.load(self)
  love.graphics.setDefaultFilter('nearest', 'nearest')
  self.spriteSheet = love.graphics.newImage('img/sprite-sheet.png')
end

-- Every frame the client tells the server which buttons it's pressing
function client.update(self, dt)
  if self:isHighlighted() then
    self:setInputs({
      up = love.keyboard.isDown('w') or love.keyboard.isDown('up'),
      left = love.keyboard.isDown('a') or love.keyboard.isDown('left'),
      down = love.keyboard.isDown('s') or love.keyboard.isDown('down'),
      right = love.keyboard.isDown('d') or love.keyboard.isDown('right')
    })
  end
end

-- Draw the game for each client
function client.draw(self)
  -- Draw the court
  love.graphics.setColor(1, 1, 1)
  self:drawSprite(1, 204, 279, 145, 0, 0)
  -- Draw each entity's actual state
  -- love.graphics.setColor(1, 1, 1)
  -- for _, entity in ipairs(self.gameWithoutPrediction.entities) do
  --   love.graphics.rectangle('line', entity.x, entity.y, entity.width, entity.height)
  -- end
  -- Draw each entity's shadow
  love.graphics.setColor(1, 1, 1)
  for _, entity in ipairs(self.game.entities) do
    if entity.type == 'player' then
      self:drawSprite(25, 17, 10, 4, entity.x, entity.y + entity.height - 6)
    elseif entity.type == 'brick' then
      self:drawSprite(1, 17, 8, 14, entity.x - (entity.team == 1 and 2 or 0), entity.y - 1)
    elseif entity.type == 'ball' then
      if not entity.isBeingHeld then
        self:drawSprite(25, 22, 10, 4, entity.x - 1, entity.y + entity.height - 3)
      end
    end
  end
  -- Draw an indicator under your player character
  local player = self.game:getEntityWhere({ type = 'player', clientId = self.clientId })
  if player then
    self:drawSprite(player.team == 1 and 53 or 36, 17, 16, 8, player.x - 3, player.y)
  end
  -- Draw each entity
  love.graphics.setColor(1, 1, 1)
  for _, entity in ipairs(self.game.entities) do
    if entity.type == 'player' then
      local sx = 1
      local sy = (entity.team == 2 and 33 or 118)
      local x = entity.x
      local y = entity.y
      local flipHorizontal = entity.facingX < 0
      local animSprite
      if entity.isMoving then
        animSprite = 2 + math.floor((entity.moveFrames % (8 * 5)) / 5)
      else
        animSprite = 1
      end
      local dirSprite
      if entity.facingY < 0 then
        dirSprite = entity.facingX == 0 and 1 or 2
      elseif entity.facingY > 0 then
        dirSprite = entity.facingX == 0 and 5 or 4
      else
        dirSprite = 3
      end
      if entity.throwPhase == 'charging' then
        animSprite = entity.isMoving and entity.moveFrames % 40 > 20 and 20 or 19
        dirSprite = 3
        x, y = x  + (player.team == 1 and -3 or 3), y - 1
        flipHorizontal = entity.team == 2
      elseif entity.throwPhase == 'aiming' then
        animSprite = entity.isMoving and entity.moveFrames % 70 > 35 and 22 or 21
        dirSprite = 3
        x, y = x + (player.team == 1 and -3 or 3), y - 1
        flipHorizontal = entity.team == 2
      elseif entity.heldBall then
        animSprite = animSprite + 9
      end
      self:drawSprite(sx + 16 * (animSprite - 1), sy + 17 * (dirSprite - 1), 15, 16, x - (flipHorizontal and 4 or 1), y - 9, flipHorizontal)
    elseif entity.type == 'brick' then
      local colorSprite = entity.color
      self:drawSprite(1 + 7 * (colorSprite - 1), 1, 6, 15, entity.x, entity.y - 3, entity.team == 2)
    elseif entity.type == 'ball' then
      if not entity.isBeingHeld then
        self:drawSprite(70, 17, 8, 8, entity.x, entity.y - 1)
      end
    else
      love.graphics.rectangle('line', entity.x, entity.y, entity.width, entity.height)
    end
  end
end

function client.keypressed(self, key)
  if key == 'space' then
    local player = self.game:getEntityWhere({ type = 'player', clientId = self.clientId })
    if player and player.heldBall then
      if not player.throwPhase then
        self:fireEvent('charge-throw', { playerId = player.id })
      elseif player.throwPhase == 'charging' then
        self:fireEvent('aim-throw', { playerId = player.id })
      elseif player.throwPhase == 'aiming' then
        self:fireEvent('throw', { playerId = player.id })
      end
    end
  end
end

-- Draw a sprite from a sprite sheet to the screen
function client.drawSprite(self, sx, sy, sw, sh, x, y, flipHorizontal, flipVertical, rotation)
  if self.spriteSheet then
    local width, height = self.spriteSheet:getDimensions()
    return love.graphics.draw(self.spriteSheet,
      love.graphics.newQuad(sx, sy, sw, sh, width, height),
      x + sw / 2, y + sh / 2,
      rotation or 0,
      flipHorizontal and -1 or 1, flipVertical and -1 or 1,
      sw / 2, sh / 2)
  end
end
