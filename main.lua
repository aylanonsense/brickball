local simulsim = require 'https://raw.githubusercontent.com/bridgs/simulsim/3eabb5511ad651328db423d7143602f32d7afdd0/simulsim.lua'

local GAME_WIDTH = 300
local GAME_HEIGHT = 400

-- Define a new game
local game = simulsim.defineGame()

-- When the game is first loaded, set the background color
function game.load(self)
  self:spawnEntity({
    type = 'ball',
    x = GAME_WIDTH / 2 - 10,
    y = GAME_HEIGHT / 2 - 10,
    width = 20,
    height = 20,
    vx = 50,
    vy = -105
  })
  for team = 1, 2 do
    for c = 1, 10 do
      for r = 1, 4 do
        self:spawnEntity({
          type = 'brick',
          x = 5 + 25 * c,
          y = 20 + 15 * r + (200 * (team - 1)),
          width = 20,
          height = 10
        })
      end
    end
  end
end

-- Update the game's state every frame by moving each entity
function game.update(self, dt, isRenderable)
  for _, entity in ipairs(self.entities) do
    if entity.type == 'player' then
      local inputs = self:getInputsForClient(entity.clientId) or {}
      local moveX = (inputs.right and 1 or 0) - (inputs.left and 1 or 0)
      local moveY = (inputs.down and 1 or 0) - (inputs.up and 1 or 0)
      entity.x = math.min(math.max(0, entity.x + 200 * moveX * dt), 380)
      entity.y = math.min(math.max(0, entity.y + 200 * moveY * dt), 380)
    elseif entity.type == 'ball' then
      entity.x = entity.x + entity.vx * dt
      entity.y = entity.y + entity.vy * dt
      self:keepEntityInBounds(entity, true)
      local xNew, yNew
      -- See if there have been collisions with any bricks
      for _, entity2 in ipairs(self.entities) do
        if entity2.type == 'brick' then
          local dir, x, y, vx, vy = self:checkForEntityCollision(entity, entity2, 4, -1.0, false)
          if dir then
            entity.vx, entity.vy = vx, vy
            xNew, yNew = x, y
            entity2.scheduledForDespawn = true
          end
        end
      end
      -- Update the ball's position as a result of colliding with a brick
      if xNew and yNew then
        entity.x, entity.y = xNew, yNew
      end
    end
  end
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
      x = eventData.x - 10,
      y = eventData.y - 10,
      width = 20,
      height = 20
    })
  -- Despawn a player
  elseif eventType == 'despawn-player' then
    self:despawnEntity(self:getEntityWhere({ clientId = eventData.clientId }))
  end
end

function game.keepEntityInBounds(self, entity, reverseVelocity)
  if entity.x > GAME_WIDTH - entity.width then
    entity.x = GAME_WIDTH - entity.width
    if reverseVelocity and entity.vx > 0 then
      entity.vx = -entity.vx
    end
    return 'right'
  elseif entity.x < 0 then
    entity.x = 0
    if reverseVelocity and entity.vx < 0 then
      entity.vx = -entity.vx
    end
    return 'left'
  end
  if entity.y > GAME_HEIGHT - entity.height then
    entity.y = GAME_HEIGHT - entity.height
    if reverseVelocity and entity.vy > 0 then
      entity.vy = -entity.vy
    end
    return 'down'
  elseif entity.y < 0 then
    entity.y = 0
    if reverseVelocity and entity.vy < 0 then
      entity.vy = -entity.vy
    end
    return 'up'
  end
end

function game.rectsOverlapping(self, x1, y1, w1, h1, x2, y2, w2, h2)
  return x1 + w1 > x2 and x2 + w2 > x1 and y1 + h1 > y2 and y2 + h2 > y1
end

function game.entitiesOverlapping(self, a, b)
  return self:rectsOverlapping(a.x, a.y, a.width, a.height, b.x, b.y, b.width, b.height)
end

-- Checks to see if a (moving) is colliding with b (stationary) and if so from which direction
function game.checkForEntityCollision(self, a, b, padding, velocityMult, applyChanges)
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
    x = 100 + 200 * math.random(),
    y = 100 + 200 * math.random()
  })
end

-- When a client disconnects from the server, despawn their player entity
function server.clientdisconnected(self, client)
  self:fireEvent('despawn-player', { clientId = client.clientId })
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
  -- Clear the screen
  love.graphics.setColor(0.1, 0.1, 0.1)
  love.graphics.rectangle('fill', 0, 0, GAME_WIDTH, GAME_HEIGHT)
  -- Draw each entity's actual state
  love.graphics.setColor(1, 1, 1)
  for _, entity in ipairs(self.gameWithoutPrediction.entities) do
    love.graphics.rectangle('line', entity.x, entity.y, entity.width, entity.height)
  end
  -- Draw each entity
  love.graphics.setColor(1, 1, 1)
  for _, entity in ipairs(self.game.entities) do
    love.graphics.rectangle('fill', entity.x, entity.y, entity.width, entity.height)
  end
end
