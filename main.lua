local simulsim = require 'https://raw.githubusercontent.com/bridgs/simulsim/3eabb5511ad651328db423d7143602f32d7afdd0/simulsim.lua'

local GAME_WIDTH = 279
local GAME_HEIGHT = 145

local game = simulsim.defineGame()

function game.load(self)
  self:spawnEntity({
    type = 'ball',
    x = GAME_WIDTH / 2 - 10,
    y = GAME_HEIGHT / 2 - 10,
    width = 8,
    height = 8,
    vx = 100,
    vy = -20
  })
  for r = 1, 10 do
    for team = 1, 2 do
      for c = 1, 6 do
        self:spawnEntity({
          type = 'brick',
          x = 6 * (c - 1) + (team == 1 and 12 or GAME_WIDTH - 6 * 6 - 12),
          y = 12 + 12 * (r - 1),
          width = 6,
          height = 12,
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
      local speedMult = moveX ~= 0 and moveY ~= 0 and 0.707 or 1.00
      entity.x = entity.x + 60 * speedMult * moveX * dt
      entity.y = entity.y + 55 * speedMult * moveY * dt
      self:checkForBounds(entity, 0, 0, GAME_WIDTH, GAME_HEIGHT, -1.0, true)
      -- See if there have been collisions with any bricks
      self:forEachEntity(function(entity2)
        if entity2.type == 'brick' then
          local dir, x, y, vx, vy = self:checkForEntityCollision(entity, entity2, 0.0, true)
        end
      end)
    elseif entity.type == 'ball' then
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
            end
          end
        end
      end)
      -- Update the ball's position as a result of colliding with a brick
      if xNew and yNew then
        entity.x, entity.y = xNew, yNew
      end
    end
  end)
  for i = #self.entities, 1, -1 do
    local entity = self.entities[i]
    if entity.scheduledForDespawn then
      self:despawnEntity(entity)
    end
  end
end

-- Handle events that the server and client fire, which may end up changing the game state
function game.handleEvent(self, eventType, eventData)
  -- Spawn a new player entity for a client
  if eventType == 'spawn-player' then
    self:spawnEntity({
      type = 'player',
      clientId = eventData.clientId,
      x = eventData.x - 5,
      y = eventData.y - 4,
      vx = 0,
      vy = 0,
      width = 10,
      height = 8
    })
  -- Despawn a player
  elseif eventType == 'despawn-player' then
    self:despawnEntity(self:getEntityWhere({ clientId = eventData.clientId }))
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
  latency = 300
})

-- When a client connects to the server, spawn a playable entity for them to control
function server.clientconnected(self, client)
  self:fireEvent('spawn-player', {
    clientId = client.clientId,
    x = GAME_WIDTH / 2,
    y = GAME_HEIGHT / 2
  })
end

-- When a client disconnects from the server, despawn their player entity
function server.clientdisconnected(self, client)
  self:fireEvent('despawn-player', { clientId = client.clientId })
end

function client.load(self)
  love.graphics.setDefaultFilter('nearest', 'nearest')
  self.spriteSheet = love.graphics.newImage('img/sprite-sheet.png')
end

-- Every frame the client tells the server which buttons it's pressing
function client.update(self, dt)
  self:setInputs({
    up = love.keyboard.isDown('w') or love.keyboard.isDown('up'),
    left = love.keyboard.isDown('a') or love.keyboard.isDown('left'),
    down = love.keyboard.isDown('s') or love.keyboard.isDown('down'),
    right = love.keyboard.isDown('d') or love.keyboard.isDown('right')
  })
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
      self:drawSprite(25, 22, 10, 4, entity.x - 1, entity.y + entity.height - 3)
    end
  end
  -- Draw each entity
  love.graphics.setColor(1, 1, 1)
  for _, entity in ipairs(self.game.entities) do
    if entity.type == 'player' then
      self:drawSprite(1, 33, 15, 16, entity.x - 1, entity.y - 9)
    elseif entity.type == 'brick' then
      self:drawSprite(29, 1, 6, 15, entity.x, entity.y - 3, entity.team == 2)
    elseif entity.type == 'ball' then
      self:drawSprite(68, 17, 8, 8, entity.x, entity.y - 1)
    else
      love.graphics.rectangle('line', entity.x, entity.y, entity.width, entity.height)
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
