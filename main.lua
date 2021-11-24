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
Raidboss.PlayerMultiplier = {}
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
    if SendEvent then CSendEvent = SendEvent end
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
    if Predicate.IsNotSoldier == nil then
        Predicate.IsNotSoldier = function() 
            return function(_entity) return Logic.SoldierGetLeaderEntityID(_entity) == 0 end; 
        end;
    end
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
        Raidboss.DamageMultipliers[i] = 1
    end

end
function Raidboss.ApplyKerbeChanges()
    Raidboss.Pointers = {
        LeaderBeh = S5Hook.GetRawMem(9002416)[0][16][ 195 *8+5][6],
        AuraBeh = S5Hook.GetRawMem(9002416)[0][16][ 195 *8+5][14],
        -- 4: Recharge, int
        -- 7: Range, float
        -- 8: Duration, int
        -- 10: ArmorShred, float
        FearBeh = S5Hook.GetRawMem(9002416)[0][16][ 195 *8+5][12],
        -- 4: Recharge, int
        -- 7: Duration, int
        -- 8: Flightdistance, float
        -- 9: Range, float
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

    -- changes to fear and armor shred
    Raidboss.Pointers.AuraBeh[10]:SetFloat(0) -- armor shred
    Raidboss.Pointers.AuraBeh[8]:SetInt(600) -- duration
    Raidboss.Pointers.AuraBeh[7]:SetFloat(3000) -- range of initial cast

    Raidboss.Pointers.FearBeh[7]:SetInt(600) -- duration of fear
    Raidboss.Pointers.FearBeh[8]:SetFloat(30000) -- flight distance
    Raidboss.Pointers.FearBeh[9]:SetFloat(800) -- fear range
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
    local factor2 = Raidboss.DamageMultipliers[GetPlayer(_attackerId)]
    for k,v in pairs(Raidboss.DamageMultipliers) do
        if Logic.IsEntityInCategory( _attackerId, k) == 1 then
            --LuaDebugger.Log("Attacker has ECategory"..k)
            factor = v
            break
        end
    end
    local newDamage = math.floor(rawDamage*factor*factor2)
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
Raidboss.MaxSoundRange = 7500
function Raidboss.PlaySound( _soundId, _pos)
    local x,y = GUI.Debug_GetMapPositionUnderMouse()
    local dis = math.sqrt(Raidboss.GetDistanceSq( _pos, {X = x, Y = y}))
    local factor = math.min(dis/Raidboss.MaxSoundRange, 1)
    Sound.PlayGUISound( _soundId, 100 * (1-factor))
end

function Raidboss.FindNiceTarget()
end

function Raidboss.PoisonStrike( _schemeTable, _targetPos)

end
function Raidboss.MeteorStrike( _schemeTable, _targetPos)

end

function Raidboss.FearStrike( _schemeTable, _targetPos)
    StartSimpleJob("Raidboss_FearStrike")
    Raidboss.FearStrikeCounter = 8
    local pos = GetPosition(Raidboss.eId)
    local angle, sin, cos
    for i = 1, 6 do
        angle = i*60
        cos = math.cos(math.rad(angle))
        sin = math.sin(math.rad(angle))
        Logic.CreateEffect(GGL_Effects.FXDie, pos.X + 800*cos, pos.Y + 800*sin, 0)
    end
end
function Raidboss_FearStrike()
    Raidboss.FearStrikeCounter = Raidboss.FearStrikeCounter - 1
    if Raidboss.FearStrikeCounter == 0 then
        CSendEvent.HeroInflictFear( Raidboss.eId)
        local pos = GetPosition(Raidboss.eId)
        Raidboss.PlaySound( Sounds.VoicesHero7_HERO7_InflictFear_rnd_02, pos)
        Logic.CreateEffect( GGL_Effects.FXKerberosFear, pos.X, pos.Y, 0)
        return true
    else
        local angle, cos, sin, r
        local pos = GetPosition(Raidboss.eId)
        r = Raidboss.FearStrikeCounter * 100
        for i = 1, 6 do
            angle = (i + Raidboss.FearStrikeCounter/2) *60
            cos = math.cos(math.rad(angle))
            sin = math.sin(math.rad(angle))
            Logic.CreateEffect(GGL_Effects.FXDie, pos.X + r*cos, pos.Y + r*sin, 0)
        end
    end
end
function Raidboss.ArmorShred( _schemeTable, _targetPos)
    local pos = GetPosition(Raidboss.eId)
    local angle, sin, cos, r
    for i = 1, 3 do
        r = i*1000
        for j = 1, 6*i do
            angle = (j + i/2)*60/i
            sin = math.sin(math.rad(angle))
            cos = math.cos(math.rad(angle))
            Logic.CreateEffect( GGL_Effects.FXMaryDemoralize, pos.X + sin*r, pos.Y + cos*r, 0)
        end
    end
    Logic.CreateEffect( GGL_Effects.FXMaryDemoralize, pos.X, pos.Y, 0)
    CSendEvent.HeroActivateAura( Raidboss.eId)
    Raidboss.PlaySound( Sounds.VoicesHero7_HERO7_Madness_rnd_01, pos)
end
function Raidboss.ReflectArrow( _schemeTable, _targetPos)
    --[[ Raidboss.ReflectArrowT = {
        windUpMax = 50,
        windUp = 50,
        rangeStart = 3000,
        rangeFinish = 800,
        count = 36,
        reflectDuration = 50,
        reflectCounter = 50
    }

    StartSimpleHiResJob("Raidboss_ReflectArrowJob") ]]
    local pos = GetPosition(Raidboss.eId)
    local leaders = S5Hook.EntityIteratorTableize( Predicate.NotOfPlayer0(), Predicate.IsNotSoldier(), Predicate.InCircle( pos.X, pos.Y, 3000))
    local eType, posLeader
    for i = table.getn(leaders), 1, -1 do
        if Logic.IsEntityInCategory( leaders[i], EntityCategories.LongRange) == 0 then
            table.remove(leaders, i)
        else
            posLeader = GetPosition(leaders[i])
            Logic.CreateEffect( GGL_Effects.FXMaryDemoralize, posLeader.X, posLeader.Y, 0)
        end
    end
    StartSimpleHiResJob("Raidboss_ReflectArrow_Job")
    Raidboss.ReflectArrowCounter = 21
    Raidboss.PlaySound( Sounds.Coiner01, pos)
    Raidboss.ReflectArrowLeaders = leaders
end
function Raidboss_ReflectArrow_Job()
    Raidboss.ReflectArrowCounter = Raidboss.ReflectArrowCounter - 1
    if math.mod(Raidboss.ReflectArrowCounter, 2) == 0 then
        local myIndex = Raidboss.ReflectArrowCounter / 2
        if myIndex > 0 then
            Raidboss.PlaySound( Sounds["Misc_Countdown"..myIndex], GetPosition(Raidboss.eId))
        end
    end
    if Raidboss.ReflectArrowCounter <= 0 then
        Raidboss.ReflectArrowActivateShield()
        StartSimpleJob("Raidboss_ReflectArrow_Job2")
        Raidboss.ReflectArrowCounter = 8
        return true
    end
end
function Raidboss_ReflectArrow_Job2()
    Raidboss.ReflectArrowCounter = Raidboss.ReflectArrowCounter - 1
    if Raidboss.ReflectArrowCounter <= 0 then
        Raidboss.ReflectArrowDeactivateShield()
        return true
    end
    local pos
    for k,v in pairs(Raidboss.ReflectArrowLeaders) do
        if not IsDead(v) then
            pos = GetPosition(v)
            Logic.CreateEffect(GGL_Effects.FXMaryDemoralize, pos.X, pos.Y, 0)
        end
    end
end
--[[ function Raidboss_ReflectArrowJob()
    Raidboss.ReflectArrowT.windUp = Raidboss.ReflectArrowT.windUp - 1
    -- still in windup?
    if Raidboss.ReflectArrowT.windUp > 0 then
        local radiusDiff = Raidboss.ReflectArrowT.rangeStart -  Raidboss.ReflectArrowT.rangeFinish
        local scale = Raidboss.ReflectArrowT.windUp / Raidboss.ReflectArrowT.windUpMax
        local radius = Raidboss.ReflectArrowT.rangeFinish + scale*radiusDiff
        local angleStep = 360 / Raidboss.ReflectArrowT.count
        local sin, cos, myAngle
        local pos = GetPosition(Raidboss.eId)
        for i = 1, Raidboss.ReflectArrowT.count do
            myAngle = math.rad(i * angleStep + 360*scale)
            cos = math.cos(myAngle)
            sin = math.sin(myAngle)
            Logic.CreateEffect(GGL_Effects.FXDie, pos.X + radius*cos, pos.Y + radius*sin, 2)
        end
        return
    end
    -- if program arrives here: windUp completed
    -- here: first tick after windup
    if Raidboss.ReflectArrowT.reflectCounter == Raidboss.ReflectArrowT.reflectDuration then
        Raidboss.ReflectArrowActivateShield()
    end
    if math.mod(Raidboss.ReflectArrowT.reflectCounter, 10) == 0 then
        local angleStep = 360 / Raidboss.ReflectArrowT.count
        local sin, cos, myAngle
        local radius = Raidboss.ReflectArrowT.rangeFinish
        local pos = GetPosition(Raidboss.eId)
        for i = 1, Raidboss.ReflectArrowT.count do
            myAngle = math.rad(i * angleStep)
            cos = math.cos(myAngle)
            sin = math.sin(myAngle)
            Logic.CreateEffect(GGL_Effects.FXDieHero, pos.X + radius*cos, pos.Y + radius*sin, 2)
        end
    end
    Raidboss.ReflectArrowT.reflectCounter = Raidboss.ReflectArrowT.reflectCounter - 1
    if Raidboss.ReflectArrowT.reflectCounter <= 0 then
        Raidboss.ReflectArrowDeactivateShield()
        return true
    end
end ]]
function Raidboss.ReflectArrowActivateShield()
    Raidboss.ReflectArrowTrigger = Trigger.RequestTrigger(Events.LOGIC_EVENT_ENTITY_HURT_ENTITY, nil, "Raidboss_ReflectArrowOnHurt", 1)
end
function Raidboss_ReflectArrowOnHurt()
    if Event.GetEntityID2() ~= Raidboss.eId then return end
    local attacker = Event.GetEntityID1()
    --LuaDebugger.Log(attacker)
    if IsDead(attacker) then return end
    local leader = attacker
    if Logic.IsEntityInCategory( attacker, EntityCategories.Soldier) == 1 then
        leader = Logic.GetEntityScriptingValue(attacker, 69)
    end
    LuaDebugger.Log(leader)
    local dmg = 50
    local radius = 0
    for k,v in pairs(Raidboss.ReflectArrowLeaders) do
        if v == leader then
            local sPos = GetPosition(Raidboss.eId)
            local tPos = GetPosition(attacker)
            CppLogic.Effect.CreateProjectile( GGL_Effects.FXKalaArrow, sPos.X, sPos.Y, tPos.X, tPos.Y, dmg, radius, attacker, Raidboss.eId, GetPlayer(Raidboss.eId), nil, nil) 
            return
        end
    end
end
function Raidboss.ReflectArrowDeactivateShield()
    EndJob(Raidboss.ReflectArrowTrigger)
end


-- table concerning the attack schemes
-- attacks:
--  spawn adds
--  kill/bomb ranged attackers
--  meteor shower, multiple meteors spawn
Raidboss.AttackSchemes = {
    PoisonStrike = {
        -- determines the probability of using this attack next
        weight = 15,
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
        -- determines the probability of using this attack next
        weight = 5,
        -- the function that will be called if this function was selected
        callback = Raidboss.MeteorStrike,
        -- the system assumes that this is the duration of the attack, e.g. the next attack will be selected after this time
        duration = 10,
        -- parameters of the attack that will be used internally
        disallowRepeatedCasting = true,
        -- internal stuff
        chargeTime = 5,
        damage = 700,
        radius = 750
    },
    FearInducingStrike = {
        weight = 300,
        callback = Raidboss.FearStrike,
        duration = 16,
        disallowRepeatedCasting = true
    },
    ArmorShred = {
        weight = 300,
        callback = Raidboss.ArmorShred,
        duration = 2,
        disallowRepeatedCasting = true
    },
    ReflectArrows = {
        weight = 300,
        callback = Raidboss.ReflectArrow,
        duration = 15,
        disallowRepeatedCasting = true
    }
}