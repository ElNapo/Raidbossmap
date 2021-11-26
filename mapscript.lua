--------------------------------------------------------------------------------
-- MapName: XXX
--
-- Author: XXX
--
--------------------------------------------------------------------------------

-- Include main function
Script.Load( Folders.MapTools.."Main.lua" )
IncludeGlobals("MapEditorTools")

--++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
-- This function is called from main script to initialize the diplomacy states
function InitDiplomacy()
end


--++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
-- This function is called from main script to init all resources for player(s)
function InitResources()
end

--++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
-- This function is called to setup Technology states on mission start
function InitTechnologies()
end

--++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
-- This function is called on game start and after save game is loaded, setup your weather gfx
-- sets here
function InitWeatherGfxSets()
	SetupNormalWeatherGfxSet()
end

--++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
-- This function is called on game start you should setup your weather periods here
function InitWeather()
	AddPeriodicSummer(10)
end

--++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
-- This function is called on game start and after save game to initialize player colors
function InitPlayerColorMapping()
end
	
--++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
-- This function is called on game start after all initialization is done
function FirstMapAction()
	Tools.ExploreArea(1,1,900)
    Script.Load("maps\\user\\Raidbossmap\\main.lua")
    Script.Load("maps\\user\\Raidbossmap\\S5Hook.lua")
    Script.Load("maps\\user\\Raidbossmap\\MeteorSystem.lua")
    InstallS5Hook()
    Script.Load("maps\\user\\Raidbossmap\\SVFuncs.lua")
    SW.SV.Init()
    MeteorSys.Init()

    
    Raidboss.Init( GetEntityId("Kerberos"))
    Game.GameTimeSetFactor(5)
    SetHostile(1,2)
    local darioPos = GetPosition(65538)
    for i = 1, 12 do
        Tools.CreateGroup( 1, Entities.PU_LeaderBow4, 8, darioPos.X, darioPos.Y, 0)
        Tools.CreateGroup( 1, Entities.PU_LeaderSword4, 8, darioPos.X, darioPos.Y, 0)
    end
end
