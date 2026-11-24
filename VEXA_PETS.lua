--[[
================================================================================
    V  E  X  A  P  E  T  S
================================================================================
  VEXA PETS  -  v1.0.0  -  single-file UI framework for Roblox automation
--------------------------------------------------------------------------------
  FEATURES
    - Animated loading screen with staged progress
    - Dashboard with live stats and an activity feed
    - CanvasGroup page cross-fades, tween-driven toggles / sliders / buttons
    - Draggable, minimise-to-pill, mobile + touch compatible
    - Toast notification system, live FPS / ping readout
    - Module runtime with per-tick sandboxing (pcall) and auto-disable on error
    - Built-in DEMO adapter so every module runs end to end out of the box
    - Graceful unload: disconnects every loop and removes all GUI
--------------------------------------------------------------------------------
  IMPORTANT - READ THIS
  A local, simulated demo adapter is installed by default. It drives every
  module with fake data so the dashboard and all controls can be exercised.
  Turn it off in Settings > Demo mode before supplying your own handlers.

  The game-specific actions (growing pets, claiming cash, using potions,
  hatching eggs) talk to the game through the adapter table below:

      PetFarmStart   / PetFarmTick   / PetFarmStop
      MoneyStart     / MoneyTick     / MoneyStop
      AgeUpStart     / AgeUpTick     / AgeUpStop
      EggStart       / EggTick       / EggStop

  A module's Tick receives (deltaTime, module) and must not yield.
  If a key is missing the toggle politely refuses and reports which key it
  wanted instead of failing silently.

  Usage:   loadstring(game:HttpGet("<url>"))()
  Unload:  _G.VEXA:Destroy()      or the Unload button in Settings
  Toggle:  RightShift (configurable)
================================================================================
]]

--==============================================================================
-- 01 -- SERVICES
--==============================================================================

local Players          = game:GetService("Players")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService       = game:GetService("RunService")
local Stats            = game:GetService("Stats")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
	Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
	LocalPlayer = Players.LocalPlayer
end

-- Wipe any previous instance so re-execution is always safe.
if _G.VEXA and type(_G.VEXA) == "table" and _G.VEXA.Destroy then
	pcall(function()
		_G.VEXA:Destroy()
	end)
	_G.VEXA = nil
end

--==============================================================================
-- 02 -- THEME
--==============================================================================

local Theme = {
	Bg        = Color3.fromRGB(13, 13, 19),
	Surface   = Color3.fromRGB(20, 20, 29),
	Surface2  = Color3.fromRGB(28, 28, 41),
	Surface3  = Color3.fromRGB(36, 36, 53),
	Stroke    = Color3.fromRGB(52, 52, 74),
	Accent    = Color3.fromRGB(140, 92, 246),
	Accent2   = Color3.fromRGB(56, 189, 248),
	Text      = Color3.fromRGB(237, 239, 248),
	TextDim   = Color3.fromRGB(142, 148, 170),
	TextFaint = Color3.fromRGB(100, 105, 128),
	Success   = Color3.fromRGB(52, 211, 153),
	Danger    = Color3.fromRGB(248, 113, 113),
	Warn      = Color3.fromRGB(250, 191, 60),
	Font      = Enum.Font.Gotham,
	FontMed   = Enum.Font.GothamMedium,
	FontBold  = Enum.Font.GothamBold,
	FontBlack = Enum.Font.GothamBlack,
}

local WHITE = Color3.fromRGB(255, 255, 255)

--==============================================================================
-- 03 -- HELPERS
--==============================================================================

local connections = {}

local function bind(signal, fn)
	local conn = signal:Connect(fn)
	connections[#connections + 1] = conn
	return conn
end

local function create(class, props)
	local inst = Instance.new(class)
	local parent

	for key, value in next, props do
		if key == "Parent" then
			parent = value
		else
			inst[key] = value
		end
	end

	if parent then
		inst.Parent = parent
	end

	return inst
end

local function tween(inst, goal, duration, style, direction)
	local info = TweenInfo.new(
		duration or 0.25,
		style or Enum.EasingStyle.Quint,
		direction or Enum.EasingDirection.Out
	)
	local t = TweenService:Create(inst, info, goal)
	t:Play()
	return t
end

local function corner(inst, radius)
	return create("UICorner", {
		CornerRadius = UDim.new(0, radius or 8),
		Parent = inst,
	})
end

local function stroke(inst, color, thickness, transparency)
	return create("UIStroke", {
		Color = color or Theme.Stroke,
		Thickness = thickness or 1,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = inst,
	})
end

local function pad(inst, top, bottom, left, right)
	return create("UIPadding", {
		PaddingTop = UDim.new(0, top or 0),
		PaddingBottom = UDim.new(0, bottom or top or 0),
		PaddingLeft = UDim.new(0, left or top or 0),
		PaddingRight = UDim.new(0, right or left or top or 0),
		Parent = inst,
	})
end

local function vlist(inst, spacing, align)
	local layout = create("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, spacing or 8),
		Parent = inst,
	})
	if align then
		layout.VerticalAlignment = align
	end
	return layout
end

local function label(parent, props)
	local base = {
		BackgroundTransparency = 1,
		Font = Theme.Font,
		TextSize = 13,
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		RichText = false,
	}
	for key, value in next, props do
		base[key] = value
	end
	return create("TextLabel", base)
end

local function getGuiParent()
	local ok, hui = pcall(function()
		if gethui then
			return gethui()
		end
		return nil
	end)
	if ok and hui then
		return hui
	end

	local ok2, coreGui = pcall(function()
		return game:GetService("CoreGui")
	end)
	if ok2 and coreGui then
		return coreGui
	end

	return LocalPlayer:WaitForChild("PlayerGui")
end

--==============================================================================
-- 04 -- SCREEN GUI
--==============================================================================

local screenGui = create("ScreenGui", {
	Name = "VEXA_PETS",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 9999,
})

do
	local ok = pcall(function()
		screenGui.Parent = getGuiParent()
	end)
	if not ok then
		screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
	end
end

--==============================================================================
-- 05 -- PUBLIC API + STATE
--==============================================================================

local Vexa = {}
Vexa.Version = "1.0.0"
Vexa.Adapter = {}
Vexa.Config = {
	notifications = true,
	tickInterval = 0.1,
	toggleKey = Enum.KeyCode.RightShift,
	autoEquip = true,
	petMode = "level",
	targetPet = "all",
	actionDelay = 1,
	maxPets = 6,
	moneyMethod = "tasks",
	autoClaim = true,
	claimInterval = 5,
	sessionCap = 60,
	keepReserve = true,
	reserve = 3,
	potionsPerCycle = 1,
	ageUpDelay = 2,
	egg = "auto",
	autoDelete = false,
	minRarity = 1,
	hatchDelay = 1.5,
}
Vexa.Modules = {}

Vexa.Stats = {
	cash = 0,
	potions = 0,
	petsGrown = 0,
	eggsHatched = 0,
	pets = 0,
}

Vexa.Log = {}

local state = {
	activeTab = "",
	minimised = false,
	openDropdown = nil,
	toasts = {},
	running = 0,
	startedAt = os.time(),
	bootAt = os.clock(),
	viewportScale = 1,
	logVersion = 0,
	toggleSetters = {},
	booting = true,
	glowEnabled = true,
	lastToggle = 0,
	isTyping = false,
}

local function pushLog(text, kind)
	table.insert(Vexa.Log, 1, {
		text = text,
		kind = kind or "info",
		stamp = os.date("%H:%M:%S"),
	})
	while #Vexa.Log > 40 do
		table.remove(Vexa.Log)
	end
	state.logVersion = state.logVersion + 1
end
Vexa.PushLog = pushLog

--==============================================================================
-- 06 -- COMPONENTS
--==============================================================================

-- 6.1 Toast notifications -----------------------------------------------------

local toastHolder = create("Frame", {
	Name = "Toasts",
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -18, 1, -18),
	Size = UDim2.fromOffset(324, 0),
	BackgroundTransparency = 1,
	ZIndex = 80,
	Parent = screenGui,
})

local function relayoutToasts()
	for index, toast in next, state.toasts do
		tween(toast, { Position = UDim2.new(0, 0, 1, -(index - 1) * 80) }, 0.28)
	end
end

local function Notify(kind, title, body, duration)
	if not Vexa.Config.notifications then
		return
	end
	if #state.toasts >= 4 then
		local oldest = table.remove(state.toasts, 1)
		if oldest then
			oldest:Destroy()
		end
	end

	local accent = Theme.Accent
	if kind == "success" then
		accent = Theme.Success
	elseif kind == "error" then
		accent = Theme.Danger
	elseif kind == "warn" then
		accent = Theme.Warn
	end

	local toast = create("Frame", {
		Name = "Toast",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 340, 1, 0),
		Size = UDim2.fromOffset(324, 68),
		BackgroundColor3 = Theme.Surface2,
		BorderSizePixel = 0,
		Parent = toastHolder,
	})
	corner(toast, 12)
	stroke(toast, Theme.Stroke, 1, 0.35)

	local accentBar = create("Frame", {
		Position = UDim2.fromOffset(0, 14),
		Size = UDim2.fromOffset(3, 40),
		BackgroundColor3 = accent,
		BorderSizePixel = 0,
		Parent = toast,
	})
	corner(accentBar, 2)

	local titleLabel = label(toast, {
		Position = UDim2.fromOffset(16, 13),
		Size = UDim2.new(1, -32, 0, 15),
		Font = Theme.FontBold,
		TextSize = 13,
		Text = title or "Notice",
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = toast,
	})
	local bodyLabel = label(toast, {
		Position = UDim2.fromOffset(16, 31),
		Size = UDim2.new(1, -32, 0, 26),
		TextSize = 11,
		TextColor3 = Theme.TextDim,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		Text = body or "",
		Parent = toast,
	})

	table.insert(state.toasts, toast)
	relayoutToasts()

	tween(titleLabel, { TextTransparency = 0 }, 0.2)
	tween(bodyLabel, { TextTransparency = 0 }, 0.2)

	task.delay(duration or 4, function()
		local index = table.find(state.toasts, toast)
		if not index then
			return
		end
		table.remove(state.toasts, index)
		tween(toast, {
			Position = UDim2.new(0, 360, 1, toast.Position.Y.Offset),
			BackgroundTransparency = 1,
		}, 0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		relayoutToasts()
		task.delay(0.35, function()
			if toast and toast.Parent then
				toast:Destroy()
			end
		end)
	end)
end

-- 6.2 Buttons ----------------------------------------------------------------

local function Button(parent, text, variant, onClick, size)
	variant = variant or "primary"

	local background = Theme.Surface2
	local textColor = Theme.Text
	if variant == "primary" then
		background = Theme.Accent
		textColor = WHITE
	elseif variant == "danger" then
		background = Theme.Surface2
		textColor = Theme.Danger
	end

	local button = create("TextButton", {
		Size = size or UDim2.new(1, 0, 0, 34),
		BackgroundColor3 = background,
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Text = "",
		Parent = parent,
	})
	corner(button, 9)

	if variant == "primary" then
		create("UIGradient", {
			Color = ColorSequence.new(Theme.Accent, Theme.Accent2),
			Rotation = 15,
			Parent = button,
		})
	else
		stroke(button, variant == "danger" and Theme.Danger or Theme.Stroke, 1, 0.55)
	end

	local wash = create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = button,
	})
	corner(wash, 9)

	label(button, {
		Size = UDim2.fromScale(1, 1),
		Font = Theme.FontBold,
		TextSize = 13,
		Text = text,
		TextColor3 = textColor,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = button,
	})

	local scale = create("UIScale", { Scale = 1, Parent = button })

	bind(button.MouseEnter, function()
		tween(wash, { BackgroundTransparency = 0.93 }, 0.16)
	end)
	bind(button.MouseLeave, function()
		tween(wash, { BackgroundTransparency = 1 }, 0.16)
		tween(scale, { Scale = 1 }, 0.12)
	end)
	bind(button.MouseButton1Down, function()
		tween(scale, { Scale = 0.97 }, 0.08)
	end)
	bind(button.MouseButton1Up, function()
		tween(scale, { Scale = 1 }, 0.16)
	end)
	bind(button.MouseButton1Click, function()
		if onClick then
			local ok, err = pcall(onClick)
			if not ok then
				Notify("error", "UI error", tostring(err))
			end
		end
	end)

	return button
end

-- 6.3 Toggle ----------------------------------------------------------------

local function Toggle(parent, defaultState, onChange)
	local on = defaultState and true or false

	local button = create("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(44, 24),
		BackgroundColor3 = on and Theme.Accent or Theme.Surface3,
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Text = "",
		Parent = parent,
	})
	corner(button, 12)
	local outline = stroke(button, on and Theme.Accent or Theme.Stroke, 1, on and 0.25 or 0.6)

	local glow = create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Accent,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = button,
	})
	corner(glow, 12)

	local knob = create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(on and 23 or 4, 12),
		Size = UDim2.fromOffset(17, 17),
		BackgroundColor3 = on and WHITE or Color3.fromRGB(200, 205, 220),
		BorderSizePixel = 0,
		Parent = button,
	})
	corner(knob, 9)

	local function render(animate)
		local duration = animate and 0.22 or 0
		tween(button, { BackgroundColor3 = on and Theme.Accent or Theme.Surface3 }, duration)
		tween(outline, {
			Color = on and Theme.Accent or Theme.Stroke,
			Transparency = on and 0.25 or 0.6,
		}, duration)
		tween(knob, {
			Position = UDim2.fromOffset(on and 23 or 4, 12),
			BackgroundColor3 = on and WHITE or Color3.fromRGB(200, 205, 220),
		}, duration)
	end

	bind(button.MouseEnter, function()
		if not on then
			tween(glow, { BackgroundTransparency = 0.94 }, 0.18)
		end
	end)
	bind(button.MouseLeave, function()
		tween(glow, { BackgroundTransparency = 1 }, 0.18)
	end)
	bind(button.MouseButton1Click, function()
		on = not on
		render(true)
		if onChange then
			local ok, result = pcall(onChange, on)
			if not ok then
				Notify("error", "UI error", tostring(result))
			elseif result == false then
				on = not on
				render(true)
			end
		end
	end)

	return button, function(value)
		if value ~= on then
			on = value
			render(true)
		end
	end
end

-- 6.4 Slider ----------------------------------------------------------------

local function Slider(parent, opts)
	opts = opts or {}
	local minV = opts.min or 0
	local maxV = opts.max or 100
	local step = opts.step or 1
	local value = math.clamp(opts.value or minV, minV, maxV)
	local decimals = 0
	if step < 1 and step >= 0.1 then
		decimals = 1
	elseif step < 0.1 then
		decimals = 2
	end
	local pattern = "%." .. decimals .. "f"

	local holder = create("Frame", {
		Size = UDim2.new(1, 0, 0, 46),
		BackgroundTransparency = 1,
		Parent = parent,
	})

	label(holder, {
		Size = UDim2.new(1, -80, 0, 15),
		Font = Theme.FontMed,
		TextSize = 13,
		Text = opts.text or "Value",
		Parent = holder,
	})

	local valueLabel = label(holder, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.fromOffset(78, 15),
		Font = Theme.FontBold,
		TextSize = 12,
		TextColor3 = Theme.Accent2,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "",
		Parent = holder,
	})

	local track = create("Frame", {
		Position = UDim2.fromOffset(0, 28),
		Size = UDim2.new(1, 0, 0, 6),
		BackgroundColor3 = Theme.Surface3,
		BorderSizePixel = 0,
		Parent = holder,
	})
	corner(track, 3)

	local fill = create("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Theme.Accent,
		BorderSizePixel = 0,
		Parent = track,
	})
	corner(fill, 3)
	create("UIGradient", {
		Color = ColorSequence.new(Theme.Accent, Theme.Accent2),
		Parent = fill,
	})

	local knob = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.fromOffset(14, 14),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = track,
	})
	corner(knob, 7)
	stroke(knob, Theme.Accent, 2, 0)

	local hit = create("Frame", {
		Position = UDim2.fromOffset(-6, 18),
		Size = UDim2.new(1, 12, 0, 26),
		BackgroundTransparency = 1,
		Parent = holder,
	})

	local function applyValue(nextValue, silent)
		value = math.clamp(nextValue, minV, maxV)
		local alpha = 0
		if maxV ~= minV then
			alpha = (value - minV) / (maxV - minV)
		end
		tween(fill, { Size = UDim2.fromScale(alpha, 1) }, 0.1)
		tween(knob, { Position = UDim2.new(alpha, 0, 0.5, 0) }, 0.1)
		valueLabel.Text = string.format(pattern, value)
		if not silent and opts.onChanged then
			local ok, err = pcall(opts.onChanged, value)
			if not ok then
				Notify("error", "UI error", tostring(err))
			end
		end
	end

	applyValue(value, true)

	local dragging = false
	local dragConn = nil

	local function setFromX(x)
		local width = math.max(track.AbsoluteSize.X, 1)
		local alpha = math.clamp((x - track.AbsolutePosition.X) / width, 0, 1)
		local raw = minV + alpha * (maxV - minV)
		if step > 0 then
			raw = math.floor(raw / step + 0.5) * step
		end
		applyValue(raw)
	end

	local function stopDrag()
		if not dragging then
			return
		end
		dragging = false
		if dragConn then
			dragConn:Disconnect()
			dragConn = nil
		end
		tween(knob, { Size = UDim2.fromOffset(14, 14) }, 0.14)
	end

	bind(hit.InputBegan, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			tween(knob, { Size = UDim2.fromOffset(17, 17) }, 0.14)
			setFromX(input.Position.X)
			dragConn = UserInputService.InputChanged:Connect(function(moveInput)
				if moveInput.UserInputType == Enum.UserInputType.MouseMovement
					or moveInput.UserInputType == Enum.UserInputType.Touch then
					setFromX(moveInput.Position.X)
				end
			end)
		end
	end)

	bind(UserInputService.InputEnded, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			stopDrag()
		end
	end)

	return function(newValue, silent)
		applyValue(newValue, silent)
	end
end

-- 6.5 Dropdown --------------------------------------------------------------

local function closeOpenDropdown()
	local open = state.openDropdown
	if open then
		state.openDropdown = nil
		open.frame.Visible = false
		if open.conn then
			open.conn:Disconnect()
		end
	end
end

local function Dropdown(parent, opts)
	opts = opts or {}
	local items = opts.items or {}
	local current = opts.value or (items[1] and items[1].value) or ""
	local currentLabel = ""

	for _, item in next, items do
		if item.value == current then
			currentLabel = item.label
		end
	end
	if currentLabel == "" and items[1] then
		currentLabel = items[1].label
		current = items[1].value
	end

	local button = create("TextButton", {
		Size = opts.size or UDim2.new(1, 0, 0, 34),
		BackgroundColor3 = Theme.Surface2,
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Text = "",
		Parent = parent,
	})
	corner(button, 9)
	stroke(button, Theme.Stroke, 1, 0.5)

	local textLabel = label(button, {
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.new(1, -34, 1, 0),
		Font = Theme.FontMed,
		TextSize = 13,
		Text = currentLabel,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = button,
	})

	label(button, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(10, 6),
		Font = Theme.FontBold,
		TextSize = 10,
		TextColor3 = Theme.TextDim,
		Text = "v",
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = button,
	})

	local list = create("Frame", {
		Visible = false,
		ZIndex = 60,
		BackgroundColor3 = Theme.Surface2,
		BorderSizePixel = 0,
		Parent = screenGui,
	})
	corner(list, 10)
	stroke(list, Theme.Stroke, 1, 0.25)
	pad(list, 4, 4, 4, 4)
	vlist(list, 2)

	local rowHeight = 28

	local function open()
		closeOpenDropdown()

		local rows = #items
		list.Size = UDim2.fromOffset(
			math.max(button.AbsoluteSize.X, 140),
			rows * (rowHeight + 2) + 8
		)
		list.Position = UDim2.fromOffset(
			button.AbsolutePosition.X,
			button.AbsolutePosition.Y + button.AbsoluteSize.Y + 6
		)
		list.Visible = true
		list.BackgroundTransparency = 1

		tween(list, { BackgroundTransparency = 0 }, 0.16)

		local conn = UserInputService.InputBegan:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.MouseButton1
				and input.UserInputType ~= Enum.UserInputType.Touch then
				return
			end
			local px, py
			if input.UserInputType == Enum.UserInputType.Touch then
				px, py = input.Position.X, input.Position.Y
			else
				local loc = UserInputService:GetMouseLocation()
				px, py = loc.X, loc.Y
			end
			local pos, size = list.AbsolutePosition, list.AbsoluteSize
			local inside = px >= pos.X and px <= pos.X + size.X
				and py >= pos.Y and py <= pos.Y + size.Y
			local btnPos, btnSize = button.AbsolutePosition, button.AbsoluteSize
			local onButton = px >= btnPos.X and px <= btnPos.X + btnSize.X
				and py >= btnPos.Y and py <= btnPos.Y + btnSize.Y
			if not inside and not onButton then
				closeOpenDropdown()
			end
		end)

		state.openDropdown = { frame = list, conn = conn }
	end

	for _, item in next, items do
		local row = create("TextButton", {
			Size = UDim2.new(1, 0, 0, rowHeight),
			BackgroundColor3 = Theme.Surface2,
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			BorderSizePixel = 0,
			Text = "",
			Parent = list,
		})
		corner(row, 7)

		local rowLabel = label(row, {
			Position = UDim2.fromOffset(8, 0),
			Size = UDim2.new(1, -16, 1, 0),
			TextSize = 12,
			Font = Theme.FontMed,
			Text = item.label,
			TextColor3 = item.value == current and Theme.Accent2 or Theme.Text,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = row,
		})

		bind(row.MouseEnter, function()
			tween(row, { BackgroundTransparency = 0.25 }, 0.14)
		end)
		bind(row.MouseLeave, function()
			tween(row, { BackgroundTransparency = 1 }, 0.14)
		end)
		bind(row.MouseButton1Click, function()
			current = item.value
			textLabel.Text = item.label
			closeOpenDropdown()
			if opts.onChanged then
				local ok, err = pcall(opts.onChanged, item.value, item.label)
				if not ok then
					Notify("error", "UI error", tostring(err))
				end
			end
			for _, other in next, list:GetChildren() do
				if other:IsA("TextButton") then
					local childLabel = other:FindFirstChildOfClass("TextLabel")
					if childLabel then
						childLabel.TextColor3 = childLabel.Text == item.label and Theme.Accent2 or Theme.Text
					end
				end
			end
			rowLabel.TextColor3 = Theme.Accent2
		end)
	end

	bind(button.MouseButton1Click, function()
		if list.Visible then
			closeOpenDropdown()
		else
			open()
		end
	end)

	return function(newValue)
		current = newValue
		for _, item in next, items do
			if item.value == newValue then
				textLabel.Text = item.label
			end
		end
	end
end

-- 6.6 Section card + Row ----------------------------------------------------

local function Section(page, title, subtitle)
	local card = create("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.Surface,
		BorderSizePixel = 0,
		Parent = page,
	})
	corner(card, 12)
	stroke(card, Theme.Stroke, 1, 0.55)
	pad(card, 14, 14, 14, 14)
	vlist(card, 6)

	label(card, {
		Size = UDim2.new(1, 0, 0, 17),
		Font = Theme.FontBold,
		TextSize = 13,
		Text = title,
		Parent = card,
	})

	if subtitle then
		label(card, {
			Size = UDim2.new(1, 0, 0, 14),
			TextSize = 11,
			TextColor3 = Theme.TextFaint,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			Text = subtitle,
			Parent = card,
		})
		create("Frame", {
			Size = UDim2.new(1, 0, 0, 10),
			BackgroundTransparency = 1,
			Parent = card,
		})
	end

	return card
end

local function Row(parent, title, description)
	local height = 34
	if description then
		height = 46
	end

	local row = create("Frame", {
		Size = UDim2.new(1, 0, 0, height),
		BackgroundTransparency = 1,
		Parent = parent,
	})

	label(row, {
		Position = UDim2.fromOffset(0, description and 0 or 0),
		Size = description and UDim2.new(1, -116, 0, 16) or UDim2.new(1, -116, 1, 0),
		Font = Theme.FontMed,
		TextSize = 13,
		Text = title,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = row,
	})

	if description then
		label(row, {
			Position = UDim2.fromOffset(0, 17),
			Size = UDim2.new(1, -116, 0, 13),
			TextSize = 11,
			TextColor3 = Theme.TextFaint,
			Text = description,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = row,
		})
	end

	local slot = create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(108, 28),
		BackgroundTransparency = 1,
		Parent = row,
	})

	return row, slot
end

--==============================================================================
-- 07 -- WINDOW SKELETON
--==============================================================================

local WINDOW_W, WINDOW_H = 700, 470

local glow = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(WINDOW_W + 40, WINDOW_H + 40),
	BackgroundColor3 = Theme.Accent,
	BackgroundTransparency = 0.95,
	BorderSizePixel = 0,
	Visible = false,
	Parent = screenGui,
})
corner(glow, 34)

local window = create("Frame", {
	Name = "Window",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(WINDOW_W, WINDOW_H),
	BackgroundColor3 = Theme.Bg,
	BorderSizePixel = 0,
	ClipsDescendants = true,
	Visible = false,
	Parent = screenGui,
})
corner(window, 16)
stroke(window, Theme.Stroke, 1, 0.3)
create("UIGradient", {
	Color = ColorSequence.new(Color3.fromRGB(18, 17, 26), Color3.fromRGB(10, 10, 15)),
	Rotation = 135,
	Parent = window,
})

local windowScale = create("UIScale", { Scale = 1, Parent = window })

do
	local constraint = create("UISizeConstraint", {
		MinSize = Vector2.new(560, 400),
		Parent = window,
	})
end

-- 7.1 Sidebar ---------------------------------------------------------------

local sidebar = create("Frame", {
	Name = "Sidebar",
	Position = UDim2.fromOffset(10, 10),
	Size = UDim2.new(0, 164, 1, -20),
	BackgroundColor3 = Theme.Surface,
	BorderSizePixel = 0,
	Parent = window,
})
corner(sidebar, 12)
stroke(sidebar, Theme.Stroke, 1, 0.6)

local brandMark = create("Frame", {
	Position = UDim2.fromOffset(14, 14),
	Size = UDim2.fromOffset(30, 30),
	BackgroundColor3 = Theme.Accent,
	BorderSizePixel = 0,
	Parent = sidebar,
})
corner(brandMark, 9)
create("UIGradient", {
	Color = ColorSequence.new(Theme.Accent, Theme.Accent2),
	Rotation = 35,
	Parent = brandMark,
})
label(brandMark, {
	Size = UDim2.fromScale(1, 1),
	Font = Theme.FontBlack,
	TextSize = 16,
	Text = "V",
	TextColor3 = WHITE,
	TextXAlignment = Enum.TextXAlignment.Center,
	Parent = brandMark,
})

label(sidebar, {
	Position = UDim2.fromOffset(50, 13),
	Size = UDim2.new(1, -64, 0, 16),
	Font = Theme.FontBold,
	TextSize = 13,
	Text = "VEXA PETS",
	Parent = sidebar,
})
label(sidebar, {
	Position = UDim2.fromOffset(50, 28),
	Size = UDim2.new(1, -64, 0, 13),
	TextSize = 10,
	TextColor3 = Theme.TextFaint,
	Text = "v" .. Vexa.Version,
	Parent = sidebar,
})

local tabHolder = create("Frame", {
	Position = UDim2.fromOffset(8, 62),
	Size = UDim2.new(1, -16, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1,
	Parent = sidebar,
})
vlist(tabHolder, 3)

local footer = create("Frame", {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 0, 1, 0),
	Size = UDim2.new(1, 0, 0, 46),
	BackgroundTransparency = 1,
	Parent = sidebar,
})
create("Frame", {
	Size = UDim2.new(1, -24, 0, 1),
	Position = UDim2.fromOffset(12, 0),
	BackgroundColor3 = Theme.Stroke,
	BackgroundTransparency = 0.5,
	BorderSizePixel = 0,
	Parent = footer,
})

local fpsLabel = label(footer, {
	Position = UDim2.fromOffset(12, 12),
	Size = UDim2.new(0.5, -12, 0, 13),
	Font = Theme.FontMed,
	TextSize = 10,
	TextColor3 = Theme.TextFaint,
	Text = "-- FPS",
	Parent = footer,
})
local pingLabel = label(footer, {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0, 12),
	Size = UDim2.new(0.5, -12, 0, 13),
	Font = Theme.FontMed,
	TextSize = 10,
	TextColor3 = Theme.TextFaint,
	TextXAlignment = Enum.TextXAlignment.Right,
	Text = "-- ms",
	Parent = footer,
})
local statusLabel = label(footer, {
	Position = UDim2.fromOffset(12, 25),
	Size = UDim2.new(1, -24, 0, 13),
	Font = Theme.FontMed,
	TextSize = 10,
	TextColor3 = Theme.TextFaint,
	Text = "idle",
	Parent = footer,
})

-- 7.2 Main area -------------------------------------------------------------

local main = create("Frame", {
	Name = "Main",
	Position = UDim2.fromOffset(184, 10),
	Size = UDim2.new(1, -194, 1, -20),
	BackgroundTransparency = 1,
	Parent = window,
})

local headerTitle = label(main, {
	Position = UDim2.fromOffset(0, 4),
	Size = UDim2.new(1, -140, 0, 22),
	Font = Theme.FontBold,
	TextSize = 17,
	Text = "Dashboard",
	Parent = main,
})
local headerSubtitle = label(main, {
	Position = UDim2.fromOffset(0, 26),
	Size = UDim2.new(1, -140, 0, 15),
	TextSize = 11,
	TextColor3 = Theme.TextDim,
	Text = "",
	Parent = main,
})

local function windowButton(text, xOffset, hoverColor)
	local btn = create("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, xOffset, 0, 4),
		Size = UDim2.fromOffset(28, 28),
		BackgroundColor3 = Theme.Surface2,
		BackgroundTransparency = 0.35,
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Text = "",
		Parent = main,
	})
	corner(btn, 8)
	label(btn, {
		Size = UDim2.fromScale(1, 1),
		Font = Theme.FontBold,
		TextSize = 14,
		Text = text,
		TextColor3 = Theme.TextDim,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = btn,
	})
	bind(btn.MouseEnter, function()
		tween(btn, { BackgroundTransparency = 0, BackgroundColor3 = hoverColor }, 0.16)
	end)
	bind(btn.MouseLeave, function()
		tween(btn, { BackgroundTransparency = 0.35, BackgroundColor3 = Theme.Surface2 }, 0.16)
	end)
	return btn
end

local pagesHolder = create("Frame", {
	Position = UDim2.fromOffset(0, 54),
	Size = UDim2.new(1, 0, 1, -54),
	BackgroundTransparency = 1,
	Parent = main,
})

--==============================================================================
-- 08 -- TABS + PAGES
--==============================================================================

local tabDefs = {
	{ id = "home",     label = "Dashboard", desc = "Live session overview" },
	{ id = "pets",     label = "Pet Farm",  desc = "Grow, collect and manage your pets" },
	{ id = "money",    label = "Money",     desc = "Automate cash income" },
	{ id = "ageup",    label = "Age Up",    desc = "Potions, reserves and bulk application" },
	{ id = "eggs",     label = "Eggs",      desc = "Hatching loop and drop filters" },
	{ id = "utility",  label = "Utility",   desc = "Session helpers and small tools" },
	{ id = "settings", label = "Settings",  desc = "Preferences and runtime options" },
}

local tabs = {}
local pages = {}
local content = {}

local function setTab(id)
	if state.activeTab == id then
		return
	end
	closeOpenDropdown()

	local previous = pages[state.activeTab]
	local nextPage = content[id]
	if not nextPage then
		return
	end

	local previousButton = tabs[state.activeTab]
	local nextButton = tabs[id]
	state.activeTab = id

	if previous then
		tween(previous, { GroupTransparency = 1 }, 0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(0.16, function()
			if state.activeTab ~= id then
				previous.Visible = false
			end
		end)
	end

	nextPage.Visible = true
	nextPage.GroupTransparency = 1
	nextPage.Position = UDim2.fromOffset(0, 10)
	tween(nextPage, { GroupTransparency = 0, Position = UDim2.fromOffset(0, 0) }, 0.3)

	for _, def in next, tabDefs do
		local btn = tabs[def.id]
		if btn then
			local active = def.id == id
			tween(btn.frame, {
				BackgroundColor3 = active and Theme.Surface2 or Theme.Surface,
				BackgroundTransparency = active and 0 or 1,
			}, 0.22)
			tween(btn.text, { TextColor3 = active and Theme.Text or Theme.TextDim }, 0.22)
			tween(btn.bar, { BackgroundTransparency = active and 0 or 1 }, 0.22)
		end
	end

	headerTitle.Text = nextButton and nextButton.def.label or ""
	headerSubtitle.Text = nextButton and nextButton.def.desc or ""
end

for index, def in next, tabDefs do
	local frame = create("TextButton", {
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundColor3 = Theme.Surface,
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Text = "",
		LayoutOrder = index,
		Parent = tabHolder,
	})
	corner(frame, 9)

	local activeBar = create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(0, 17),
		Size = UDim2.fromOffset(3, 15),
		BackgroundColor3 = Theme.Accent2,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = frame,
	})
	corner(activeBar, 2)

	local textLabel = label(frame, {
		Position = UDim2.fromOffset(13, 0),
		Size = UDim2.new(1, -20, 1, 0),
		Font = Theme.FontMed,
		TextSize = 12,
		TextColor3 = Theme.TextDim,
		Text = def.label,
		Parent = frame,
	})

	bind(frame.MouseEnter, function()
		if state.activeTab ~= def.id then
			tween(frame, { BackgroundTransparency = 0.6, BackgroundColor3 = Theme.Surface2 }, 0.16)
			tween(textLabel, { TextColor3 = Theme.Text }, 0.16)
		end
	end)
	bind(frame.MouseLeave, function()
		if state.activeTab ~= def.id then
			tween(frame, { BackgroundTransparency = 1 }, 0.16)
			tween(textLabel, { TextColor3 = Theme.TextDim }, 0.16)
		end
	end)
	bind(frame.MouseButton1Click, function()
		setTab(def.id)
	end)

	tabs[def.id] = { frame = frame, text = textLabel, bar = activeBar, def = def }

	local page = create("CanvasGroup", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		GroupTransparency = 1,
		Parent = pagesHolder,
	})

	local scroll = create("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = Theme.Stroke,
		ScrollBarImageTransparency = 0.2,
		ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
		Parent = page,
	})
	pad(scroll, 0, 6, 0, 8)
	vlist(scroll, 10)

	pages[def.id] = page
	content[def.id] = scroll
end

--==============================================================================
-- 10 -- PAGE CONTENT
--==============================================================================

-- 10.0 Dashboard -------------------------------------------------------------

do
	local page = content.home

	local function formatNumber(value)
		local text = tostring(math.floor(value))
		local count
		repeat
			text, count = text:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
		until count == 0
		return text
	end

	local function statCard(parent, caption, color, order)
		local card = create("Frame", {
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundColor3 = Theme.Surface2,
			BorderSizePixel = 0,
			LayoutOrder = order,
			Parent = parent,
		})
		corner(card, 10)
		stroke(card, Theme.Stroke, 1, 0.6)

		label(card, {
			Position = UDim2.fromOffset(12, 9),
			Size = UDim2.new(1, -24, 0, 12),
			TextSize = 10,
			TextColor3 = Theme.TextFaint,
			Text = caption,
			Parent = card,
		})

		return label(card, {
			Position = UDim2.fromOffset(12, 24),
			Size = UDim2.new(1, -24, 0, 28),
			Font = Theme.FontBlack,
			TextSize = 21,
			TextColor3 = color,
			Text = "0",
			Parent = card,
		})
	end

	local overview = Section(page, "Overview")
	local grid = create("Frame", {
		Size = UDim2.new(1, 0, 0, 138),
		BackgroundTransparency = 1,
		Parent = overview,
	})
	create("UIGridLayout", {
		CellSize = UDim2.new(0.5, -5, 0, 64),
		CellPadding = UDim2.new(0, 10, 0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})

	local cashValue = statCard(grid, "CASH", Theme.Success, 1)
	local potionValue = statCard(grid, "AGE-UP POTIONS", Theme.Accent2, 2)
	local grownValue = statCard(grid, "PETS GROWN", Theme.Accent, 3)
	local eggValue = statCard(grid, "EGGS HATCHED", Theme.Warn, 4)

	local actions = Section(page, "Quick actions")
	local actionRow = create("Frame", {
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundTransparency = 1,
		Parent = actions,
	})
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = actionRow,
	})

	Button(actionRow, "Start all", "primary", function()
		pushLog(string.format("Started %d module(s)", startAll(true)), "success")
		Notify("success", "Runtime", startAll(true) .. " module(s) started")
	end, UDim2.new(0.5, -4, 0, 34))

	Button(actionRow, "Stop all", "danger", function()
		stopAll(true)
		pushLog("All modules stopped", "info")
		Notify("info", "Runtime", "All modules stopped")
	end, UDim2.new(0.5, -4, 0, 34))

	local feed = Section(page, "Activity", "Newest events first")
	local logBox = create("Frame", {
		Size = UDim2.new(1, 0, 0, 146),
		BackgroundColor3 = Theme.Surface2,
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
		Parent = feed,
	})
	corner(logBox, 10)
	pad(logBox, 10, 10, 12, 12)
	vlist(logBox, 5)

	local renderedLog = -1

	local function renderLog()
		if state.logVersion == renderedLog then
			return
		end
		renderedLog = state.logVersion

		for _, child in next, logBox:GetChildren() do
			if child:IsA("TextLabel") then
				child:Destroy()
			end
		end

		if #Vexa.Log == 0 then
			label(logBox, {
				Size = UDim2.new(1, 0, 0, 16),
				TextSize = 11,
				TextColor3 = Theme.TextFaint,
				Text = "Nothing yet - start a module to see events.",
				Parent = logBox,
			})
			return
		end

		local colors = {
			success = Theme.Success,
			warn = Theme.Warn,
			error = Theme.Danger,
			money = Theme.Accent2,
		}

		local shown = 0
		for _, entry in next, Vexa.Log do
			shown = shown + 1
			if shown > 6 then
				break
			end
			label(logBox, {
				Size = UDim2.new(1, 0, 0, 15),
				TextSize = 11,
				Text = entry.stamp .. "  " .. entry.text,
				TextColor3 = colors[entry.kind] or Theme.TextDim,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Parent = logBox,
			})
		end
	end

	renderLog()

	task.spawn(function()
		while screenGui.Parent do
			cashValue.Text = "$" .. formatNumber(Vexa.Stats.cash)
			potionValue.Text = formatNumber(Vexa.Stats.potions)
			grownValue.Text = formatNumber(Vexa.Stats.petsGrown)
			eggValue.Text = formatNumber(Vexa.Stats.eggsHatched)
			renderLog()
			task.wait(0.3)
		end
	end)
end

-- 10.1 Pet Farm --------------------------------------------------------------

do
	local page = content.pets

	local card = Section(page, "Automation", "Requires Vexa.Adapter.PetFarmStart / PetFarmTick")

	do
		local row, slot = Row(card, "Enable pet farm", "Runs the growth loop every tick")
		local _, setter = Toggle(slot, false, function(on)
			return setModule(PetFarm, on)
		end)
		state.toggleSetters[PetFarm.id] = setter
	end

	do
		local row, slot = Row(card, "Auto equip", "Swap in the pet being grown")
		Toggle(slot, true, function(on)
			Vexa.Config.autoEquip = on
		end)
	end

	do
		local row, slot = Row(card, "Mode")
		local mode = "level"
		Dropdown(slot, {
			size = UDim2.fromOffset(108, 26),
			items = {
				{ value = "level", label = "Level up" },
				{ value = "collect", label = "Collect" },
				{ value = "both", label = "Both" },
			},
			onChanged = function(value)
				Vexa.Config.petMode = value
			end,
		})
		Vexa.Config.petMode = mode
	end

	do
		local row, slot = Row(card, "Target pet")
		Dropdown(slot, {
			size = UDim2.fromOffset(108, 26),
			items = {
				{ value = "all", label = "All pets" },
				{ value = "equipped", label = "Equipped only" },
				{ value = "lowest", label = "Lowest age" },
				{ value = "highest", label = "Highest value" },
			},
			onChanged = function(value)
				Vexa.Config.targetPet = value
			end,
		})
		Vexa.Config.targetPet = "all"
	end

	do
		local card2 = Section(page, "Tuning")

		Slider(card2, {
			text = "Action delay",
			min = 0.2,
			max = 5,
			step = 0.1,
			value = 1,
			onChanged = function(value)
				Vexa.Config.actionDelay = value
			end,
		})

		Slider(card2, {
			text = "Max pets per cycle",
			min = 1,
			max = 20,
			step = 1,
			value = 6,
			onChanged = function(value)
				Vexa.Config.maxPets = value
			end,
		})
	end

	do
		local card3 = Section(page, "Actions")
		local row = create("Frame", {
			Size = UDim2.new(1, 0, 0, 34),
			BackgroundTransparency = 1,
			Parent = card3,
		})
		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = row,
		})

		Button(row, "Run once", "primary", function()
			if type(Vexa.Adapter.PetFarmTick) ~= "function" then
				Notify("warn", "Pet Farm", "Vexa.Adapter.PetFarmTick is not defined")
				return
			end
			local ok, err = pcall(Vexa.Adapter.PetFarmTick, 0, PetFarm)
			if ok then
				Notify("success", "Pet Farm", "Single cycle completed")
			else
				Notify("error", "Pet Farm", tostring(err))
			end
		end, UDim2.new(0.5, -4, 0, 34))

		Button(row, "Stop all", "danger", function()
			stopAll()
			Notify("info", "Runtime", "All modules stopped")
		end, UDim2.new(0.5, -4, 0, 34))
	end
end

-- 10.2 Money ----------------------------------------------------------------

do
	local page = pages.money

	local card = Section(page, "Cash loop", "Requires Vexa.Adapter.MoneyStart / MoneyTick")

	do
		local row, slot = Row(card, "Enable money farm", "Runs your selected method")
		local _, setter = Toggle(slot, false, function(on)
			return setModule(MoneyFarm, on)
		end)
		state.toggleSetters[MoneyFarm.id] = setter
	end

	do
		local row, slot = Row(card, "Method")
		Dropdown(slot, {
			size = UDim2.fromOffset(108, 26),
			items = {
				{ value = "tasks", label = "Tasks" },
				{ value = "collect", label = "Collect" },
				{ value = "both", label = "Both" },
			},
			onChanged = function(value)
				Vexa.Config.moneyMethod = value
			end,
		})
		Vexa.Config.moneyMethod = "both"
	end

	do
		local row, slot = Row(card, "Auto claim", "Claim rewards the moment they appear")
		Toggle(slot, true, function(on)
			Vexa.Config.autoClaim = on
		end)
	end

	do
		local card2 = Section(page, "Tuning")
		Slider(card2, {
			text = "Claim interval (s)",
			min = 1,
			max = 30,
			step = 1,
			value = 5,
			onChanged = function(value)
				Vexa.Config.claimInterval = value
			end,
		})
		Slider(card2, {
			text = "Session cap (min)",
			min = 5,
			max = 240,
			step = 5,
			value = 60,
			onChanged = function(value)
				Vexa.Config.sessionCap = value
			end,
		})
	end
end

-- 10.3 Age Up ---------------------------------------------------------------

do
	local page = pages.ageup

	local card = Section(page, "Age up potions", "Requires Vexa.Adapter.AgeUpStart / AgeUpTick")

	do
		local row, slot = Row(card, "Enable age up farm", "Applies potions on a loop")
		local _, setter = Toggle(slot, false, function(on)
			return setModule(AgeUpFarm, on)
		end)
		state.toggleSetters[AgeUpFarm.id] = setter
	end

	do
		local row, slot = Row(card, "Keep reserve", "Never spend below this amount")
		Toggle(slot, true, function(on)
			Vexa.Config.keepReserve = on
		end)
	end

	do
		local card2 = Section(page, "Limits")
		Slider(card2, {
			text = "Reserved potions",
			min = 0,
			max = 20,
			step = 1,
			value = 3,
			onChanged = function(value)
				Vexa.Config.reserve = value
			end,
		})
		Slider(card2, {
			text = "Potions per cycle",
			min = 1,
			max = 10,
			step = 1,
			value = 1,
			onChanged = function(value)
				Vexa.Config.potionsPerCycle = value
			end,
		})
		Slider(card2, {
			text = "Cycle delay (s)",
			min = 0.5,
			max = 10,
			step = 0.5,
			value = 2,
			onChanged = function(value)
				Vexa.Config.ageUpDelay = value
			end,
		})
	end

	do
		local card3 = Section(page, "Manual")
		Button(card3, "Apply all available now", "primary", function()
			if type(Vexa.Adapter.AgeUpTick) ~= "function" then
				Notify("warn", "Age Up", "Vexa.Adapter.AgeUpTick is not defined")
				return
			end
			local ok, err = pcall(Vexa.Adapter.AgeUpTick, 0, AgeUpFarm)
			if ok then
				Notify("success", "Age Up", "Applied available potions")
			else
				Notify("error", "Age Up", tostring(err))
			end
		end)
	end
end

-- 10.4 Eggs -----------------------------------------------------------------

do
	local page = pages.eggs

	local card = Section(page, "Hatcher", "Requires Vexa.Adapter.EggStart / EggTick")

	do
		local row, slot = Row(card, "Enable hatcher", "Hatches eggs continuously")
		local _, setter = Toggle(slot, false, function(on)
			return setModule(EggFarm, on)
		end)
		state.toggleSetters[EggFarm.id] = setter
	end

	do
		local row, slot = Row(card, "Egg")
		Dropdown(slot, {
			size = UDim2.fromOffset(108, 26),
			items = {
				{ value = "auto", label = "Auto (cheapest)" },
				{ value = "starter", label = "Starter egg" },
				{ value = "rare", label = "Rare egg" },
				{ value = "event", label = "Event egg" },
			},
			onChanged = function(value)
				Vexa.Config.egg = value
			end,
		})
		Vexa.Config.egg = "auto"
	end

	do
		local row, slot = Row(card, "Auto delete", "Remove low tier results automatically")
		Toggle(slot, false, function(on)
			Vexa.Config.autoDelete = on
		end)
	end

	do
		local card2 = Section(page, "Filters")
		Slider(card2, {
			text = "Minimum rarity tier",
			min = 1,
			max = 5,
			step = 1,
			value = 1,
			onChanged = function(value)
				Vexa.Config.minRarity = value
			end,
		})
		Slider(card2, {
			text = "Hatch delay (s)",
			min = 0.5,
			max = 8,
			step = 0.5,
			value = 1.5,
			onChanged = function(value)
				Vexa.Config.hatchDelay = value
			end,
		})
	end
end

-- 10.5 Utility --------------------------------------------------------------

local antiAfkConnection = nil

local function setAntiAfk(enabled)
	if not enabled then
		if antiAfkConnection then
			antiAfkConnection:Disconnect()
			antiAfkConnection = nil
		end
		return true
	end

	local ok = pcall(function()
		local virtualUser = game:GetService("VirtualUser")
		antiAfkConnection = LocalPlayer.Idled:Connect(function()
			virtualUser:CaptureController()
			virtualUser:ClickButton2(Vector2.new())
		end)
	end)

	if not ok then
		return false, "VirtualUser is unavailable in this environment"
	end
	return true
end

do
	local page = pages.utility

	local card = Section(page, "Session")

	do
		local row, slot = Row(card, "Anti AFK", "Prevents the idle kick while farming")
		Toggle(slot, false, function(on)
			local ok, err = setAntiAfk(on)
			if not ok then
				Notify("error", "Anti AFK", err)
				return false
			end
		end)
	end

	do
		local row, slot = Row(card, "Notifications", "Toast messages in the corner")
		Toggle(slot, true, function(on)
			Vexa.Config.notifications = on
		end)
	end

	do
		local card2 = Section(page, "Interface")
		Button(card2, "Hide interface", "ghost", function()
			Vexa.ToggleVisibility()
		end)
	end

	do
		local card3 = Section(page, "Session clock")
		local clock = label(card3, {
			Size = UDim2.new(1, 0, 0, 30),
			Font = Theme.FontBlack,
			TextSize = 22,
			Text = "00:00:00",
			Parent = card3,
		})
		task.spawn(function()
			while screenGui.Parent do
				local elapsed = os.time() - state.startedAt
				clock.Text = string.format(
					"%02d:%02d:%02d",
					math.floor(elapsed / 3600),
					math.floor(elapsed % 3600 / 60),
					elapsed % 60
				)
				task.wait(1)
			end
		end)
	end
end

-- 10.6 Settings -------------------------------------------------------------

do
	local page = pages.settings

	local card = Section(page, "Runtime")

	Slider(card, {
		text = "Update interval (s)",
		min = 0.05,
		max = 1,
		step = 0.05,
		value = Vexa.Config.tickInterval,
		onChanged = function(value)
			Vexa.Config.tickInterval = value
		end,
	})

	do
		local row, slot = Row(card, "Remember settings", "Persist config for this session")
		Toggle(slot, false, function(on)
			Vexa.Config.persist = on
		end)
	end

	do
		local card2 = Section(page, "Interface")

		local row = Row(card2, "Toggle key", "Shows or hides the window")
		local keyLabel = label(row, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, 0, 0.5, 0),
			Size = UDim2.fromOffset(108, 24),
			BackgroundColor3 = Theme.Surface2,
			BackgroundTransparency = 0,
			Font = Theme.FontBold,
			TextSize = 11,
			TextColor3 = Theme.TextDim,
			Text = Vexa.Config.toggleKey.Name,
			TextXAlignment = Enum.TextXAlignment.Center,
			Parent = row,
		})
		corner(keyLabel, 7)
		stroke(keyLabel, Theme.Stroke, 1, 0.6)

		local row2, slot2 = Row(card2, "Window glow", "Ambient accent behind the panel")
		Toggle(slot2, state.glowEnabled, function(on)
			state.glowEnabled = on
			glow.Visible = on and not state.minimised
		end)
	end

	do
		local cardD = Section(page, "Demo mode", "Simulated locally - no game data is touched")

		local rowD, slotD = Row(cardD, "Enable demo", "Drives the modules with fake data")
		Toggle(slotD, Vexa.Demo.enabled, function(on)
			stopAll(true)
			Vexa.SetDemo(on)
			refreshStatus()
		end)

		Button(cardD, "Reset simulated data", "ghost", function()
			Vexa.ResetDemo()
			Notify("info", "Demo", "Simulated data reset")
		end)
	end

	do
		local card3 = Section(page, "Danger zone")

		Button(card3, "Unload VEXA PETS", "danger", function()
			Notify("warn", "VEXA PETS", "Unloading in 1 second...")
			task.delay(1, function()
				Vexa:Destroy()
			end)
		end)

		label(card3, {
			Size = UDim2.new(1, 0, 0, 14),
			TextSize = 10,
			TextColor3 = Theme.TextFaint,
			Text = "Unloading disconnects every loop and removes all GUI.",
			TextXAlignment = Enum.TextXAlignment.Center,
			Parent = card3,
		})
	end
end

--==============================================================================
-- 11 -- WINDOW BEHAVIOUR
--==============================================================================

local restoreButton = create("TextButton", {
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 16, 0.5, 0),
	Size = UDim2.fromOffset(46, 46),
	BackgroundColor3 = Theme.Accent,
	BorderSizePixel = 0,
	AutoButtonColor = false,
	Text = "",
	Visible = false,
	Parent = screenGui,
})
corner(restoreButton, 14)
create("UIGradient", {
	Color = ColorSequence.new(Theme.Accent, Theme.Accent2),
	Rotation = 35,
	Parent = restoreButton,
})
label(restoreButton, {
	Size = UDim2.fromScale(1, 1),
	Font = Theme.FontBlack,
	TextSize = 18,
	Text = "V",
	TextColor3 = WHITE,
	TextXAlignment = Enum.TextXAlignment.Center,
	Parent = restoreButton,
})

local function showWindow()
	state.minimised = false
	restoreButton.Visible = false
	toastHolder.Visible = true
	window.Visible = true
	windowScale.Scale = (state.viewportScale or 1) * 0.95
	glow.Visible = state.glowEnabled
	glow.BackgroundTransparency = 1
	tween(windowScale, { Scale = state.viewportScale or 1 }, 0.26)
	if state.glowEnabled then
		tween(glow, { BackgroundTransparency = 0.95 }, 0.4)
	end
end
Vexa.Show = showWindow

function Vexa.Minimise()
	if state.minimised then
		return
	end
	state.minimised = true
	closeOpenDropdown()

	tween(windowScale, { Scale = (state.viewportScale or 1) * 0.96 }, 0.16)
	tween(glow, { BackgroundTransparency = 1 }, 0.16)

	task.delay(0.16, function()
		if state.minimised then
			window.Visible = false
			glow.Visible = false
			toastHolder.Visible = false
			if not state.booting then
				restoreButton.Visible = true
			end
		end
	end)
end

function Vexa.SetVisible(visible)
	if visible then
		showWindow()
	else
		Vexa.Minimise()
	end
end

function Vexa.ToggleVisibility()
	if state.booting then
		return
	end

	local now = os.clock()
	if now - state.lastToggle < 0.15 then
		return
	end
	state.lastToggle = now

	if state.minimised then
		showWindow()
	else
		Vexa.Minimise()
	end
end

bind(restoreButton.MouseButton1Click, function()
	showWindow()
end)
bind(restoreButton.MouseEnter, function()
	tween(restoreButton, { Size = UDim2.fromOffset(50, 50) }, 0.16)
end)
bind(restoreButton.MouseLeave, function()
	tween(restoreButton, { Size = UDim2.fromOffset(46, 46) }, 0.16)
end)

-- 11.1 Dragging -------------------------------------------------------------

do
	local dragging = false
	local dragStart = nil
	local startPos = nil

	local function beginDrag(input)
		dragging = true
		closeOpenDropdown()
		dragStart = input.Position

		local absolute = window.AbsolutePosition
		window.AnchorPoint = Vector2.new(0, 0)
		window.Position = UDim2.fromOffset(absolute.X, absolute.Y)
		startPos = Vector2.new(absolute.X, absolute.Y)
	end

	bind(sidebar.InputBegan, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			beginDrag(input)
		end
	end)

	bind(main.InputBegan, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			local pos = input.Position
			local absolute = window.AbsolutePosition
			local headerHeight = 54 * (windowScale.Scale or 1)
			if pos.Y - absolute.Y <= headerHeight then
				beginDrag(input)
			end
		end
	end)

	bind(UserInputService.InputChanged, function(input)
		if not dragging then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch then
			local delta = input.Position - dragStart
			window.Position = UDim2.fromOffset(startPos.X + delta.X, startPos.Y + delta.Y)
		end
	end)

	bind(UserInputService.InputEnded, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
end

-- 11.2 Window controls ------------------------------------------------------

do
	local minimiseButton = windowButton("_", -38, Theme.Surface3)
	local closeButton = windowButton("x", -4, Theme.Danger)

	bind(minimiseButton.MouseButton1Click, function()
		Vexa.Minimise()
	end)

	bind(closeButton.MouseButton1Click, function()
		Vexa:Destroy()
	end)
end

-- 11.3 Responsive scale -----------------------------------------------------

local lastViewport = nil

local function resizeForViewport()
	local camera = workspace.CurrentCamera
	local viewport = (camera and camera.ViewportSize) or Vector2.new(1280, 720)
	if lastViewport and viewport.X == lastViewport.X and viewport.Y == lastViewport.Y then
		return
	end
	lastViewport = viewport

	local scale = math.clamp((viewport.X - 40) / WINDOW_W, 0.62, 1)
	state.viewportScale = scale
	if not state.minimised then
		windowScale.Scale = scale
	end
end

bind(RunService.RenderStepped, resizeForViewport)
resizeForViewport()

-- 11.4 Keybind --------------------------------------------------------------

local function isTyping()
	local ok, box = pcall(function()
		return UserInputService:GetFocusedTextBox()
	end)
	return ok and box ~= nil
end

bind(UserInputService.InputBegan, function(input)
	if input.KeyCode ~= Vexa.Config.toggleKey then
		return
	end
	if isTyping() then
		return
	end
	Vexa.ToggleVisibility()
end)

Vexa.IsTyping = isTyping

-- 11.5 Telemetry ------------------------------------------------------------

do
	local frames = 0
	local accumulator = 0
	bind(RunService.RenderStepped, function(dt)
		frames = frames + 1
		accumulator = accumulator + dt
		if accumulator < 0.5 then
			return
		end
		fpsLabel.Text = math.floor(frames / accumulator + 0.5) .. " FPS"
		frames = 0
		accumulator = 0

		local ok, ping = pcall(function()
			return Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
		end)
		if ok and type(ping) == "number" then
			pingLabel.Text = math.floor(ping) .. " ms"
		end
	end)
end

--==============================================================================
-- 12 -- LOADING SEQUENCE
--==============================================================================

local loader = create("Frame", {
	Name = "Loader",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Theme.Bg,
	BorderSizePixel = 0,
	ZIndex = 200,
	Parent = screenGui,
})
create("UIGradient", {
	Color = ColorSequence.new(Color3.fromRGB(20, 17, 32), Color3.fromRGB(7, 7, 12)),
	Rotation = 135,
	Parent = loader,
})

local loadGlow = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(420, 220),
	BackgroundColor3 = Theme.Accent,
	BackgroundTransparency = 0.93,
	BorderSizePixel = 0,
	Parent = loader,
})
corner(loadGlow, 60)

local center = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(340, 190),
	BackgroundTransparency = 1,
	Parent = loader,
})

local brand = label(center, {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 0),
	Size = UDim2.new(1, 0, 0, 58),
	Font = Theme.FontBlack,
	TextSize = 52,
	Text = "VEXA",
	TextColor3 = WHITE,
	TextXAlignment = Enum.TextXAlignment.Center,
	Parent = center,
})
create("UIGradient", {
	Color = ColorSequence.new(Theme.Accent, Theme.Accent2),
	Rotation = 10,
	Parent = brand,
})

label(center, {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 56),
	Size = UDim2.new(1, 0, 0, 16),
	Font = Theme.FontBold,
	TextSize = 11,
	TextColor3 = Theme.TextDim,
	Text = "P E T S",
	TextXAlignment = Enum.TextXAlignment.Center,
	Parent = center,
})

local bar = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 106),
	Size = UDim2.fromOffset(300, 5),
	BackgroundColor3 = Theme.Surface3,
	BorderSizePixel = 0,
	Parent = center,
})
corner(bar, 3)

local barFill = create("Frame", {
	Size = UDim2.fromScale(0, 1),
	BackgroundColor3 = Theme.Accent,
	BorderSizePixel = 0,
	Parent = bar,
})
corner(barFill, 3)
create("UIGradient", {
	Color = ColorSequence.new(Theme.Accent, Theme.Accent2),
	Parent = barFill,
})

local statusText = label(center, {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 122),
	Size = UDim2.new(1, 0, 0, 14),
	TextSize = 11,
	TextColor3 = Theme.TextFaint,
	Text = "Starting up",
	Parent = center,
})
local percentText = label(center, {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 122),
	Size = UDim2.new(1, 0, 0, 14),
	TextSize = 11,
	Font = Theme.FontBold,
	TextColor3 = Theme.Accent2,
	TextXAlignment = Enum.TextXAlignment.Right,
	Text = "0%",
	Parent = center,
})

-- Breathing brand while the loader is on screen.
task.spawn(function()
	while loader.Parent and brand.Parent do
		tween(brand, { TextTransparency = 0.18 }, 1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		task.wait(1.4)
		if not (loader.Parent and brand.Parent) then
			return
		end
		tween(brand, { TextTransparency = 0 }, 1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		task.wait(1.4)
	end
end)

local loadSteps = {
	{ "Initialising runtime", 0.14 },
	{ "Syncing game data", 0.34 },
	{ "Loading module registry", 0.58 },
	{ "Building interface", 0.84 },
	{ "Finalising", 1.00 },
}

local function runLoader()
	for _, step in next, loadSteps do
		if not loader.Parent then
			return
		end
		local message, progress = step[1], step[2]
		statusText.Text = message
		tween(barFill, { Size = UDim2.fromScale(progress, 1) }, 0.38, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		percentText.Text = math.floor(progress * 100) .. "%"
		task.wait(0.26)
	end

	task.wait(0.15)
	statusText.Text = "Welcome back"
	percentText.Text = "100%"
	task.wait(0.3)

	showWindow()
	setTab("home")

	tween(loader, { BackgroundTransparency = 1 }, 0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	tween(center, { Position = UDim2.new(0.5, 0, 0.5, -14) }, 0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	tween(loadGlow, { BackgroundTransparency = 1 }, 0.45)

	for _, element in next, center:GetDescendants() do
		if element:IsA("TextLabel") then
			tween(element, { TextTransparency = 1 }, 0.35)
		elseif element:IsA("GuiObject") then
			tween(element, { BackgroundTransparency = 1 }, 0.35)
		end
	end

	task.wait(0.5)
	loader:Destroy()

	state.booting = false

	local started = 0
	if Vexa.Demo.enabled then
		started = startAll(true)
		pushLog(string.format("Demo running - %d module(s) active", started), "success")
	end

	Notify(
		"success",
		"VEXA PETS",
		string.format("Ready in %.1fs - %d module(s) running", os.clock() - state.bootAt, started),
		4
	)
end

--==============================================================================
-- 13 -- TEARDOWN
--==============================================================================

function Vexa:Destroy()
	for _, module in next, Vexa.Modules do
		if module.enabled then
			module.enabled = false
			pcall(function()
				module:Stop()
			end)
		end
	end

	if antiAfkConnection then
		pcall(function()
			antiAfkConnection:Disconnect()
		end)
		antiAfkConnection = nil
	end

	for _, conn in next, connections do
		pcall(function()
			conn:Disconnect()
		end)
	end
	connections = {}

	closeOpenDropdown()

	pcall(function()
		screenGui:Destroy()
	end)

	if _G.VEXA == self then
		_G.VEXA = nil
	end
end

_G.VEXA = Vexa

--==============================================================================
-- 14 -- GO
--==============================================================================

task.spawn(runLoader)

return Vexa