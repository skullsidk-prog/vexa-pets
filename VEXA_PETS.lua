--[[
VEXA PETS - Debug/Compatibility Edition for Injectors
By: VEXA Development
-------------------------------------------
This version includes extra error handling and logging
to help troubleshoot why the GUI might not appear.
-------------------------------------------
Press RightShift to toggle the GUI.
-------------------------------------------
]]

-- Services
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")

-- Wait for LocalPlayer
local LocalPlayer
local function waitForPlayer()
    LocalPlayer = Players.LocalPlayer
    if not LocalPlayer then
        Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
        LocalPlayer = Players.LocalPlayer
    end
end
waitForPlayer()

-- Create ScreenGui reliably
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "VEXA_PETS"
ScreenGui.ResetOnSpawn = false
ScreenGui.IgnoreGuiInset = true
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.DisplayOrder = 9999

-- Try multiple ways to get a parent GUI
local function getParentGui()
    -- Try gethui (common in executors)
    local ok, result = pcall(function()
        if gethui then
            return gethui()
        end
        return nil
    end)
    if ok and result then
        return result
    end
    
    -- Try CoreGui
    ok, result = pcall(function()
        return game:GetService("CoreGui")
    end)
    if ok and result then
        return result
    end
    
    -- Fallback: StarterGui (most reliable)
    return game:GetService("StarterGui")
end

local ok, parentGui = pcall(getParentGui)
if ok and parentGui then
    ScreenGui.Parent = parentGui
    print("[VEXA] GUI parented to: " .. tostring(parentGui))
else
    -- Last resort: try PlayerGui directly
    local playerGui = Instance.new("ScreenGui")
    playerGui.Name = "VEXA_PETS_Fallback"
    playerGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui", 10)
    print("[VEXA] Using fallback parent: PlayerGui")
    ScreenGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

-- Now the rest of the script...
-- MINIMAL VERSION - just the essentials so we can see if GUI appears
-- If this works, we can add features back

-- Simple notification function
local function ShowMessage(title, body, duration)
    duration = duration or 3
    -- Try to create a simple text label
    local gui = ScreenGui:FindFirstChildOfClass("ScreenGui")
    if gui then
        local frame = Instance.new("Frame")
        frame.Size = UDim2.new(0, 200, 0, 50)
        frame.Position = UDim2.new(0.5, -100, 0.5, -25)
        frame.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
        frame.BorderSizePixel = 0
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 8)
        corner.Parent = frame
        local text = Instance.new("TextLabel")
        text.Size = UDim2.new(1, -16, 1, -16)
        text.Position = UDim2.new(0, 8, 0, 8)
        text.BackgroundTransparency = 1
        text.TextColor3 = Color3.fromRGB(237, 239, 248)
        text.TextStrokeTransparency = 0.5
        text.TextScaled = true
        text.Text = title .. ": " .. body
        text.Parent = frame
        frame.Parent = gui
        game:GetService("Debris"):AddItem(frame, duration)
    end
end

-- Simple toggle
local toggled = false
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if input.KeyCode == Enum.KeyCode.RightShift then
        toggled = not toggled
        if toggled then
            ScreenGui.Enabled = true
            ShowMessage("VEXA PETS", "GUI Enabled - RightShift to toggle off", 3)
        else
            ScreenGui.Enabled = false
            ShowMessage("VEXA PETS", "GUI Disabled", 2)
        end
    end
end)

-- Print success
print("[VEXA] Script loaded - GUI creation attempted")
ShowMessage("VEXA PETS", "Script loaded - check output for details", 4)
