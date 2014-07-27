-----------------------------------------------------------------------------------------------
-- Client Lua Script for Graph
-- Copyright (c) NCsoft. All rights reserved
-----------------------------------------------------------------------------------------------
 
require "Window"
 
-----------------------------------------------------------------------------------------------
-- Graph Module Definition
-----------------------------------------------------------------------------------------------
local Graph = {}
local fTimeSpan = 30
local fMedian = 5
local fUpdatesPerSecond = 3
 
-----------------------------------------------------------------------------------------------
-- Constants
-----------------------------------------------------------------------------------------------
-- e.g. local kiExampleVariableMax = 999
 
-----------------------------------------------------------------------------------------------
-- Initialization
-----------------------------------------------------------------------------------------------
function Graph:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self 

    -- initialize variables here
	self.tPixies = {}
	self.tHistory = {}
	self.bShowOptions = false

    return o
end

function Graph:Init()
	local bHasConfigureFunction = false
	local strConfigureButtonText = ""
	local tDependencies = {
		-- "UnitOrPackageName",
	}
    Apollo.RegisterAddon(self, bHasConfigureFunction, strConfigureButtonText, tDependencies)
end
 

-----------------------------------------------------------------------------------------------
-- Graph OnLoad
-----------------------------------------------------------------------------------------------
function Graph:OnLoad()
    -- load our form file
	self.xmlDoc = XmlDoc.CreateFromFile("Graph.xml")
	self.xmlDoc:RegisterCallback("OnDocLoaded", self)
end

-----------------------------------------------------------------------------------------------
-- Graph OnDocLoaded
-----------------------------------------------------------------------------------------------
function Graph:OnDocLoaded()

	if self.xmlDoc ~= nil and self.xmlDoc:IsLoaded() then
	    self.wndMain = Apollo.LoadForm(self.xmlDoc, "GraphForm", nil, self)
	    self.wndOptions = Apollo.LoadForm(self.xmlDoc, "Options", nil, self)
		if self.wndMain == nil then
			Apollo.AddAddonErrorText(self, "Could not load the main window for some reason.")
			return
		end
		
	    self.wndMain:Show(false, true)

		-- Register handlers for events, slash commands and timer, etc.
		-- e.g. Apollo.RegisterEventHandler("KeyDown", "OnKeyDown", self)
		Apollo.RegisterSlashCommand("graph", "OnGraphOn", self)
		
		Apollo.RegisterEventHandler("DamageOrHealingDone", "OnDamageOrHealingDone", self)
		Apollo.RegisterEventHandler("UnitEnteredCombat", "OnUnitEnteredCombat", self)
		Apollo.RegisterEventHandler("TargetThreatListUpdated", "OnTargetThreatListUpdated", self)
		Apollo.RegisterEventHandler("CombatLogDamage", "OnCombatLogDamage", self)
		Apollo.RegisterEventHandler("UnitTargetChanged", "OnUnitTargetChanged", self)

		self.timer = ApolloTimer.Create(1/fUpdatesPerSecond, true, "OnTimer", self)
		
		self:OnWindowSizeChanged(nil, nil)
		self:OnTimeSpanSliderBarChanged(nil, nil, fTimeSpan, 0)
		self:OnMedianSliderBarChanged(nil, nil, fMedian, 0)
		self:OnUpdatesSliderBarChanged(nil, nil, fUpdatesPerSecond, 0)

		-- Do additional Addon initialization here
	end
end

-----------------------------------------------------------------------------------------------
-- Graph Functions
-----------------------------------------------------------------------------------------------
-- Define general functions here

-- on SlashCommand "/graph"
function Graph:OnGraphOn()
	if self.wndMain:IsShown() then
		self.wndMain:Show(false)
		self.wndOptions:Show(false)
	else
		self.wndMain:Invoke() -- show the window
	end
end

function Graph:DrawGrid(wndCtrl, nHorizontal, nVertical, col, nLineMultiply)
	local width = wndCtrl:GetWidth()+1
	local height = wndCtrl:GetHeight()+1
	
	-- horizontal lines
	if nHorizontal and type(nHorizontal)=="number" and nHorizontal>1 then
		local fHorStep = width/nHorizontal
		local x = fHorStep
		
		while x<width do
			self:DrawLine(0, x, 0, x, height, 2, col)
			x = x + fHorStep
		end
	end
	
	-- vertical lines
	if nVertical and type(nVertical)=="number" and nVertical>1 then
		local fVerStep = height/nVertical
		local y = height
		
		local i = 0
		while y>0 do
			self:DrawLine(0, 0, y, width, y, 1, col, tostring(i*nLineMultiply))
			y = y - fVerStep
			i = i+1
		end
	end
end

-- on timer
function Graph:OnTimer()
	local fGameTime = GameLib.GetGameTime()
	local nDamage = 0
	local nMinDamage = nil
	local nMaxDamage = nil
	local fInterval = 1/fUpdatesPerSecond

	local tDpsHistory = {}
	local fEnd = math.max(fTimeSpan-fMedian, fMedian)
	local nLenHistory = #self.tHistory
	-- get dps history
	for fLow=0,fEnd,fInterval do
		local fHigh = fLow+fMedian
		-- get damage values from history
		for i=nLenHistory,1,-1 do
			local fTimeDiff = fGameTime - self.tHistory[i].fGameTime
			if self.tHistory[i].tUnitCaster.bIsSelf then
				local target = GameLib.GetPlayerUnit():GetTarget()
				if target then
					if self.tHistory[i].tUnitTarget.id==target:GetId() then
						-- median values
						if fTimeDiff>=fLow then
							if fTimeDiff<fHigh then
								nDamage = nDamage + self.tHistory[i].nDamageAmount
							else
								i=nLenHistory -- make sure we skip values we don't need 
								break;
							end
						else
							nLenHistory=i -- maybe +1
						end
					end
				else
					-- median values
					if fTimeDiff>=fLow then
						if fTimeDiff<fHigh then
							nDamage = nDamage + self.tHistory[i].nDamageAmount
						else
							i=nLenHistory -- make sure we skip values we don't need 
							break;
						end
					else
						nLenHistory=i -- maybe +1
					end
				end
				
			end
		end

		table.insert(tDpsHistory, nDamage)
		nMinDamage = nMinDamage and math.min(nMinDamage, nDamage) or nDamage
		nMaxDamage = nMaxDamage and math.max(nMaxDamage, nDamage) or nDamage
		nDamage = 0
	end
	
	nMinDamage = nMinDamage/fMedian
	nMaxDamage = (nMaxDamage/fMedian)*1.05
	
	local wndForm = self.wndMain:FindChild("Grid")
	local wndDPSText = self.wndMain:FindChild("DPSText")
	local width = wndForm:GetWidth()
	local height = wndForm:GetHeight()

	local fScale = nMaxDamage and (height/nMaxDamage) or 1
	local fUnit = (width/fEnd)*fInterval
	
	local fNum = nMaxDamage
	local nLineMultiply = 1
	while true do
		if fNum<10 then
			break
		end
		
		fNum = fNum/10
		nLineMultiply = nLineMultiply*10
	end
	
	wndForm:DestroyAllPixies()
	self:DrawGrid(wndForm, fTimeSpan, fNum, {a=0.2, r=0.5, g=1, b=1}, nLineMultiply)
	local x1,y1 = width, height
	for idx,nDmg in ipairs(tDpsHistory) do
		local x2 = math.floor(width-(idx-1)*fUnit)
		local y2 = math.max(0, math.floor(height-fScale*(nDmg/fMedian)))
		self:DrawLine(0, x1, y1, x2, y2, 2, {a=1, r=1, g=1, b=1})
		x1,y1 = x2,y2	
	end
	
	if tDpsHistory[1] then
		local target = GameLib.GetPlayerUnit():GetTarget()
		if target then
			wndDPSText:SetText(string.format("%s - %d dps", target:GetName(), tDpsHistory[1]/fMedian))
		else
			wndDPSText:SetText(string.format("Global - %d dps", tDpsHistory[1]/fMedian))
		end
	end
end

function Graph:DrawLine(nLayer, x1, y1, x2, y2, fWidth, col, strText)
	fWidth = fWidth or 2.0
	col = col or {a = 1, r = 1, g = 1, b = 1}
	local wndForm = self.wndMain:FindChild("Grid")
	local idPixie = wndForm:AddPixie({
		strText = strText,
		bLine = true,
		fWidth = fWidth,
		loc = {
			nOffsets = {x1, y1, x2, y2}
		},
		cr = col,
		flagsText = {
		    DT_RIGHT = true
		}
	})
	return idPixie
end


-----------------------------------------------------------------------------------------------
-- GraphForm Functions
-----------------------------------------------------------------------------------------------
-- when the OK button is clicked
function Graph:OnOK()
	self.wndMain:Close() -- hide the window
end

-- when the Cancel button is clicked
function Graph:OnCancel()
	self.wndMain:Close() -- hide the window
end

function Graph:OnDamageOrHealingDone(provider, receiver, n1, nDamage, nShielded, n3, bCritical, strSpell)
	local str = string.format("n1 = %s, nDamage = %s, n2 = %s, n3 = %s, b1 = %s, strSpell = %s",
		tostring(n1), tostring(nDamage), tostring(n2), tostring(n3), tostring(b1), tostring(strSpell))
	--Print(str)
end

function Graph:OnCombatLogDamage(tEventArgs)	
	local nGameTime = GameLib.GetGameTime()
	tEventArgs.fGameTime = GameLib.GetGameTime()
	tEventArgs.tUnitCaster = {
		id = tEventArgs.unitCaster:GetId(),
		strName = tEventArgs.unitCaster:GetName(),
		bIsSelf = (GameLib.GetPlayerUnit():GetId()==tEventArgs.unitCaster:GetId())
	}
	tEventArgs.tUnitTarget = {
		id = tEventArgs.unitTarget:GetId(),
		strName = tEventArgs.unitTarget:GetName(),
		bIsSelf = (GameLib.GetPlayerUnit():GetId()==tEventArgs.unitTarget:GetId())
	}
	
	table.insert(self.tHistory, tEventArgs)
	--Print("#self.tHistory = "..tostring(#self.tHistory))
	--[[tEventArgs.bTargetKilled
	tEventArgs.nOverkill
	tEventArgs.eEffectType
	tEventArgs.splCallingSpell
	tEventArgs.nDamageAmount
	tEventArgs.bPeriodic
	tEventArgs.unitCaster
	tEventArgs.nShield
	tEventArgs.nRawDamage
	tEventArgs.nAbsorption
	tEventArgs.bTargetVulnerable
	tEventArgs.unitTarget
	tEventArgs.eCombatResult]]--
end

function Graph:OnTargetThreatListUpdated(unit, nThreat)
end

function Graph:OnUnitEnteredCombat(unit, bEnteredCombat, strDesc)
end

function Graph:OnUnitTargetChanged(unit)
	local wndDPSText = self.wndMain:FindChild("DPSText")
	
	if unit then
		self.idUnitTarget = unit:GetId()
		self.strUnitTargetName = unit:GetName()
	end
end

function Graph:OnWindowSizeChanged(wndHandler, wndControl)
	local mainLeft, mainTop, mainRight, mainBottom = self.wndMain:GetAnchorOffsets()
	local width, height = self.wndOptions:GetWidth(), self.wndOptions:GetHeight()
	
	self.wndOptions:SetAnchorOffsets(mainRight, mainTop, mainRight+width, mainTop+height)
end

function Graph:OnOptionsButtonClicked()
	if self.wndOptions:IsShown() then
		self.wndOptions:Show(false)
	else
		self.wndOptions:Show(true)
	end
end

function Graph:OnTimeSpanSliderBarChanged(wndHandler, wndControl, fNewValue, fOldValue)
	fTimeSpan = math.floor(fNewValue)
	self.wndOptions:FindChild("TimeSpanValue"):SetText(tostring(fTimeSpan))
	self:OnTimer()
end

function Graph:OnMedianSliderBarChanged(wndHandler, wndControl, fNewValue, fOldValue)
	fMedian = math.floor(fNewValue)
	self.wndOptions:FindChild("MedianValue"):SetText(tostring(fMedian))
end

function Graph:OnUpdatesSliderBarChanged(wndHandler, wndControl, fNewValue, fOldValue)
	fUpdatesPerSecond = math.floor(fNewValue)
	self.wndOptions:FindChild("UpdatesValue"):SetText(tostring(fUpdatesPerSecond))
	self.timer:Set(1/fUpdatesPerSecond, true, "OnTimer", self)
end

---------------------------------------------------------------------------------------------------
-- Options Functions
---------------------------------------------------------------------------------------------------



-----------------------------------------------------------------------------------------------
-- Graph Instance
-----------------------------------------------------------------------------------------------
local GraphInst = Graph:new()
GraphInst:Init()
