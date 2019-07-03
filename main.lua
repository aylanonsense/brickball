local simulsim = require 'https://raw.githubusercontent.com/bridgs/simulsim/ccfcf1942fdb2b16acc87ed35815005d869cac29/simulsim.lua'

local GAME_WIDTH = 279
local GAME_HEIGHT = 145
local TIME_PER_ROUND = 136.00
local TIME_BEFORE_ROUND_START = 16.00
local WINNER_CELEBRATION_TIME = 7.00
local MAX_BALL_HOLD_TIME = 12.00
local LEVEL_DATA_LOOKUP = {
  purpleBrick = { 119, 43, 228 },
  pinkBrick = { 194, 31, 101 },
  orangeBrick = { 211, 99, 33 },
  blueBrick = { 35, 133, 183 },
  greenBrick = { 83, 171, 48 },
  goldBrick = { 204, 118, 11 },
  metalBrick = { 111, 109, 93 },
  glassBrick = { 253, 250, 234 }
}

local game = simulsim.defineGame()

function game.load(self)
  self.data.numTeam1Players = 0
  self.data.numTeam2Players = 0
  self.data.team1Score = 0
  self.data.team2Score = 0
  self:startUp()
end

-- Update the game's state every frame by moving each entity
function game.update(self, dt, isRenderable)
  self.data.phaseTimer = self.data.phaseTimer + dt
  self.data.phaseFrame = self.data.phaseFrame + 1
  if self.data.phase == 'gameplay' and self.data.phaseTimer > TIME_PER_ROUND then
    self:endGameplay()
  end
  if self.data.phase == 'gameplay' and self.data.phaseTimer > 5.00 and self.data.phaseFrame % 30 == 0 then
    local numTeam1Bricks = #self:getEntitiesWhere({ type = 'brick', team = 1 })
    local numTeam2Bricks = #self:getEntitiesWhere({ type = 'brick', team = 2 })
    if numTeam1Bricks <= 0 or numTeam2Bricks <= 0 then
      self:endGameplay()
    end
  end
  if self.data.phase == 'scoring' and self.data.phaseFrame > 120 and self.data.phaseFrame % 5 == 0 then
    self:trigger('score-step')
  end
  if self.data.phase == 'declaring-winner' and self.data.phaseTimer > WINNER_CELEBRATION_TIME then
    self:startUp()
  end
  self:forEachEntity(function(entity)
    if entity.type == 'player' then
      if entity.freezeFrames > 0 then
        entity.freezeFrames = math.max(0, entity.freezeFrames - 1)
      else
        entity.invincibilityFrames = math.max(0, entity.invincibilityFrames - 1)
        local inputs = self:getInputsForClient(entity.clientId) or {}
        local moveX = (inputs.right and 1 or 0) - (inputs.left and 1 or 0)
        local moveY = (inputs.down and 1 or 0) - (inputs.up and 1 or 0)
        local diagonalMult = moveX ~= 0 and moveY ~= 0 and 0.707 or 1.00
        if entity.anim == 'catching' or entity.anim == 'throwing' or entity.anim == 'standing-up' or entity.anim == 'getting-hit' then
          entity.animFrames = entity.animFrames - 1
          if entity.animFrames <= 0 then
            if entity.anim == 'getting-hit' then
              entity.anim = 'standing-up'
              entity.animFrames = 95
            else
              entity.anim = nil
            end
          end
        elseif entity.anim then
          entity.animFrames = entity.animFrames + 1
          if entity.anim == 'charging' then
            entity.charge = ((6 * entity.animFrames + 100) % 400) - 100
            if entity.charge > 100 then
              entity.charge = 200 - entity.charge
            end
          elseif entity.anim == 'aiming' then
            local wobbleRange = 15 - 7 * math.abs(entity.charge) / 100
            entity.baseAim = math.min(math.max(-100 + wobbleRange, entity.baseAim + 200 * moveY * dt), 100 - wobbleRange)
            entity.aim = entity.baseAim + wobbleRange * math.sin(entity.animFrames / (5 + 15 * math.abs(entity.charge / 100)))
          end
        end
        -- Calculate speed based on the player's state
        local speed
        if entity.anim == 'charging' then
          speed = 20
        elseif entity.anim == 'aiming' or entity.anim == 'throwing' or entity.anim == 'catching' or entity.anim == 'getting-hit' or entity.anim == 'standing-up' then
          speed = 0
        else
          speed = 60
        end
        if entity.anim ~= 'getting-hit' then
          entity.vx = 0.7 * entity.vx + 0.3 * (speed * diagonalMult * moveX)
          entity.vy = 0.7 * entity.vy + 0.3 * (speed * 0.9 * diagonalMult * moveY)
        end
        entity.x = entity.x + entity.vx * dt
        entity.y = entity.y + entity.vy * dt
        entity.isMoving = speed ~= 0 and (moveX ~= 0 or moveY ~= 0)
        if entity.isMoving then
          entity.facingX, entity.facingY = moveX, moveY
          entity.moveFrames = entity.moveFrames + 1
          entity.stillFrames = 0
        else
          entity.stillFrames = entity.stillFrames + 1
          entity.moveFrames = 0
        end
        if entity.heldBall then
          local ball = self:getEntityById(entity.heldBall)
          if ball and ball.timeSinceCatch > MAX_BALL_HOLD_TIME then
            self:trigger('player-held-ball-too-long', {
              playerId = entity.id,
              x = entity.x,
              y = entity.y,
              team = entity.team,
              numTimesKnockedBack = entity.numTimesKnockedBack
            })
          end
        end
        if entity.team == 1 then
          self:checkForBounds(entity, 2, 3, GAME_WIDTH / 2 - 2, GAME_HEIGHT - 3, 0.0, true)
        else
          self:checkForBounds(entity, GAME_WIDTH / 2, 3, GAME_WIDTH / 2 - 2, GAME_HEIGHT - 3, 0.0, true)
        end
        self:forEachEntity(function(entity2)
          if entity2.type == 'ball' and not entity2.isBeingHeld then
            if not entity.heldBall and entity.anim == 'catching' and entity.animFrames > 25 and self:entitiesOverlapping(entity, entity2) then
              self:trigger('player-caught-ball', {
                playerId = entity.id,
                ballId = entity2.id,
                numCatches = entity.numCatches
              })
            elseif not entity.heldBall and not entity.anim and entity2.vx == 0 and entity2.vy == 0 and self:entitiesOverlapping(entity, entity2) then
              entity.heldBall = entity2.id
              entity2.isBeingHeld = true
              entity2.timeSinceCatch = 0.00
            elseif entity.invincibilityFrames <= 0 and (entity2.framesSinceThrow > 15 or entity2.thrower ~= entity.id) and (entity2.vx ~= 0 or entity2.vy ~= 0) and self:entitiesOverlapping(entity, entity2) then
              self:trigger('player-got-hit-by-ball', {
                playerId = entity.id,
                x = entity.x,
                y = entity.y,
                vx = 1.2 * entity2.vx - entity.vx,
                vy = 1.2 * entity2.vy - entity.vy,
                numTimesKnockedBack = entity.numTimesKnockedBack
              })
            end
          -- See if there have been collisions with any bricks
          elseif entity2.type == 'brick' and not entity2.isDespawning then
            local dir, x, y, vx, vy = self:checkForEntityCollision(entity, entity2, 0.0, true)
          elseif entity2.type == 'level-selector' and entity.team == entity2.team and self:entitiesOverlapping(entity, entity2) then
            entity.levelVote = entity2.level
          end
        end)
      end
    elseif entity.type == 'ball' then
      if entity.freezeFrames > 0 then
        entity.freezeFrames = entity.freezeFrames - 1
      else
        entity.timeSinceCatch = entity.timeSinceCatch + dt
        if not entity.isBeingHeld then
          entity.framesSinceThrow = entity.framesSinceThrow + 1
          entity.framesSinceBallCollision = entity.framesSinceBallCollision + 1
          entity.x = entity.x + entity.vx * dt
          entity.y = entity.y + entity.vy * dt
          self:checkForBounds(entity, 0, 0, GAME_WIDTH, GAME_HEIGHT, -1.0, true)
          local xNew, yNew
          local vxOld, vyOld = entity.vx, entity.vy
          self:forEachEntity(function(entity2)
            if entity2.type == 'ball' and entity.id ~= entity2.id and not entity2.isBeingHeld and entity.framesSinceBallCollision > 40 and entity2.framesSinceBallCollision > 40 and ((entity.vx > 0) ~= (entity2.vx > 0) or (entity.vy > 0) ~= (entity2.vy > 0)) and self:entitiesOverlapping(entity, entity2) then
              entity.vx, entity.vy, entity2.vx, entity2.vy = entity2.vx, entity2.vy, entity.vx, entity.vy
              if entity.vx == 0 then
                entity.vx = (entity2.vx > 0 and -40 or 40)
              elseif entity2.vx == 0 then
                entity2.vx = (entity.vx > 0 and -40 or 40)
              end
              entity.freezeFrames, entity2.freezeFrames = 5, 5
              entity.framesSinceBallCollision, entity2.framesSinceBallCollision = 0, 0
            elseif entity2.type == 'brick' and not entity2.isDespawning then
              local dir, x, y, vx, vy = self:checkForEntityCollision(entity, entity2, -1.0, false)
              if dir then
                xNew, yNew = x, y
                if entity2.material ~= 'glass' then
                  entity.vx, entity.vy = vx, vy
                end
                if entity2.material == 'glass' or (entity.vx ~= vxOld or entity.vy ~= vyOld) then
                  entity.freezeFrames = (entity2.material == 'glass' and 1 or 3)
                  if entity2.material == 'metal' then
                    entity2.material = 'broken-metal'
                  else
                    entity2.framesToDeath = 7
                    entity2.isDespawning = true
                  end
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
    end
  end)
  for i = #self.entities, 1, -1 do
    local entity = self.entities[i]
    if entity.framesToDeath then
      entity.framesToDeath = entity.framesToDeath - 1
      if entity.framesToDeath <= 0 then
        entity.scheduledForDespawn = true
      end
    end
    if entity.scheduledForDespawn then
      if entity.type == 'brick' then
        self:trigger('brick-despawned', { brick = entity })
      end
      self:despawnEntity(entity)
    end
  end
end

function game.handleEvent(self, eventType, eventData)
  if eventType == 'join-game' then
    local player = self:getEntityById('player-' .. eventData.clientId)
    if not player then
      local team
      if self.data.numTeam1Players <= self.data.numTeam2Players then
        team = 1
      else
        team = 2
      end
      -- Update the player counts
      if team == 1 then
        self.data.numTeam1Players = self.data.numTeam1Players + 1
      elseif team == 2 then
        self.data.numTeam2Players = self.data.numTeam2Players + 1
      end
      -- Spawn a player
      self:spawnEntity({
        id = 'player-' .. eventData.clientId,
        type = 'player',
        clientId = eventData.clientId,
        x = GAME_WIDTH / 2 + (team == 2 and 40 or -40) - 5,
        y = GAME_HEIGHT / 2 - 4,
        vx = 0,
        vy = 0,
        team = team,
        facingX = 1,
        facingY = -1,
        width = 10,
        height = 8,
        isMoving = false,
        moveFrames = 0,
        stillFrames = 0,
        heldBall = nil,
        anim = nil,
        animFrames = 0,
        charge = nil,
        aim = nil,
        baseAim = nil,
        invincibilityFrames = 0,
        numTimesKnockedBack = 0,
        freezeFrames = 0,
        numCatches = 0,
        username = eventData.username,
        photoUrl = eventData.photoUrl
      })
    end
  elseif eventType == 'start-gameplay' then
    self:setPhase('gameplay')
    self.data.team1Score = 0
    self.data.team2Score = 0
    for i = #self.entities, 1, -1 do
      if self.entities[i].type == 'level-selector' then
        self:despawnEntity(self.entities[i])
      end
    end
    self:forEachEntityWhere({ type = 'player'}, function(player)
      player.freezeFrames = 30
      player.x = GAME_WIDTH / 2 - player.width / 2 + (player.team == 2 and 40 or -40)
    end)
    for i = 1, 3 do
      self:spawnEntity({
        id = 'ball-' .. i,
        type = 'ball',
        x = GAME_WIDTH / 2 - 4,
        y = GAME_HEIGHT / 2 - 4 + 40 * (i - 2),
        width = 8,
        height = 8,
        vx = 0,
        vy = 0,
        thrower = nil,
        team = nil,
        framesSinceThrow = 0,
        framesSinceBallCollision = 0,
        timeSinceCatch = 0.00,
        freezeFrames = 0,
        isBeingHeld = false
      })
    end
    for i = 1, #eventData.bricks do
      local brickData = eventData.bricks[i]
      self:spawnEntity({
        id = 'brick-' .. i,
        type = 'brick',
        x = brickData.x,
        y = brickData.y,
        width = 6,
        height = 12,
        color = brickData.color,
        material = brickData.material,
        team = brickData.team,
        isDespawning = false
      })
    end
  -- Despawn a player
  elseif eventType == 'despawn-player' then
    local player = self:getEntityWhere({ id = 'player-' .. eventData.clientId })
    if player then
      -- Update the player counts
      if player.team == 1 then
        self.data.numTeam1Players = self.data.numTeam1Players - 1
      elseif player.team == 2 then
        self.data.numTeam2Players = self.data.numTeam2Players - 1
      end
      self:despawnEntity(player)
    end
  elseif eventType == 'catch-ball' then
    local player = self:getEntityById(eventData.playerId)
    local ball = self:getEntityById(eventData.ballId)
    if player and ball and not ball.isBeingHeld then
      player.heldBall = ball.id
      player.anim = 'catching'
      player.animFrames = 20
      player.numCatches = player.numCatches + 1
      ball.isBeingHeld = true
      ball.timeSinceCatch = 0.00
    end
  elseif eventType == 'knock-back-player' then
    local player = self:getEntityById(eventData.playerId)
    if player then
      player.x = eventData.x
      player.y = eventData.y
      self:knockBackPlayer(player, eventData.vx, eventData.vy)
    end
  elseif eventType == 'charge-throw' or eventType == 'aim-throw' or eventType == 'throw' or eventType == 'catch' then
    local player = self:getEntityById(eventData.playerId)
    if player then
      if eventType == 'catch' then
        player.anim = 'catching'
        player.animFrames = 42
      elseif player.heldBall then
        if eventType == 'charge-throw' then
          player.anim = 'charging'
          player.animFrames = 0
          player.charge = 0
        elseif eventType == 'aim-throw' then
          player.anim = 'aiming'
          player.animFrames = 0
          player.baseAim = 0
          player.aim = 0
          if eventData.charge then
            player.charge = eventData.charge
          end
        elseif eventType == 'throw' then
          self:temporarilyDisableSyncForEntity(player)
          local ball = self:getEntityById(player.heldBall)
          local charge = eventData.charge or player.charge
          local aim = eventData.aim or player.aim
          player.anim = 'throwing'
          player.animFrames = 35 - 15 * math.abs(charge / 100)
          player.charge = nil
          player.aim = nil
          player.baseAim = nil
          player.heldBall = nil
          if ball then
            local angle = aim / 83
            local dx = 10 * math.cos(angle) * (player.team == 1 and 1 or -1)
            local dy = 10 * math.sin(angle)
            local speed = 90 - 60 * math.abs(charge / 100)
            ball.freezeFrames = player.animFrames - 2
            ball.vx = speed * math.cos(angle) * (player.team == 1 and 1 or -1)
            ball.vy = speed * math.sin(angle)
            ball.x = player.x + dx + player.width / 2 - ball.width / 2
            ball.y = player.y + dy - 3 + player.height / 2 - ball.height / 2
            ball.isBeingHeld = false
            ball.thrower = player.id
            ball.team = player.team
            ball.framesSinceThrow = 0
          end
        end
      end
    end
  elseif eventType == 'score-brick' then
    local brick = self:getEntityById(eventData.brickId)
    if brick then
      brick.framesToDeath = 7
      brick.isDespawning = true
      if brick.team == 1 then
        self.data.team1Score = self.data.team1Score + (brick.material == 'gold' and 3 or 1)
      else
        self.data.team2Score = self.data.team2Score + (brick.material == 'gold' and 3 or 1)
      end
    end
  elseif eventType == 'finish-scoring' then
    self:setPhase('declaring-winner')
  end
end

function game.endGameplay(self)
  self:setPhase('scoring')
  for i = #self.entities, 1, -1 do
    local entity = self.entities[i]
    if entity.type == 'ball' then
      self:despawnEntity(entity)
    elseif entity.type == 'player' then
      entity.heldBall = nil
      if entity.anim == 'catching' or entity.anim == 'charging' or entity.anim == 'aiming' or entity.anim == 'throwing' then
        entity.anim = nil
        entity.animFrames = 0
      end
      entity.charge = nil
      entity.aim = nil
      entity.baseAim = nil
    end
  end
end

function game.startUp(self)
  self:setPhase('starting-up')
  for team = 1, 2 do
    for lvl = 1, 8 do
      self:spawnEntity({
        type = 'level-selector',
        x = (team == 1 and 7 or GAME_WIDTH - 35) + 32 * ((lvl - 1) % 4) * (team == 1 and 1 or -1),
        y = lvl <= 4 and 7 or 110,
        width = 27,
        height = 28,
        team = team,
        level = lvl
      })
    end
  end
end

function game.setPhase(self, phase)
  self.data.phase = phase
  self.data.phaseTimer = 0.00
  self.data.phaseFrame = 0
end

function game.knockBackPlayer(self, player, vx, vy)
  player.vx = vx
  player.vy = vy
  player.numTimesKnockedBack = player.numTimesKnockedBack + 1
  player.anim = 'getting-hit'
  player.animFrames = 20
  player.invincibilityFrames = 150
  if player.heldBall then
    local ball = self:getEntityById(player.heldBall)
    if ball then
      ball.freezeFrames = 3
      ball.vx = -player.vx / 2
      ball.vy = -player.vy / 2
      ball.x = player.x + player.width / 2 - ball.width / 2
      ball.y = player.y - 3 + player.height / 2 - ball.height / 2
      ball.isBeingHeld = false
      ball.thrower = player.id
      ball.team = player.team
      ball.framesSinceThrow = 0
      ball.framesSinceBallCollision = 0
    end
  end
  player.heldBall = nil
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
  exposeGameWithoutPrediction = false,
  width = 299,
  height = 190,
  framesBetweenClientSmoothing = 1,
  numClients = 4,
  latency = 250
})

function server.load(self)
  self.levelData = love.image.newImageData('img/level-data.png')
end

-- When a client disconnects from the server, despawn their player entity
function server.clientdisconnected(self, client)
  -- Despawn the client's player
  self:fireEvent('despawn-player', { clientId = client.clientId })
end

function server.update(self, dt)
  if self.game.data.phase == 'starting-up' and self.game.data.phaseTimer >= TIME_BEFORE_ROUND_START then
    local team1Votes = {}
    local team2Votes = {}
    self.game:forEachEntityWhere({ type = 'player' }, function(player)
      if player.levelVote then
        if player.team == 1 then
          table.insert(team1Votes, player.levelVote)
        elseif player.team == 2 then
          table.insert(team2Votes, player.levelVote)
        end
      end
    end)
    local team1Level = #team1Votes > 0 and team1Votes[math.random(1, #team1Votes)] or 1
    local team2Level = #team2Votes > 0 and team2Votes[math.random(1, #team2Votes)] or 1
    self:startGameplay(team1Level, team2Level)
  end
end

function server.gametriggered(self, triggerName, triggerData)
  if triggerName == 'player-caught-ball' then
    self:fireEvent('catch-ball', {
      playerId = triggerData.playerId,
      ballId = triggerData.ballId
    }, {
      eventId = 'catch-' .. triggerData.playerId .. '-' .. (triggerData.numCatches + 1)
    })
  elseif triggerName == 'player-got-hit-by-ball' then
    self:fireEvent('knock-back-player', {
      playerId = triggerData.playerId,
      x = triggerData.x,
      y = triggerData.y,
      vx = triggerData.vx,
      vy = triggerData.vy
    }, {
      eventId = 'knockback-' .. triggerData.playerId .. '-' .. (triggerData.numTimesKnockedBack + 1)
    })
  elseif triggerName == 'player-held-ball-too-long' then
    self:fireEvent('knock-back-player', {
      playerId = triggerData.playerId,
      x = triggerData.x,
      y = triggerData.y,
      vx = triggerData.team == 1 and -70 or 70,
      vy = 0
    }, {
      eventId = 'knockback-' .. triggerData.playerId .. '-' .. (triggerData.numTimesKnockedBack + 1)
    })
  elseif triggerName == 'score-step' then
    local brick1 = self.game:getEntityWhere({ type = 'brick', team = 1, isDespawning = false })
    local brick2 = self.game:getEntityWhere({ type = 'brick', team = 2, isDespawning = false })
    if brick1 or brick2 then
      if brick1 then
        self:fireEvent('score-brick', {
          brickId = brick1.id
        })
      end
      if brick2 then
        self:fireEvent('score-brick', {
          brickId = brick2.id
        })
      end
    else
      self:fireEvent('finish-scoring')
    end
  end
end

function server.startGameplay(self, team1Level, team2Level)
  local bricks = {}
  for y = 0, 44 do
    for team = 1, 2 do
      for x = 0, 44 do
        local symbol
        local r1, g1, b1 = self.levelData:getPixel(x + 47 * ((team == 1 and team1Level or team2Level) - 1), y)
        for k, v in pairs(LEVEL_DATA_LOOKUP) do
          local r2, g2, b2 = v[1] / 255, v[2] / 255, v[3] / 255
          if r2 * 0.95 <= r1 and r1 <= r2 * 1.05 and g2 * 0.95 <= g1 and g1 <= g2 * 1.05 and b2 * 0.95 <= b1 and b1 <= b2 * 1.05 then
            symbol = k
            break
          end
        end
        if symbol then
          local material, color
          if symbol == 'purpleBrick' then
            color = 1
          elseif symbol == 'pinkBrick' then
            color = 2
          elseif symbol == 'orangeBrick' then
            color = 3
          elseif symbol == 'blueBrick' then
            color = 4
          elseif symbol == 'greenBrick' then
            color = 5
          elseif symbol == 'goldBrick' then
            material = 'gold'
          elseif symbol == 'metalBrick' then
            material = 'metal'
          elseif symbol == 'glassBrick' then
            material = 'glass'
          end
          table.insert(bricks, { x = team == 1 and 3 * x or GAME_WIDTH - 3 * x - 6, y = 3 * y, team = team, material = material, color = color })
        end
      end
    end
  end
  self:fireEvent('start-gameplay', {
    bricks = bricks
  })
end

function client.load(self)
  self.isShowingInstructions = false
  self.isShowingTitleScreen = true
  self.wasDisconnected = false
  self.failedToConnect = false
  self.font = love.graphics.newFont(6)
  love.graphics.setFont(self.font)
  love.graphics.setDefaultFilter('nearest', 'nearest')
  self.spriteSheet = love.graphics.newImage('img/sprite-sheet.png')
end

function client.disconnected(self)
  self.isShowingTitleScreen = true
  self.isShowingInstructions = false
  self.wasDisconnected = true
end

function client.connectfailed(self)
  self.isShowingTitleScreen = true
  self.isShowingInstructions = false
  self.failedToConnect = true
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
  local player = self:getPlayer()
  love.graphics.clear(12 / 255, 3 / 255, 28 / 255)
  love.graphics.translate(10, 28)
  -- Draw round timer
  love.graphics.setColor(1, 1, 1)
  if self.game.data.phase == 'gameplay' then
    self:drawTimer(TIME_PER_ROUND - self.game.data.phaseTimer)
  elseif self.game.data.phase == 'starting-up' then
    self:drawSprite(283, 254, 66, 6, 108, -22)
    self:drawTimer(TIME_BEFORE_ROUND_START - self.game.data.phaseTimer)
  else
    self:drawTimer(0)
  end
  -- Draw team scores
  if self.game.data.phase == 'scoring' or (self.game.data.phase == 'declaring-winner' and self.game.data.phaseFrame < 120) then
    self:drawText(self.game.data.team1Score, self.game.data.team1Score < 10 and 77 or 72, -13, 4)
    self:drawText(self.game.data.team2Score, GAME_WIDTH - (self.game.data.team2Score < 10 and 83 or 88), -13, 2)
  elseif self.game.data.phase == 'declaring-winner' then
    self:drawSprite(283, self.game.data.team1Score >= self.game.data.team2Score and 279 or 261, 68, 16, GAME_WIDTH / 2 - 34 - 60, -20)
    self:drawSprite(352, self.game.data.team2Score >= self.game.data.team1Score and 279 or 261, 68, 16, GAME_WIDTH / 2 - 34 + 60, -20)
  end
  -- Draw the court
  love.graphics.setColor(1, 1, 1)
  self:drawSprite(1, 204, 281, 149, -1, 0)
  -- Draw each entity's actual state
  -- love.graphics.setColor(1, 1, 1)
  -- for _, entity in ipairs(self.gameWithoutPrediction.entities) do
  --   if entity.type == 'ball' then
  --     love.graphics.circle('line', entity.x + entity.width / 2, entity.y + entity.height / 2, 6)
  --   else
  --     love.graphics.rectangle('line', entity.x, entity.y, entity.width, entity.height)
  --   end
  -- end
  -- Draw each entity's shadow
  love.graphics.setColor(1, 1, 1)
  for _, entity in ipairs(self.game.entities) do
    if entity.type == 'player' then
      self:drawSprite(25, 17, 10, 4, entity.x, entity.y + entity.height - 6)
    elseif entity.type == 'brick' then
      self:drawSprite(1, 17, 8, 14, entity.x - (entity.team == 1 and 2 or 1), entity.y - 1)
    elseif entity.type == 'ball' then
      if not entity.isBeingHeld then
        self:drawSprite(25, 22, 10, 4, entity.x - 1, entity.y + entity.height - 3)
      end
    end
  end
  -- Draw level selection
  -- self:drawSprite(274, 354, 123, 127, 9, 9)
  -- self:drawSprite(274, 354, 123, 127, 147, 9, true)
  -- Draw all level selectors
  self.game:forEachEntityWhere({ type = 'level-selector' }, function(selector)
    local borderSprite
    if player and player.team == selector.team and player.levelVote == selector.level then
      if player.team == 1 then
        borderSprite = 2
      else
        borderSprite = 3
      end
    else
      borderSprite = 1
    end
    self:drawSprite(234 + 28 * (borderSprite - 1), 379, 27, 28, selector.x, selector.y, selector.team == 2)
    self:drawSprite(234 + 24 * (selector.level - 1), 354, 23, 24, selector.x + 2, selector.y + 2, selector.team == 2)
  end)
  -- Draw an indicator under your player character
  if player then
    self:drawSprite(player.team == 1 and 53 or 36, 17, 16, 8, player.x - 3, player.y)
  end
  -- Draw all the bricks
  self.game:forEachEntityWhere({ type = 'brick' }, function(brick)
    local sprite
    if brick.isDespawning then
      sprite = 1
    elseif brick.color then
      sprite = brick.color + 1
    elseif brick.material == 'gold' then
      sprite = 10
    elseif brick.material == 'metal' then
      sprite = 7
    elseif brick.material == 'broken-metal' then
      sprite = 8
    elseif brick.material == 'glass' then
      sprite = 9
    end
    self:drawSprite(1 + 7 * (sprite - 1), 1, 6, 15, brick.x, brick.y - 3, brick.team == 2)
  end)
  -- Draw all the players
  self.game:forEachEntityWhere({ type = 'player' }, function(player)
    local sx = 1
    local sy = (player.team == 2 and 33 or 118)
    local x = player.x
    local y = player.y
    local flipHorizontal = player.facingX < 0
    local animSprite
    if player.isMoving then
      animSprite = 2 + math.floor((player.moveFrames % (8 * 5)) / 5)
    else
      animSprite = 1
    end
    local dirSprite
    if player.facingY < 0 then
      dirSprite = player.facingX == 0 and 1 or 2
    elseif player.facingY > 0 then
      dirSprite = player.facingX == 0 and 5 or 4
    else
      dirSprite = 3
    end
    if player.anim == 'getting-hit' then
      animSprite = 19
      dirSprite = 2
      flipHorizontal = player.vx < 0
    elseif player.anim == 'standing-up' then
      animSprite = player.animFrames > 15 and 20 or 21
      dirSprite = 2
      flipHorizontal = player.vx < 0
    elseif player.anim == 'catching' then
      animSprite = player.heldBall and 26 or (player.animFrames > 30 and 24 or 25)
      dirSprite = 3
      flipHorizontal = player.team == 2
    elseif player.anim == 'charging' then
      animSprite = player.isMoving and player.moveFrames % 40 > 20 and 20 or 19
      dirSprite = 3
      x, y = x  + (player.team == 1 and -3 or 3), y - 1
      flipHorizontal = player.team == 2
    elseif player.anim == 'aiming' then
      animSprite = player.isMoving and player.moveFrames % 70 > 35 and 22 or 21
      dirSprite = 3
      x, y = x + (player.team == 1 and -3 or 3), y - 1
      flipHorizontal = player.team == 2
    elseif player.anim == 'throwing' then
      animSprite = 23
      dirSprite = 3
      flipHorizontal = player.team == 2
    elseif player.heldBall then
      animSprite = animSprite + 9
    end
    self:drawSprite(sx + 16 * (animSprite - 1), sy + 17 * (dirSprite - 1), 15, 16, x - (flipHorizontal and 4 or 1), y - 9, flipHorizontal)
    if player.username and (player.clientId ~= self.clientId or (player.anim ~= 'charging' and player.anim ~= 'aiming')) then
      if player.team == 1 then
        love.graphics.setColor(72 / 255, 167 / 255, 205 / 255)
      else
        love.graphics.setColor(218 / 255, 63 / 255, 111 / 255)
      end
      love.graphics.push()
      love.graphics.scale(0.6, 0.6)
      love.graphics.print(player.username, (player.x + 5.5) / 0.6 - self.font:getWidth(player.username) / 2, (player.y - 13) / 0.6)
      love.graphics.pop()
      love.graphics.setColor(1, 1, 1)
    end
    -- Draw ball drop countdown
    if player.heldBall then
      local ball = self.game:getEntityById(player.heldBall)
      if ball then
        local timeLeft = math.max(0, math.floor((MAX_BALL_HOLD_TIME - ball.timeSinceCatch) / 1.5))
        if timeLeft < 3 then
          self:drawSprite(293 + 7 * timeLeft, 204, 6, 9, player.x + (player.team == 1 and 2 - 13 or 2 + 13), player.y - 6)
        end
      end
    end
  end)
  -- Draw all the balls
  self.game:forEachEntityWhere({ type = 'ball' }, function(ball)
    if not ball.isBeingHeld then
      self:drawSprite(70, 17, 8, 8, ball.x, ball.y - (ball.vx == 0 and ball.vy == 0 and 0 or 1))
    end
  end)
  -- Draw aiming indicator
  if player and player.anim == 'charging' then
    self:drawSprite(120, 25, 29, 6, player.x - (player.team == 1 and 10 or 9), player.y - 15)
    self:drawSprite(150, 21, 1, 10, player.x + (player.team == 1 and 4 or 5) + 13 * player.charge / 100, player.y - 18)
  elseif player and player.anim == 'aiming' then
    local angle = player.aim / 83
    local dx = 11 * math.cos(angle) * (player.team == 1 and 1 or -1)
    local dy = 10 * math.sin(angle)
    self:drawSprite(411, 204, 4, 54, player.x + (player.team == 1 and 5 or 1), player.y - 28, player.team == 2)
    self:drawSprite(121, 17, 22, 7, player.x + dx + (player.team == 1 and -7 or -6), player.y + dy - 3, player.team == 2, false, (player.team == 1 and angle or -angle))
  end
  -- Draw keys
  self:drawSprite(330, 305, 66, 8, 200, 151)
    -- Blackout screen
  if self.isShowingTitleScreen or self.isShowingInstructions then
    love.graphics.setColor(0, 0, 0, 0.8)
    love.graphics.rectangle('fill', -10, -28, 299, 190)
    love.graphics.setColor(1, 1, 1)
  end
  if self.isShowingTitleScreen then
    -- Draw title
    self:drawSprite(1, 354, 230, 80, 25, 20)
    -- Draw status
    if self.failedToConnect then
      self:drawSprite(152, 9, 113, 6, 83, 115)
    elseif self.wasDisconnected then
      self:drawSprite(152, 23, 113, 6, 83, 115)
    elseif not self:isConnected() then
      self:drawSprite(152, 2, 113, 6, 83, 115)
    elseif self.game.frame % 60 < 50 then
      self:drawSprite(152, 16, 113, 6, 83, 115)
    end
  elseif self.isShowingInstructions then
    self:drawSprite(1, self.game.frame % 90 < 45 and 546 or 435, 272, 110, 4, 20)
  elseif not player then
    if self.game.frame % 150 < 75 then
      self:drawSprite(266, 2, 113, 6, 83, 43)
    else
      self:drawSprite(266, 9, 113, 6, 83, 43)
    end
  end
end

function client.gametriggered(self, triggerName, triggerData)
  if triggerName == 'player-caught-ball' and self.clientId and triggerData.playerId == 'player-' .. self.clientId then
    self:fireEvent('catch-ball', {
      playerId = triggerData.playerId,
      ballId = triggerData.ballId
    }, {
      sendToServer = false,
      eventId = 'catch-' .. triggerData.playerId .. '-' .. (triggerData.numCatches + 1)
    })
  elseif triggerName == 'player-got-hit-by-ball' and self.clientId and triggerData.playerId == 'player-' .. self.clientId then
    local clientEvent, serverEvent = self:fireEvent('knock-back-player', {
      playerId = triggerData.playerId,
      x = triggerData.x,
      y = triggerData.y,
      vx = triggerData.vx,
      vy = triggerData.vy
    }, {
      sendToServer = false,
      eventId = 'knockback-' .. triggerData.playerId .. '-' .. (triggerData.numTimesKnockedBack + 1)
    })
  elseif triggerName == 'player-held-ball-too-long' and self.clientId and triggerData.playerId == 'player-' .. self.clientId then
    self:fireEvent('knock-back-player', {
      playerId = triggerData.playerId,
      x = triggerData.x,
      y = triggerData.y,
      vx = triggerData.team == 1 and -70 or 70,
      vy = 0
    }, {
      sendToServer = false,
      eventId = 'knockback-' .. triggerData.playerId .. '-' .. (triggerData.numTimesKnockedBack + 1)
    })
  elseif eventType == 'brick-despawned' then

  end
end

function client.smoothEntity(self, game, entity, idealEntity)
  if entity and idealEntity and entity.type == 'player' and entity.clientId == self.clientId then
    local x, y = entity.x, entity.y
    local baseAim, aim, charge = entity.baseAim, entity.aim, entity.charge
    game:copyEntityProps(idealEntity, entity)
    entity.baseAim, entity.aim, entity.charge = baseAim, aim, charge
    entity.x = x * 0.5 + entity.x * 0.5
    entity.y = y * 0.5 + entity.y * 0.5
    return entity
  elseif entity and idealEntity then
    return game:copyEntityProps(idealEntity, entity)
  elseif idealEntity then
    return game:cloneEntity(idealEntity)
  else
    return nil
  end
end

function client.isEntityUsingPrediction(self, entity)
  return entity and (entity.clientId == self.clientId or entity.type == 'ball' or entity.type == 'brick')
end

function client.isEventUsingPrediction(self, event, firedByClient)
  return firedByClient or event.type == 'throw' or event.type == 'start-gameplay'
end

function client.keypressed(self, key)
  if self:isHighlighted() then
    if key == 'i' and not self.isShowingTitleScreen then
      self.isShowingInstructions = not self.isShowingInstructions
    elseif key == 'space' then
      if self.isShowingTitleScreen then
        if self:isConnected() then
          self.isShowingTitleScreen = false
        end
      else
        local player = self:getPlayer()
        if not player then
          self:fireEvent('join-game', {
            clientId = self.clientId,
            username = self.user and self.user.username,
            photoUrl = self.user and self.user.photoUrl
          })
        elseif player.heldBall then
          if not player.anim then
            self:fireEvent('charge-throw', { playerId = player.id })
          elseif player.anim == 'charging' and player.animFrames > 4 then
            self:fireEvent('aim-throw', { playerId = player.id, charge = player.charge })
          elseif player.anim == 'aiming' and player.animFrames > 4 then
            self:fireEvent('throw', { playerId = player.id, charge = player.charge, aim = player.aim })
          end
        elseif not player.anim then
          self:fireEvent('catch', { playerId = player.id })
        end
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

function client.getPlayer(self)
  if self.clientId then
    return self.game:getEntityById('player-' .. self.clientId)
  end
end

function client.drawText(self, text, x, y, color)
  color = color or 1
  text = '' .. (text or '')
  local currX = x
  for i = 1, #text do
    local c = text:sub(i, i)
    local n = tonumber(c)
    if c == ':' then
      self:drawSprite(283, 204 + 10 * (color - 1), 2, 9, currX, y)
      currX = currX + 3
    elseif n then
      self:drawSprite(286 + 7 * n, 204 + 10 * (color - 1), 6, 9, currX, y)
      currX = currX + 7
    else
      self:drawSprite(356, 204 + 10 * (color - 1), 6, 9, currX, y)
      currX = currX + 7
    end
  end
end

function client.drawTimer(self, time)
  time = math.max(0, time)
  local minutesLeft = math.floor(time / 60)
  local secondsLeft = math.floor(time) % 60
  local isRed = time < 10 and time % 1 > 0.75
  self:drawText(minutesLeft .. ':' .. (secondsLeft < 10 and '0' .. secondsLeft or secondsLeft), 127, -13, isRed and 2 or 1)
end
