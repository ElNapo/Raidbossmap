-- To complete:

-- A system that transforms a certain entity into a raidboss with special attacks,
-- partial immunity against attacks and a special AI

Raidboss = {}
-- multiplier by entity category
Raidboss.DamageMultipliers = {
    [EntityCategories.Bow] = 1,
    [EntityCategories.Cannon] = 1,
    [EntityCategories.CavalryHeavy] = 1,
    [EntityCategories.CavalryLight] = 1,
    [EntityCategories.Hero] = 0.1,
    [EntityCategories.Rifle] = 1,
    [EntityCategories.Spear] = 1,
    [EntityCategories.Sword] = 1
}
-- multiplier if no appropriate ECategory was found
Raidboss.FallbackMultiplier = 0.1
-- table concerning the attack schemes
Raidboss.AttackSchemes = {
    PoisonStrike = {
        -- determines the probability of using this attack next
        weight = 100,
        -- the function that will be called if this function was selected
        callback = Raidboss.PoisonStrike,
        -- the system assumes that this is the duration of the attack, e.g. the next attack will be selected after this time
        duration = 15,
        -- if this attack was used it cannot be used again
        disallowRepeatedCasting = true,
        -- parameters of the attack that will be used internally
        chargeTime = 5,
        effectDOT = 100,
        radius = 750
    },
    MeteorStrike = {
        weight = 30,
        callback = Raidboss.MeteorStrike,
        duration = 10,
        disallowRepeatedCasting = true,
        -- internal stuff
        chargeTime = 5,
        damage = 700,
        radius = 750
    },
    FearInducingStrike = {
        weight = 30,
        callback = Raidboss.FearStrike,
        duration = 10,
        disallowRepeatedCasting = true,
        -- internal stuff
        chargeTime = 5,
        fearDuration = 20,
        fleeDistance = 3000,
        range = 1500
    },
    ArmorShred = {
        weight = 30,
        callback = Raidboss.FearStrike,
        duration = 10,
        disallowRepeatedCasting = true,
        -- internal stuff
        shredValue = 50,
        shredDuration = 60,
        range = 1500
    }
}
Raidboss.CombatRange = 3000

function Raidboss.Init( _eId)
    Raidboss.eId = _eId
    Raidboss.Origin = GetPosition( _eId)

    -- setup special attack scheduler
    Raidboss.AttackScheduler = {
        lastAttack = nil,
        currentAttackStarted = 0,
        timeToNextAttack = 15,
        listOfScheduledAttacks = {}
    }
    Raidboss.InCombat = false
    Raidboss.JobId = StartSimpleJob("Raidboss_Job")

    -- create raidboss arena
    local dx, dy, angle, stoneId
    for i = 1, 72 do
        angle = math.rad(i * 5)
        dx = math.cos(angle)*Raidboss.CombatRange
        dy = math.sin(angle)*Raidboss.CombatRange
        stoneId = Logic.CreateEntity( Entities.XD_Rock1, Raidboss.Origin.X + dx, Raidboss.Origin.Y + dy, i*5+90, 0)
        Logic.SetModelAndAnimSet( stoneId, Models.Banners_XB_StandarteOccupied)
    end

    -- setup damage system
    Raidboss.HurtTrigger = Trigger.RequestTrigger(Events.LOGIC_EVENT_ENTITY_HURT_ENTITY, nil, "Raidboss_OnHit", 1)
end

function Raidboss_OnHit()
    local attacker = Event.GetEntityID1()
    local attacked = Event.GetEntityID2()
    if attacker == Raidboss.eId then
        Raidboss.InCombat = true
    end
    if attacked == Raidboss.eId then
        Raidboss.InCombat = true
        if IsDead(attacker) then return end
        Raidboss.ManipulateTrigger( attacker)
    end
end
function Raidboss.ManipulateTrigger( _attackerId)
    local rawDamage = CEntity.TriggerGetDamage()
    local factor = Raidboss.FallbackMultiplier
    for k,v in pairs(Raidboss.DamageMultipliers) do
        if Logic.IsEntityInCategory( _attackerId, k) == 1 then
            --LuaDebugger.Log("Attacker has ECategory"..k)
            factor = v
            break
        end
    end
    local newDamage = math.floor(rawDamage*factor)
    --LuaDebugger.Log(factor)
    --LuaDebugger.Log(newDamage)
    CEntity.TriggerSetDamage( newDamage)
end


function Raidboss_Job()
    Raidboss.UpdateCombatStatus()
    Raidboss.TickScheduler()
end
function Raidboss.UpdateCombatStatus()
end
function Raidboss.TickScheduler()

end

function Raidboss.PoisonStrike( _schemeTable, _targetPos)

end
function Raidboss.MeteorStrike( _schemeTable, _targetPos)

end
function Raidboss.FearStrike( _schemeTable, _targetPos)

end


