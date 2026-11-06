-- GeistRemake
-- Hold a keybind: a 5x5 grid of action buttons pops up centered on the mouse.
-- Release the keybind: the grid hides.
--
-- Everything that happens on key press/release runs inside Blizzard's secure
-- (restricted) environment, so it keeps working in combat.

local ADDON_NAME = ...

local ROWS, COLS = 5, 5

-- Square outline color (soft gray) and opacity (0 = invisible, 1 = solid)
local OUTLINE_R, OUTLINE_G, OUTLINE_B = 0.6, 0.6, 0.6
local OUTLINE_ALPHA = 0.3
local NUM_BUTTONS = ROWS * COLS

local DEFAULTS = {
	startSlot = 145,  -- first action slot used; the grid uses startSlot .. startSlot+24
	scale = 1.0,
	buttonSize = 36,
	spacing = 4,
}

-- Keybinding labels shown in Options > Keybindings > AddOns
BINDING_HEADER_GEISTREMAKE = "GeistRemake"
_G["BINDING_NAME_CLICK GeistRemakeToggle:LeftButton"] = "Show Geist Grid (hold)"

local db
local anchor, grid, toggle, outlineLayer
local buttons = {}
local outlines = {}

local function Print(msg)
	print("|cff66ccffGeistRemake|r: " .. msg)
end

local function InCombat()
	return InCombatLockdown()
end

-- The default border art is slightly larger than the button and anchored to
-- its top-left, so it shows as a second line on the right and bottom edges.
local function StripArt(b)
	local normal = b.NormalTexture or b:GetNormalTexture()
	if normal then normal:SetAlpha(0) end
	if b.SlotBackground then b.SlotBackground:SetAlpha(0) end
	if b.SlotArt then b.SlotArt:SetAlpha(0) end
end

---------------------------------------------------------------------------
-- Cooldowns
--
-- In combat this client hides cooldown times from addons ("secret values").
-- Blizzard's button code may only pass them to SetCooldown when it runs
-- untainted, and on buttons an addon created it never is, so every cooldown
-- update on the grid threw "Secret values are only allowed during untainted
-- execution". We run Blizzard's handler protected so that can't error, then
-- draw the cooldown ourselves in a way the client allows.
---------------------------------------------------------------------------

local function IsSecret(v)
	return issecretvalue ~= nil and issecretvalue(v)
end

local function DrawCooldown(b)
	local cd = b.cooldown
	local slot = b.action or b:GetAttribute("action")
	if not (cd and slot) then return end

	-- Newer clients hand out a "duration object" that can carry hidden times
	-- straight to a cooldown frame.
	if C_ActionBar and C_ActionBar.GetActionCooldownDuration and cd.SetCooldownFromDurationObject then
		local ok, duration = pcall(C_ActionBar.GetActionCooldownDuration, slot)
		if ok and duration and pcall(cd.SetCooldownFromDurationObject, cd, duration) then
			return
		end
	end

	local start, duration, enable, modRate
	if GetActionCooldown then
		start, duration, enable, modRate = GetActionCooldown(slot)
	elseif C_ActionBar and C_ActionBar.GetActionCooldown then
		local info = C_ActionBar.GetActionCooldown(slot)
		if type(info) == "table" then
			start, duration, enable, modRate = info.startTime, info.duration, info.isEnabled, info.modRate
		end
	end
	-- Hidden by the game: leave the cooldown as it was rather than error.
	if start == nil or IsSecret(start) or IsSecret(duration) or IsSecret(enable) or IsSecret(modRate) then
		return
	end
	if duration and duration > 0 and enable ~= false and enable ~= 0 then
		cd:SetCooldown(start, duration, modRate or 1)
	else
		cd:Clear()
	end
end

-- Blizzard's event dispatcher calls button:OnEvent for every action bar event.
-- Only our own 25 buttons are changed; the default action bars are untouched.
local function ProtectCooldowns(b)
	local original = b.OnEvent
	if type(original) ~= "function" then return end
	local function OnEvent(self, event, ...)
		pcall(original, self, event, ...)
		DrawCooldown(self)
	end
	b.OnEvent = OnEvent
	if b:GetScript("OnEvent") then
		b:SetScript("OnEvent", OnEvent)
	end
end

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------

local function CreateFrames()
	-- Full-screen, click-through reference frame. The secure snippet reads the
	-- mouse position relative to this frame and anchors the grid to it.
	anchor = CreateFrame("Frame", "GeistRemakeAnchor", UIParent, "SecureFrameTemplate")
	anchor:SetAllPoints(UIParent)
	anchor:EnableMouse(false)

	-- The grid itself
	grid = CreateFrame("Frame", "GeistRemakeGrid", anchor, "SecureHandlerStateTemplate")
	grid:SetFrameStrata("DIALOG")
	grid:SetClampedToScreen(true)
	grid:SetPoint("CENTER", anchor, "CENTER")
	grid:Hide()

	-- Outlines sit on their own layer above the buttons and ignore the mouse
	outlineLayer = CreateFrame("Frame", nil, grid)
	outlineLayer:SetAllPoints(grid)
	outlineLayer:EnableMouse(false)

	for i = 1, NUM_BUTTONS do
		local b = CreateFrame("CheckButton", "GeistRemakeButton" .. i, grid, "ActionBarButtonTemplate")
		b:SetID(0) -- ID 0 => the button reads its slot from the "action" attribute
		if b.HotKey then
			b.HotKey:SetText("")
			b.HotKey:Hide()
		end
		-- Hide Blizzard's slot fill and border so only our outline shows. Blizzard
		-- re-applies this art when a button updates, so strip it again after
		-- every update.
		StripArt(b)
		for _, method in ipairs({ "Update", "UpdateButtonArt", "UpdateAction" }) do
			if type(b[method]) == "function" then
				hooksecurefunc(b, method, StripArt)
			end
		end
		ProtectCooldowns(b)
		buttons[i] = b

		-- Square outline drawn as four 1px edges
		-- Each edge stops 2px short of the corner, and one pixel set in diagonally
		-- joins them, giving a slightly rounded corner.
		local cell = CreateFrame("Frame", nil, outlineLayer)
		local function Px()
			local t = cell:CreateTexture(nil, "OVERLAY")
			t:SetColorTexture(OUTLINE_R, OUTLINE_G, OUTLINE_B, OUTLINE_ALPHA)
			return t
		end
		local top, bottom, left, right = Px(), Px(), Px(), Px()
		top:SetPoint("TOPLEFT", 2, 0); top:SetPoint("TOPRIGHT", -2, 0); top:SetHeight(1)
		bottom:SetPoint("BOTTOMLEFT", 2, 0); bottom:SetPoint("BOTTOMRIGHT", -2, 0); bottom:SetHeight(1)
		left:SetPoint("TOPLEFT", 0, -2); left:SetPoint("BOTTOMLEFT", 0, 2); left:SetWidth(1)
		right:SetPoint("TOPRIGHT", 0, -2); right:SetPoint("BOTTOMRIGHT", 0, 2); right:SetWidth(1)
		for _, c in ipairs({ { "TOPLEFT", 1, -1 }, { "TOPRIGHT", -1, -1 },
		                     { "BOTTOMLEFT", 1, 1 }, { "BOTTOMRIGHT", -1, 1 } }) do
			local dot = Px()
			dot:SetSize(1, 1)
			dot:SetPoint(c[1], c[2], c[3])
		end
		outlines[i] = cell
	end
	outlineLayer:SetFrameLevel(buttons[NUM_BUTTONS]:GetFrameLevel() + 5)

	-- The button the keybind "clicks". It fires on key down AND key up.
	toggle = CreateFrame("Button", "GeistRemakeToggle", UIParent, "SecureHandlerClickTemplate")
	toggle:RegisterForClicks("AnyDown", "AnyUp")
	toggle:SetSize(1, 1)
	toggle:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10, 10) -- off-screen
	toggle:SetFrameRef("grid", grid)
	toggle:SetFrameRef("anchor", anchor)
	toggle:SetAttribute("_onclick", [[
		local grid = self:GetFrameRef("grid")
		local anchor = self:GetFrameRef("anchor")
		if down then
			local x, y = anchor:GetMousePosition()
			if x and y then
				local s = grid:GetScale()
				grid:ClearAllPoints()
				grid:SetPoint("CENTER", anchor, "BOTTOMLEFT",
					x * anchor:GetWidth() / s, y * anchor:GetHeight() / s)
			end
			grid:Show()
		elseif not self:GetAttribute("pinned") then
			grid:Hide()
		end
	]])
end

-- Assign action slots and lay buttons out. Only allowed out of combat.
local function ApplySettings()
	if InCombat() then
		Print("Can't change settings in combat.")
		return false
	end

	local size, gap = db.buttonSize, db.spacing
	local total = COLS * size + (COLS - 1) * gap
	grid:SetSize(total, total)
	grid:SetScale(db.scale)

	for i, b in ipairs(buttons) do
		local row = math.floor((i - 1) / COLS)
		local col = (i - 1) % COLS
		local cx = col * (size + gap) + size / 2
		local cy = -(row * (size + gap) + size / 2)

		-- The Blizzard button art has a fixed size, so resizing the frame leaves the
		-- icon small and stuck in the corner. Keep the native size and scale it
		-- instead, centered in its square.
		local native = b:GetWidth()
		if not native or native <= 0 then native = 45 end
		local s = size / native
		b:SetScale(s)
		b:ClearAllPoints()
		b:SetPoint("CENTER", grid, "TOPLEFT", cx / s, cy / s)

		local o = outlines[i]
		o:ClearAllPoints()
		o:SetSize(size, size)
		o:SetPoint("CENTER", grid, "TOPLEFT", cx, cy)

		b:SetAttribute("action", db.startSlot + i - 1)
		if b.UpdateAction then
			b:UpdateAction(true)
		elseif ActionButton_UpdateAction then
			ActionButton_UpdateAction(b, true)
		end

		-- Always show empty slots so spells can be dragged onto them
		if b.ShowGrid then
			b:ShowGrid(ACTION_BUTTON_SHOW_GRID_REASON_CVAR or 1)
		else
			b:SetAttribute("showgrid", 1)
		end
		b:Show()
	end
	return true
end

local function SetPinned(pinned)
	if InCombat() then
		Print("Can't do that in combat.")
		return
	end
	toggle:SetAttribute("pinned", pinned or nil)
	if pinned then
		grid:ClearAllPoints()
		grid:SetPoint("CENTER", anchor, "CENTER")
		grid:Show()
		Print("Grid pinned open. Drag spells, items, or macros onto it, then type /geist hide.")
	else
		grid:Hide()
	end
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

local function PrintHelp()
	Print("commands:")
	print("  /geist show  - keep the grid open so you can drag spells onto it")
	print("  /geist hide  - close the grid")
	print(("  /geist slot <n>  - first action slot to use (now %d, uses %d-%d)")
		:format(db.startSlot, db.startSlot, db.startSlot + NUM_BUTTONS - 1))
	print(("  /geist scale <n> - grid scale, e.g. 0.8 or 1.2 (now %.2f)"):format(db.scale))
	print("  /geist reset - restore default settings")
	print("Set the keybind under Options > Keybindings > AddOns > GeistRemake.")
end

SLASH_GEISTREMAKE1 = "/geist"
SLASH_GEISTREMAKE2 = "/geistremake"
SlashCmdList.GEISTREMAKE = function(msg)
	local cmd, arg = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")

	if cmd == "show" then
		SetPinned(true)
	elseif cmd == "hide" then
		SetPinned(false)
	elseif cmd == "slot" then
		local n = tonumber(arg)
		if not n or n < 1 or n + NUM_BUTTONS - 1 > 180 then
			Print("Slot must be a number from 1 to " .. (180 - NUM_BUTTONS + 1) .. ".")
			return
		end
		local old = db.startSlot
		db.startSlot = math.floor(n)
		if ApplySettings() then
			Print(("Grid now uses action slots %d-%d."):format(db.startSlot, db.startSlot + NUM_BUTTONS - 1))
		else
			db.startSlot = old
		end
	elseif cmd == "scale" then
		local n = tonumber(arg)
		if not n or n < 0.3 or n > 3 then
			Print("Scale must be between 0.3 and 3.")
			return
		end
		local old = db.scale
		db.scale = n
		if not ApplySettings() then db.scale = old end
	elseif cmd == "reset" then
		for k, v in pairs(DEFAULTS) do db[k] = v end
		if ApplySettings() then Print("Settings reset.") end
	else
		PrintHelp()
	end
end

---------------------------------------------------------------------------
-- Init
---------------------------------------------------------------------------

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, name)
	if name ~= ADDON_NAME then return end
	self:UnregisterEvent("ADDON_LOADED")

	GeistRemakeDB = GeistRemakeDB or {}
	db = GeistRemakeDB
	for k, v in pairs(DEFAULTS) do
		if db[k] == nil then db[k] = v end
	end

	CreateFrames()
	if InCombat() then
		-- e.g. /reload mid-fight: finish setup once combat ends
		self:RegisterEvent("PLAYER_REGEN_ENABLED")
		self:SetScript("OnEvent", function(f)
			f:UnregisterEvent("PLAYER_REGEN_ENABLED")
			ApplySettings()
		end)
	else
		ApplySettings()
	end
end)
