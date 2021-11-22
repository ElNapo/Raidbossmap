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

Raidboss.CombatRange = 3000
Raidboss.MaxHealth = 100000
Raidboss.Armor = 0
Raidboss.Damage = 1
Raidboss.AttackRange = 800
Raidboss.MovementSpeed = 600
Raidboss.Scale = 4
Raidboss.LastHitTime = 0

function Raidboss.Init( _eId)
    Raidboss.eId = _eId
    Raidboss.Origin = GetPosition( _eId)
    Raidboss.ApplyKerbeChanges()
    -- setup special attack scheduler
    Raidboss.AttackScheduler = {
        lastAttack = nil,
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
    Raidboss.DamageTracker = {}
    for i = 0, 16 do
        Raidboss.DamageTracker[i] = 0
    end

end
function Raidboss.ApplyKerbeChanges()
    Raidboss.Pointers = {
        LeaderBeh = S5Hook.GetRawMem(9002416)[0][16][ 195 *8+5][6],
        Logic = S5Hook.GetRawMem(9002416)[0][16][ 195*8+2]
    }
    -- set max health
    Raidboss.Pointers.Logic[13]:SetInt(Raidboss.MaxHealth)
    -- set armor
    Raidboss.Pointers.Logic[61]:SetInt(Raidboss.Armor)
    -- fix health difference
    Logic.HealEntity( Raidboss.eId, Raidboss.MaxHealth - Logic.GetEntityHealth(Raidboss.eId))
    -- set regen to 0
    Raidboss.Pointers.LeaderBeh[28]:SetInt(0)
    -- set attack range
    Raidboss.Pointers.LeaderBeh[23]:SetFloat(Raidboss.AttackRange)
    -- set attack damage
    Raidboss.Pointers.LeaderBeh[14]:SetInt(Raidboss.Damage)
    
    -- movement speed and scale
    S5Hook.GetEntityMem( Raidboss.eId)[31][1][5]:SetFloat( Raidboss.MovementSpeed)
    S5Hook.GetEntityMem( Raidboss.eId)[25]:SetFloat( Raidboss.Scale)
end

function Raidboss_OnHit()
    local attacker = Event.GetEntityID1()
    local attacked = Event.GetEntityID2()
    if attacker == Raidboss.eId then
        Raidboss.InCombat = true
        Raidboss.LastHitTime = Logic.GetTime()
    end
    if attacked == Raidboss.eId then
        Raidboss.LastHitTime = Logic.GetTime()
        Raidboss.InCombat = true
        if Raidboss.IsAttackerInvalid(attacker) then
            CEntity.TriggerSetDamage(0) -- the dead dont deal damage
            return 
        end
        Raidboss.ManipulateTrigger( attacker)
    end
end
function Raidboss.IsAttackerInvalid( _eId)
    if IsDead( _eId) then return true end
    local pos = GetPosition( _eId)
    if Raidboss.GetDistanceSq( pos, Raidboss.Origin) > Raidboss.CombatRange^2 then
        return true
    end
    return false
end
function Raidboss.GetDistanceSq( p1, p2)
    return (p1.X - p2.X)^2 + (p1.Y - p2.Y)^2
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
    Raidboss.DamageTracker[GetPlayer(_attackerId)] = Raidboss.DamageTracker[GetPlayer(_attackerId)] + newDamage
    CEntity.TriggerSetDamage( newDamage)
end

function Raidboss_Job()
    if Logic.GetTime() - 8 > Raidboss.LastHitTime then
        Raidboss.InCombat = false
    end
    if Raidboss.InCombat then
        Raidboss.TickScheduler()
    end
end
function Raidboss.TickScheduler()
    t = Raidboss.AttackScheduler
    t.timeToNextAttack = math.max(t.timeToNextAttack - 1,0)
    if t.timeToNextAttack == 0 then
        if table.getn(t.listOfScheduledAttacks) > 0 then -- is there already some command supposed to be executed?
            Raidboss.ExecuteAttack(t.listOfScheduledAttacks[1])
            table.remove(t, 1)
        else
            local totalWeight = 0
            local isLastAttackForbidden = false
            if t.lastAttack ~= nil then
                isLastAttackForbidden = Raidboss.AttackSchemes[t.lastAttack].disallowRepeatedCasting
            end
            -- sum up all admissable weights
            admissableScenarios = {}
            for k,v in pairs(Raidboss.AttackSchemes) do
                if not( k == t.lastAttack and isLastAttackForbidden) then
                    table.insert(admissableScenarios, {k = k, w = v.weight})
                    totalWeight = totalWeight + v.weight
                end
            end
            local rndNumber = math.random(totalWeight)
            local attackName
            for i = 1, table.getn(admissableScenarios) do
                rndNumber = rndNumber - admissableScenarios[i].w
                if rndNumber <= 0 then
                    attackName = admissableScenarios[i].k
                    break
                end
            end
            LuaDebugger.Log("Selected "..attackName)
            Raidboss.ExecuteAttack( attackName)
        end
    end
end
function Raidboss.ExecuteAttack( _attackName)
    myAttack = Raidboss.AttackSchemes[_attackName]
    t = Raidboss.AttackScheduler
    t.lastAttack = _attackName
    t.timeToNextAttack = myAttack.duration
    targetPos = Raidboss.FindNiceTarget()
    myAttack.callback( myAttack, targetPos)
end

function Raidboss.FindNiceTarget()
end

function Raidboss.PoisonStrike( _schemeTable, _targetPos)

end
function Raidboss.MeteorStrike( _schemeTable, _targetPos)

end
function Raidboss.FearStrike( _schemeTable, _targetPos)

end


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