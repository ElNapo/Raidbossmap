MeteorSys = {}
MeteorSys.Meteors = {}
MeteorSys.InitialHeight = 400
function MeteorSys.Init()
    StartSimpleHiResJob("MeteorSys_HiResJob")
end
function MeteorSys.Add( _x, _y, _callback, _time)
    local mId = MeteorSys.SpawnBall( _x, _y)
    table.insert( MeteorSys.Meteors, {
        eId = mId,
        currHeight = MeteorSys.InitialHeight,
        flightTime = _time*10,
        fullTime = _time*10,
        callback = _callback
    })
end

function MeteorSys_HiResJob()
    local t, currHeight
    for i = table.getn(MeteorSys.Meteors), 1, -1 do
        t = MeteorSys.Meteors[i]
        t.flightTime = t.flightTime - 1
        currHeight = MeteorSys.InitialHeight*t.flightTime / t.fullTime
        if t.flightTime < 0 then
            t.callback()
            DestroyEntity(t.eId)
            table.remove( MeteorSys.Meteors, i)
        else
            S5Hook.GetEntityMem(t.eId)[76]:SetFloat(currHeight);
        end
    end
end
function MeteorSys.SpawnBall( _x, _y)
    local e = Logic.CreateEntity(Entities.CB_Camp23, _x, _y, 0, 8)
    Logic.SetModelAndAnimSet(e, Models.XD_CannonBall)
    S5Hook.GetEntityMem(e)[76]:SetFloat(MeteorSys.InitialHeight) -- height
    
    CUtil.SetEntityDisplayName(e, "")
    return e
end

