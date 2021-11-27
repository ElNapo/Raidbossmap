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
    [EntityCategories.Hero] = 1,
    [EntityCategories.Rifle] = 1,
    [EntityCategories.Spear] = 1,
    [EntityCategories.Sword] = 1
}
Raidboss.PlayerMultiplier = {}
Raidboss.PlayerFlatDamage = {}
-- multiplier if no appropriate ECategory was found
Raidboss.FallbackMultiplier = 0.1

Raidboss.CombatRange = 3000
Raidboss.MaxHealth = 100000
Raidboss.Armor = 0
Raidboss.Damage = 100
Raidboss.AttackRange = 800
Raidboss.MovementSpeed = 800
Raidboss.Scale = 4
Raidboss.LastHitTime = 0
Raidboss.Regen = 100

function Raidboss.Init( _eId, _pId)
    if SendEvent then CSendEvent = SendEvent end
    -- get control over framework on game closed
    Framework_CloseGame_Orig = Framework.CloseGame
    Framework.CloseGame = function()
        SW.SV.GreatReset()
        Framework_CloseGame_Orig()
    end
    Raidboss.ApplyKerbeConfigChanges()
    Raidboss.Origin = GetPosition( _eId)
    Raidboss.pId = GetPlayer(_eId)

    -- force respawn to enforce xml changes
    DestroyEntity(_eId)
    Raidboss.eId = Logic.CreateEntity(Entities.CU_BlackKnight, Raidboss.Origin.X, Raidboss.Origin.Y, 0, Raidboss.pId)
    -- MS and scale
    S5Hook.GetEntityMem( Raidboss.eId)[31][1][5]:SetFloat( Raidboss.MovementSpeed)
    S5Hook.GetEntityMem( Raidboss.eId)[25]:SetFloat( Raidboss.Scale)
    
    
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
        stoneId = Logic.CreateEntity( Entities.XD_ScriptEntity, Raidboss.Origin.X + dx, Raidboss.Origin.Y + dy, i*5+90, Raidboss.pId)
        Logic.SetEntityScriptingValue( stoneId, -30, 65793)
        Logic.SetModelAndAnimSet( stoneId, Models.Banners_XB_StandarteOccupied)
    end

    -- setup damage system
    Raidboss.HurtTrigger = Trigger.RequestTrigger(Events.LOGIC_EVENT_ENTITY_HURT_ENTITY, nil, "Raidboss_OnHit", 1)
    Raidboss.DamageTracker = {}
    for i = 0, 16 do
        Raidboss.DamageTracker[i] = 0
        Raidboss.PlayerMultiplier[i] = 1
        Raidboss.PlayerFlatDamage[i] = 0
    end
    StartSimpleJob("Raidboss_ControlKerbe")

end

function Raidboss_ControlKerbe()
    local posKerbe = GetPosition(Raidboss.eId)
    -- if kerberos is in his arena? no need to do smth
    if Raidboss.GetDistanceSq( posKerbe, Raidboss.Origin) < 2700*2700 then return end
    
    local pOrigin = Raidboss.Origin
    local listOfValidTargets = S5Hook.EntityIteratorTableize(Predicate.InCircle(pOrigin.X, pOrigin.Y, 2500), Predicate.OfCategory(EntityCategories.Military), Predicate.IsNotSoldier())

    local myTargetHero, myTargetMelee, myTargetRanged
    local eId
    for i = 1, table.getn(listOfValidTargets) do
        eId = listOfValidTargets[i]
        if eId == Raidboss.eId then -- do nothing here, DONT ATTACK YOURSELF
        elseif Logic.IsEntityInCategory( eId, EntityCategories.Hero) == 1 then
            myTargetHero = myTargetHero or eId
        elseif Logic.IsEntityInCategory( eId, EntityCategories.LongRange) == 1 then
            myTargetMelee = myTargetMelee or eId
        elseif Logic.IsEntityInCategory( eId, EntityCategories.Melee) == 1 then
            myTargetRanged = myTargetRanged or eId
        end
    end
    --LuaDebugger.Log(myTargetHero)
    --LuaDebugger.Log(myTargetMelee)
    --LuaDebugger.Log(myTargetRanged)
    if myTargetHero ~= nil then
        Logic.GroupAttack( Raidboss.eId, myTargetHero)
    elseif myTargetMelee ~= nil then
        Logic.GroupAttack( Raidboss.eId, myTargetMelee)
    elseif myTargetRanged ~= nil then
        Logic.GroupAttack( Raidboss.eId, myTargetRanged)
    else
        Logic.MoveSettler( Raidboss.eId, pOrigin.X, pOrigin.Y)
    end
    -- idle? lauf zurück zu faules stück
    if Logic.GetCurrentTaskList(Raidboss.eId) == "TL_MILITARY_IDLE" then 
        Logic.MoveSettler( Raidboss.eId, pOrigin.X, pOrigin.Y)
    end
    -- nicht im kampf? regeneriere dich
    if not Raidboss.InCombat then
        local curHealth = Logic.GetEntityHealth( Raidboss.eId)
        local maxHealth = Logic.GetEntityMaxHealth( Raidboss.eId)
        local toHeal = math.min( maxHealth - curHealth, Raidboss.Regen)
    end
end
function Raidboss.ApplyKerbeConfigChanges()
    -- armor and max health
    SW.SetSettlerMaxHealth( Entities.CU_BlackKnight, Raidboss.MaxHealth)
    SW.SetSettlerArmor( Entities.CU_BlackKnight, Raidboss.Armor)

    -- changes to the fear
    SW.SetHeroFearRecharge( Entities.CU_BlackKnight, 0)
    SW.SetHeroFearDuration( Entities.CU_BlackKnight, 20)
    SW.SetHeroFearFlightDistance( Entities.CU_BlackKnight, 3000)
    SW.SetHeroFearRange( Entities.CU_BlackKnight, 800)

    -- changes to the aura
    SW.SetHeroAuraRecharge( Entities.CU_BlackKnight, 0)
    SW.SetHeroAuraRange( Entities.CU_BlackKnight, 3000)
    SW.SetHeroAuraDuration( Entities.CU_BlackKnight, 15)
    SW.SetHeroAuraArmorMultiplier( Entities.CU_BlackKnight, -100)

    -- regen, attack range and attack damage
    SW.SetLeaderDamage( Entities.CU_BlackKnight, Raidboss.Damage)
    SW.SetLeaderMaxRange( Entities.CU_BlackKnight, Raidboss.AttackRange)
    SW.SetLeaderRegen( Entities.CU_BlackKnight, 0)

    -- changes to the bomb
    SW.SetBombDamage( Entities.XD_Bomb1, 300)
    SW.SetBombRange( Entities.XD_Bomb1, 600)
end

function Raidboss_OnHit()
    local attacker = Event.GetEntityID1()
    local attacked = Event.GetEntityID2()
    if attacker == Raidboss.eId then
        Raidboss.InCombat = true
        Raidboss.LastHitTime = Logic.GetTime()
        Raidboss.OnKerbeDealsDamage( attacked)
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
function Raidboss.OnKerbeDealsDamage( _victimId)
    -- only consider valid victims
    if IsDead(_victimId) then return end
    -- manipulate damage iff target is melee
    if Logic.IsEntityInCategory( _victimId, EntityCategories.Melee) == 0 then return end
    
    -- get armor of obj
    local armor = Logic.GetEntityArmor( _victimId)
    local rawDamage = CEntity.TriggerGetDamage()
    local multiplier = math.min(math.max(1 - armor / 14, 0), 1)
    --LuaDebugger.Log(multiplier)

    -- set damage of trigger
    CEntity.TriggerSetDamage(math.ceil(rawDamage * multiplier))
end
function Raidboss.ManipulateTrigger( _attackerId)
    -- local rawDamage = CEntity.TriggerGetDamage()
    local rawDamage = Logic.GetEntityDamage( _attackerId)
    local factor = Raidboss.FallbackMultiplier
    local factor2 = Raidboss.PlayerMultiplier[GetPlayer(_attackerId)]
    local flatDamage = Raidboss.PlayerFlatDamage[GetPlayer(_attackerId)]
    for k,v in pairs(Raidboss.DamageMultipliers) do
        if Logic.IsEntityInCategory( _attackerId, k) == 1 then
            --LuaDebugger.Log("Attacker has ECategory"..k)
            factor = v
            break
        end
    end
    local newDamage = math.floor(rawDamage*factor*factor2 + flatDamage)
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
            --LuaDebugger.Log("Selected "..attackName)
            Raidboss.ExecuteAttack( attackName)
        end
    end
end
function Raidboss.ExecuteAttack( _attackName)
    local myAttack = Raidboss.AttackSchemes[_attackName]
    local  t = Raidboss.AttackScheduler
    t.lastAttack = _attackName
    t.timeToNextAttack = myAttack.duration
    local targetPos = Raidboss.FindNiceTarget()
    --LuaDebugger.Log(targetPos)
    myAttack.callback( myAttack, targetPos)
end
Raidboss.MaxSoundRange = 7500
function Raidboss.PlaySound( _soundId, _pos)
    local x,y = GUI.Debug_GetMapPositionUnderMouse()
    local dis = math.sqrt(Raidboss.GetDistanceSq( _pos, {X = x, Y = y}))
    local factor = math.min(dis/Raidboss.MaxSoundRange, 1)
    Sound.PlayGUISound( _soundId, 100 * (1-factor))
end

function Raidboss.DistanceEval( disSq)
    return math.exp( -disSq / 1000000)
end
function Raidboss.FindNiceTarget()
    local pos = GetPosition(Raidboss.eId)
    local leaders = S5Hook.EntityIteratorTableize( Predicate.InCircle( pos.X, pos.Y, 3000), Predicate.OfCategory(EntityCategories.Leader))
    local n = table.getn(leaders)
    if n == 0 then
        return pos
    end
    local posis = {}
    for i = 1, n do
        table.insert( posis, GetPosition(leaders[i]))
    end
    local evals = {}
    for i = 1, n do
        local evaluation = 0
        for j = 1, n do
            evaluation = evaluation + Raidboss.DistanceEval(Raidboss.GetDistanceSq(posis[i], posis[j]))
        end
        table.insert( evals, evaluation)
    end
    local highestValue = -1
    local highestIndex = -1
    for i = 1, n do
        if highestValue < evals[i] then
            highestValue = evals[i]
            highestIndex = i
        end
    end
    if highestIndex == -1 then
        return pos
    else
        return posis[highestIndex]
    end
end


function Raidboss.MeteorStrike( _schemeTable, _targetPos)
    Raidboss.PlaySound( Sounds.Military_SO_CannonTowerFire_rnd_1, _targetPos)
    --local rX, rY
    local spread = _schemeTable.randomSpread
    local timeSpread = 2
    local dmg = _schemeTable.damage
    local range = _schemeTable.radius
    for i = 1, _schemeTable.numMeteors do
        local rX = math.random(-spread, spread)
        local rY = math.random(-spread, spread)
        MeteorSys.Add( _targetPos.X + rX, _targetPos.Y + rY, function()
            if not IsDead(Raidboss.eId) then
                CEntity.DealDamageInArea( Raidboss.eId, _targetPos.X + rX, _targetPos.Y + rY, range, dmg)
            end
            Logic.CreateEffect( GGL_Effects.FXExplosionShrapnel,  _targetPos.X + rX, _targetPos.Y + rY, 0)
        end, 6 + math.random(-timeSpread*5, timeSpread*5)/5)
        Logic.CreateEffect(GGL_Effects.FXSalimHeal, _targetPos.X + rX, _targetPos.Y + rY, 0)
    end
end
function Raidboss.FearStrike( _schemeTable, _targetPos)
    StartSimpleJob("Raidboss_FearStrike")
    Raidboss.FearStrikeCounter = _schemeTable.windUp
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
        r = Raidboss.FearStrikeCounter * 800 / Raidboss.AttackSchemes.FearInducingStrike.windUp
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
    Raidboss.ReflectArrowCounter = _schemeTable.windUp*10+1
    Raidboss.PlaySound( Sounds.Coiner01, pos)
    Raidboss.ReflectArrowLeaders = leaders
end
function Raidboss_ReflectArrow_Job()
    Raidboss.ReflectArrowCounter = Raidboss.ReflectArrowCounter - 1
    local windUp = Raidboss.AttackSchemes.ReflectArrows.windUp
    if math.mod(Raidboss.ReflectArrowCounter, windUp) == 0 then
        local myIndex = Raidboss.ReflectArrowCounter / windUp
        if myIndex > 0 then
            Raidboss.PlaySound( Sounds["Misc_Countdown"..myIndex], GetPosition(Raidboss.eId))
        end
    end
    if Raidboss.ReflectArrowCounter <= 0 then
        Raidboss.ReflectArrowActivateShield()
        StartSimpleJob("Raidboss_ReflectArrow_Job2")
        Raidboss.ReflectArrowCounter = Raidboss.AttackSchemes.ReflectArrows.curseDuration
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
    if Counter.Tick2("Raidboss_ReflectArrow", 2) then
        for k,v in pairs(Raidboss.ReflectArrowLeaders) do
            if not IsDead(v) then
                pos = GetPosition(v)
                Logic.CreateEffect(GGL_Effects.FXMaryDemoralize, pos.X, pos.Y, 0)
            end
        end
    end
end
function Raidboss.ReflectArrowActivateShield()
    Raidboss.ReflectArrowTrigger = Trigger.RequestTrigger(Events.LOGIC_EVENT_ENTITY_HURT_ENTITY, nil, "Raidboss_ReflectArrowOnHurt", 1)
end
function Raidboss_ReflectArrowOnHurt()
    if Event.GetEntityID2() ~= Raidboss.eId then return end
    local attacker = Event.GetEntityID1()
    if IsDead(attacker) then return end
    local leader = attacker
    if Logic.IsEntityInCategory( attacker, EntityCategories.Soldier) == 1 then
        leader = Logic.GetEntityScriptingValue(attacker, 69)
    end

    local dmg = Raidboss.AttackSchemes.ReflectArrows.damage
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
function Raidboss.SummonAdds( _schemeTable, _targetPos) --TODO
end
function Raidboss.SummonBomb( _schemeTable, _targetPos)
    local bombId = Logic.CreateEntity(Entities.XD_Bomb1, _targetPos.X, _targetPos.Y, 0, Raidboss.pId)
	if bombId == 0 then return end
    Raidboss.PlaySound( Sounds.VoicesHero2_HERO2_PlaceBomb_rnd_01, _targetPos)
	S5Hook.GetEntityMem(bombId)[31][0][4]:SetInt(_schemeTable.explosionTime*10) --wait 8 seconds
	S5Hook.GetEntityMem(bombId)[25]:SetFloat(8)
end
function Raidboss.MeteorRain( _schemeTable, _targetPos)
    -- idea for trajectory:
    -- map space around kerberos in polar coordinates, spawn at time t a ball at position
    --  (p(t), t*omega)
    -- p(t) = sum_{j=1}^6 w_j * (0.5*sin(j * 2pi / duration * t)+0.5)
    -- omega = 4 pi / duration
    _schemeTable.omega = 2 * _schemeTable.numRotations * math.pi / _schemeTable.duration 
    local weights = {}
    local sumOfWeights = 0
    _schemeTable.phaseShifts = {}
    for i = 1, 6 do
        weights[i] = math.random()
        sumOfWeights = sumOfWeights + weights[i]
        _schemeTable.phaseShifts[i] = 2*math.pi*math.random()
    end
    -- apply to rescaling
    for i = 1, 6 do
        weights[i] = weights[i] / sumOfWeights * _schemeTable.range
    end

    _schemeTable.weights = weights
    _schemeTable.p = function(t)
        local ret = 0
        local rad = 2*math.pi / _schemeTable.duration * t
        for j = 1, 6 do
            ret = ret + _schemeTable.weights[j]*(0.5 + 0.5*math.sin(rad*j + _schemeTable.phaseShifts[j]))
        end
        return ret
    end
    _schemeTable.internalTicker = 0
    StartSimpleHiResJob("Raidboss_MeteorRainJob")
end
function Raidboss_MeteorRainJob()
    --if not Counter.Tick2("MeteorRain", 2) then return end
    local t = Raidboss.AttackSchemes.MeteorRain
    t.internalTicker = t.internalTicker + 0.1

    if t.internalTicker > t.duration then return true end 

    local angle = t.internalTicker * t.omega
    local radius = t.p(t.internalTicker)
    local pos = GetPosition(Raidboss.eId)
    
    local x = pos.X + radius*math.sin(angle)
    local y = pos.Y + radius*math.cos(angle)
    local range = Raidboss.AttackSchemes.MeteorRain.damageRange
    local dmg = Raidboss.AttackSchemes.MeteorRain.damage
    MeteorSys.Add( x, y, function()
        if not IsDead(Raidboss.eId) then
            CEntity.DealDamageInArea( Raidboss.eId, x, y, range, dmg)
        end
        Logic.CreateEffect( GGL_Effects.FXExplosionShrapnel, x, y, 0)
    end, 6)
    Logic.CreateEffect(GGL_Effects.FXSalimHeal, x, y, 0)
    Raidboss.PlaySound(Sounds.Military_SO_CannonTowerFire_rnd_1, {X = x, Y = y})
end

-- table concerning the attack schemes
-- attacks:
--  spawn adds
--  meteor shower, multiple meteors spawn
Raidboss.AttackSchemes = {
    MeteorStrike = {
        -- determines the probability of using this attack next
        weight = 35,
        -- the function that will be called if this function was selected
        callback = Raidboss.MeteorStrike,
        -- the system assumes that this is the duration of the attack, e.g. the next attack will be selected after this time
        duration = 10,
        -- parameters of the attack that will be used internally
        disallowRepeatedCasting = true,
        -- internal stuff
        randomSpread = 500, -- meteors can spawn at x plusminus randomSpread, same in y direction
        damage = 100, -- damage of each meteor
        radius = 350, -- damage radius of each meteor
        numMeteors = 10 -- number of meteors spawned
    },
    FearInducingStrike = {
        weight = 15,
        callback = Raidboss.FearStrike,
        duration = 16,
        disallowRepeatedCasting = true,
        windUp = 8 -- wind up time for the fear in seconds
    },
    ArmorShred = {
        weight = 15,
        callback = Raidboss.ArmorShred,
        duration = 2,
        disallowRepeatedCasting = true
    },
    ReflectArrows = {
        weight = 15,
        callback = Raidboss.ReflectArrow,
        duration = 15,
        disallowRepeatedCasting = true,
        windUp = 4, -- wind up time for the curse, HAS TO BE INT
        curseDuration = 8, -- duration of the curse
        damage = 75 -- damage per reflected arrow
    },
    SummonAdds = { -- not implemented, LOL
        weight = 0,
        callback = Raidboss.SummonAdds,
        duration = 5,
        disallowRepeatedCasting = true
    },
    SummonBomb = { -- if you wish to change damage / radius, use SW.SetBombDamage/SW.SetBombRange
        weight = 15,
        callback = Raidboss.SummonBomb,
        duration = 3,
        disallowRepeatedCasting = true,
        explosionTime = 8 -- time in seconds until it explodes
    },
    MeteorRain = {
        weight = 5,
        callback = Raidboss.MeteorRain,
        duration = 10,
        disallowRepeatedCasting = true,
        numRotations = 2, -- the rain goes this number of full circles around kerberos
        range = 4500, -- the theoretical maximum distance of meteor to kerberos, mean distance is half of this
        damageRange = 250, -- aoe range of the meteor impact
        damage = 250 -- damage of each meteor
    }
}