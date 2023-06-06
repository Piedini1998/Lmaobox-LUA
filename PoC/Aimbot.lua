--[[
    Custom Aimbot for Lmaobox
    Author: github.com/lnx00
]]

if UnloadLib then UnloadLib() end

---@alias AimTarget { entity : Entity, angles : EulerAngles, factor : number }

---@type boolean, lnxLib
local libLoaded, lnxLib = pcall(require, "lnxLib")
assert(libLoaded, "lnxLib not found, please install it!")
assert(lnxLib.GetVersion() >= 0.987, "lnxLib version is too old, please update it!")

local Math, Conversion = lnxLib.Utils.Math, lnxLib.Utils.Conversion
local WPlayer, WWeapon = lnxLib.TF2.WPlayer, lnxLib.TF2.WWeapon
local Helpers = lnxLib.TF2.Helpers
local Prediction = lnxLib.TF2.Prediction
local Fonts = lnxLib.UI.Fonts

local Hitbox = {
    Head = 1,
    Neck = 2,
    Pelvis = 4,
    Body = 5,
    Chest = 7
}

local options = {
    AimKey = KEY_LSHIFT,
    AutoShoot = true,
    Silent = true,
    AimPos = Hitbox.Head,
    AimFov = 40,
    PredTicks = 60,
    Debug = true
}

local latency = 0
local lerp = 0

-- Finds the best position for hitscan weapons
---@param me WPlayer
---@param weapon WWeapon
---@param player WPlayer
---@return AimTarget?
local function CheckHitscanTarget(me, weapon, player)
    -- FOV Check
    local aimPos = player:GetHitboxPos(options.AimPos)
    if not aimPos then return nil end
    local angles = Math.PositionAngles(me:GetEyePos(), aimPos)
    local fov = Math.AngleFov(angles, engine.GetViewAngles())

    -- Visiblity Check
    if not Helpers.VisPos(player:Unwrap(), me:GetEyePos(), aimPos) then return nil end

    -- The target is valid
    local target = { entity = player, angles = angles, factor = fov }
    return target
end

-- Finds the best position for projectile weapons
---@param me WPlayer
---@param weapon WWeapon
---@param player WPlayer
---@return AimTarget?
local function CheckProjectileTarget(me, weapon, player)
    local projInfo = weapon:GetProjectileInfo()
    if not projInfo then return nil end

    local speed = projInfo[1]
    local shootPos = me:GetEyePos()

    -- Distance check
    local maxDistance = options.PredTicks * speed
    if me:DistTo(player) > maxDistance then return nil end

    -- Visiblity Check
    if not Helpers.VisPos(player:Unwrap(), shootPos, player:GetAbsOrigin()) then
        return nil
    end

    local predData = Prediction.Player(player, options.PredTicks)
    if not predData then return nil end

    -- Find a valid prediction
    local targetAngles = nil
    for i = 0, options.PredTicks do
        local pos = predData.pos[i]
        local solution = Math.SolveProjectile(me:GetEyePos(), pos, projInfo[1], projInfo[2])
        if not solution then goto continue end

        -- Time check
        --local time = Conversion.Ticks_to_Time(i)
        --local dist = (pos - shootPos):Length()
        local time = solution.time + latency + lerp
        local ticks = Conversion.Time_to_Ticks(time) + 1
        if ticks > i then goto continue end

        -- Visiblity Check
        --[[if not Helpers.VisPos(player:Unwrap(), me:GetEyePos(), cPos) then
            goto continue
        end]]

        -- The prediction is valid
        targetPos = pos
        targetAngles = solution.angles
        break

        -- TODO: FOV Check
        ::continue::
    end

    -- We didn't find a valid prediction
    --if not targetPos then return nil end
    --targetPos = targetPos + Vector3(0, 0, 10) -- TODO: Improve this
    if not targetAngles then return nil end

    -- Calculate the fov
    --local angles = Math.SolveProjectile(me:GetEyePos(), targetPos, projInfo[1], projInfo[2])
    --if not angles then return nil end
    local fov = Math.AngleFov(targetAngles, engine.GetViewAngles())

    -- The target is valid
    local target = { entity = player, angles = targetAngles, factor = fov }
    return target
end

-- Checks the given target for the given weapon
---@param me WPlayer
---@param weapon WWeapon
---@param entity Entity
---@return AimTarget?
local function CheckTarget(me, weapon, entity)
    if not entity then return nil end
    if not entity:IsAlive() then return nil end
    if entity:GetTeamNumber() == me:GetTeamNumber() then return nil end

    local player = WPlayer.FromEntity(entity)

    -- FOV check
    local angles = Math.PositionAngles(me:GetEyePos(), player:GetAbsOrigin())
    local fov = Math.AngleFov(angles, engine.GetViewAngles())
    if fov > options.AimFov then return nil end

    if weapon:IsShootingWeapon() then
        -- TODO: Improve this

        local projType = weapon:GetWeaponProjectileType()
        if projType == 1 then
            -- Hitscan weapon
            return CheckHitscanTarget(me, weapon, player)
        else
            -- Projectile weapon
            return CheckProjectileTarget(me, weapon, player)
        end
    elseif weapon:IsMeleeWeapon() then
        -- TODO: Melee Aimbot
    end

    return nil
end

-- Returns the best target for the given weapon
---@param me WPlayer
---@param weapon WWeapon
---@return AimTarget? target
local function GetBestTarget(me, weapon)
    local players = entities.FindByClass("CTFPlayer")
    local bestTarget = nil
    local bestFactor = math.huge

    -- Check all players
    for _, entity in pairs(players) do
        local target = CheckTarget(me, weapon, entity)
        if not target then goto continue end

        -- Add valid target
        if target.factor < bestFactor then
            bestFactor = target.factor
            bestTarget = target
        end

        -- TODO: Continue searching
        break

        ::continue::
    end

    return bestTarget
end

---@param userCmd UserCmd
local function OnCreateMove(userCmd)
    if not input.IsButtonDown(options.AimKey) then return end

    local me = WPlayer.GetLocal()
    if not me then return end

    local weapon = me:GetActiveWeapon()
    if not weapon then return end

    -- Check if we can shoot
    local flCurTime = globals.CurTime()
    local canShoot = weapon:GetNextPrimaryAttack() <= flCurTime and me:GetNextAttack() <= flCurTime
    --if not canShoot then return end

    -- Get current latency
    local latIn, latOut = clientstate.GetLatencyIn(), clientstate.GetLatencyOut()
    if latIn and latOut then
        latency = latIn + latOut
    else
        latency = 0
    end

    -- Get current lerp
    lerp = client.GetConVar("cl_interp") or 0

    -- Get the best target
    local currentTarget = GetBestTarget(me, weapon)
    if not currentTarget then return end

    -- Aim at the target
    userCmd:SetViewAngles(currentTarget.angles:Unpack())
    if not options.Silent then
        engine.SetViewAngles(currentTarget.angles)
    end

    -- Auto Shoot
    if options.AutoShoot then
        userCmd.buttons = userCmd.buttons | IN_ATTACK
    end
end

local function OnDraw()
    draw.SetFont(Fonts.Verdana)
    draw.Color(255, 255, 255, 255)

    -- Draw current latency and lerp
    draw.Text(20, 140, string.format("Latency: %.2f", latency))
    draw.Text(20, 160, string.format("Lerp: %.2f", lerp))

    local me = WPlayer.GetLocal()
    if not me then return end
end

callbacks.Unregister("CreateMove", "LNX.Aimbot.CreateMove")
callbacks.Register("CreateMove", "LNX.Aimbot.CreateMove", OnCreateMove)

callbacks.Unregister("Draw", "LNX.Aimbot.Draw")
callbacks.Register("Draw", "LNX.Aimbot.Draw", OnDraw)