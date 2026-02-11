local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

local ARSENAL_PLACE_ID = 286090429
local isArsenal = game.PlaceId == ARSENAL_PLACE_ID

local ESP_ENABLED = true
local HoldingRMB = false
local OUTER_FOV = 20  -- Outer awareness circle
local AIMBOT_FOV = 10  -- Aimbot detection circle
local currentTarget = nil
local STICKY_THRESHOLD = 0.8

-- Outer FOV Circle (outline)
local fovCircle = Drawing.new("Circle")
fovCircle.Color = Color3.fromRGB(255, 255, 255)
fovCircle.Thickness = 2
fovCircle.NumSides = 64
fovCircle.Radius = 0
fovCircle.Filled = false
fovCircle.Transparency = 0
fovCircle.Visible = false

-- Inner Aimbot FOV Circle (filled)
local aimbotCircle = Drawing.new("Circle")
aimbotCircle.Color = Color3.fromRGB(255, 255, 255)
aimbotCircle.Thickness = 1
aimbotCircle.NumSides = 64
aimbotCircle.Radius = 0
aimbotCircle.Filled = true
aimbotCircle.Transparency = 0.6  -- Semi-transparent white
aimbotCircle.Visible = false

local function updateESPVisibility(player)
    if player == LocalPlayer or not player.Character then return end
    
    local highlight = player.Character:FindFirstChild("WhiteChamsESP")
    local head = player.Character:FindFirstChild("Head")
    local billboard = head and head:FindFirstChild("DisplayNameESP")
    
    local shouldShow = ESP_ENABLED and (not isArsenal or player.Team ~= LocalPlayer.Team)
    
    if highlight then
        highlight.Enabled = shouldShow
    end
    if billboard then
        billboard.Enabled = shouldShow
    end
end

local function createESP(player)
    if player == LocalPlayer then return end
    
    local function onCharacterAdded(character)
        local oldHighlight = character:FindFirstChild("WhiteChamsESP")
        if oldHighlight then oldHighlight:Destroy() end
        local head = character:FindFirstChild("Head")
        local oldBillboard = head and head:FindFirstChild("DisplayNameESP")
        if oldBillboard then oldBillboard:Destroy() end
        
        local highlight = Instance.new("Highlight")
        highlight.Name = "WhiteChamsESP"
        highlight.FillColor = Color3.new(1, 1, 1)
        highlight.OutlineColor = Color3.new(1, 1, 1)
        highlight.FillTransparency = 0.4
        highlight.OutlineTransparency = 0
        highlight.Enabled = false
        highlight.Parent = character
        
        local newHead = character:WaitForChild("Head")
        
        local billboardGui = Instance.new("BillboardGui")
        billboardGui.Name = "DisplayNameESP"
        billboardGui.Size = UDim2.new(0, 200, 0, 50)
        billboardGui.StudsOffset = Vector3.new(0, 3, 0)
        billboardGui.LightInfluence = 0
        billboardGui.AlwaysOnTop = true
        billboardGui.Enabled = false
        billboardGui.Parent = newHead
        
        local textLabel = Instance.new("TextLabel")
        textLabel.Size = UDim2.new(1, 0, 1, 0)
        textLabel.BackgroundTransparency = 1
        textLabel.Text = player.DisplayName
        textLabel.TextColor3 = Color3.new(1, 1, 1)
        textLabel.TextStrokeTransparency = 0
        textLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
        textLabel.Font = Enum.Font.GothamBold
        textLabel.TextSize = 16
        textLabel.TextXAlignment = Enum.TextXAlignment.Center
        textLabel.Parent = billboardGui
        
        local nameUpdateConnection = player:GetPropertyChangedSignal("DisplayName"):Connect(function()
            if textLabel then textLabel.Text = player.DisplayName end
        end)
        
        local ancestryChanged = character.AncestryChanged:Connect(function()
            if not character.Parent then
                highlight:Destroy()
                billboardGui:Destroy()
                if nameUpdateConnection then nameUpdateConnection:Disconnect() end
                ancestryChanged:Disconnect()
            end
        end)
        
        updateESPVisibility(player)
    end
    
    player.CharacterAdded:Connect(onCharacterAdded)
    if player.Character then onCharacterAdded(player.Character) end
    
    player:GetPropertyChangedSignal("Team"):Connect(function()
        updateESPVisibility(player)
    end)
end

-- Aimbot Loop (10° inner FOV)
local function aimbotLoop()
    if not ESP_ENABLED or not HoldingRMB then 
        currentTarget = nil
        return 
    end
    
    local localChar = LocalPlayer.Character
    if not localChar or not localChar:FindFirstChild("HumanoidRootPart") then 
        currentTarget = nil
        return 
    end
    
    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Blacklist
    rayParams.FilterDescendantsInstances = {localChar}
    
    local center = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
    local aimbotRadius = (Camera.ViewportSize.X / 2) * (math.tan(math.rad(AIMBOT_FOV / 2)) / math.tan(math.rad(Camera.FieldOfView / 2)))
    
    local closestHead = nil
    local closestScreenDist = math.huge
    for _, player in ipairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end
        if isArsenal and player.Team == LocalPlayer.Team then continue end
        
        local char = player.Character
        if not char then continue end
        
        local humanoid = char:FindFirstChild("Humanoid")
        if not humanoid or humanoid.Health <= 0 then continue end
        
        local head = char:FindFirstChild("Head")
        if not head then continue end
        
        local screenPoint, inFront = Camera:WorldToViewportPoint(head.Position)
        local screenPos = Vector2.new(screenPoint.X, screenPoint.Y)
        local onScreen = inFront and screenPos.X >= 0 and screenPos.X <= Camera.ViewportSize.X and 
                         screenPos.Y >= 0 and screenPos.Y <= Camera.ViewportSize.Y
        
        if onScreen then
            local direction = head.Position - Camera.CFrame.Position
            local raycastResult = workspace:Raycast(Camera.CFrame.Position, direction.Unit * direction.Magnitude, rayParams)
            local visible = (not raycastResult or raycastResult.Instance:IsDescendantOf(char))
            
            if visible then
                local screenDist = (screenPos - center).Magnitude
                if screenDist < aimbotRadius and screenDist < closestScreenDist then
                    closestScreenDist = screenDist
                    closestHead = head
                end
            end
        end
    end
    
    if not closestHead then 
        currentTarget = nil
        return 
    end
    
    -- Sticky Logic
    local aimHead = closestHead
    if currentTarget and currentTarget.Parent then
        local char = currentTarget.Parent
        local player = Players:GetPlayerFromCharacter(char)
        if player and player ~= LocalPlayer and (not isArsenal or player.Team ~= LocalPlayer.Team) then
            local humanoid = char:FindFirstChild("Humanoid")
            if humanoid and humanoid.Health > 0 then
                local screenPoint, inFront = Camera:WorldToViewportPoint(currentTarget.Position)
                if inFront then
                    local screenPos = Vector2.new(screenPoint.X, screenPoint.Y)
                    local onScreen = screenPos.X >= 0 and screenPos.X <= Camera.ViewportSize.X and 
                                     screenPos.Y >= 0 and screenPos.Y <= Camera.ViewportSize.Y
                    local screenDist = (screenPos - center).Magnitude
                    if onScreen and screenDist < aimbotRadius then
                        local direction = currentTarget.Position - Camera.CFrame.Position
                        local raycastResult = workspace:Raycast(Camera.CFrame.Position, direction.Unit * direction.Magnitude, rayParams)
                        local visible = (not raycastResult or raycastResult.Instance:IsDescendantOf(char))
                        if visible and closestScreenDist >= (screenDist * STICKY_THRESHOLD) then
                            aimHead = currentTarget
                        end
                    end
                end
            end
        end
    end
    
    local targetCFrame = CFrame.lookAt(Camera.CFrame.Position, aimHead.Position)
    Camera.CFrame = Camera.CFrame:Lerp(targetCFrame, 0.12)
    
    currentTarget = aimHead
end

-- FOV Circles Update Loop (BOTH ALWAYS VISIBLE when ESP on!)
RunService.Heartbeat:Connect(function()
    local center = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
    fovCircle.Position = center
    aimbotCircle.Position = center
    
    local outerRadius = (Camera.ViewportSize.X / 2) * (math.tan(math.rad(OUTER_FOV / 2)) / math.tan(math.rad(Camera.FieldOfView / 2)))
    fovCircle.Radius = math.floor(outerRadius)
    
    local innerRadius = (Camera.ViewportSize.X / 2) * (math.tan(math.rad(AIMBOT_FOV / 2)) / math.tan(math.rad(Camera.FieldOfView / 2)))
    aimbotCircle.Radius = math.floor(innerRadius)
    
    fovCircle.Visible = ESP_ENABLED
    aimbotCircle.Visible = ESP_ENABLED  -- NOW ALWAYS ON (with ESP)!
end)

-- Apply ESP
for _, player in ipairs(Players:GetPlayers()) do
    createESP(player)
end
Players.PlayerAdded:Connect(createESP)

LocalPlayer:GetPropertyChangedSignal("Team"):Connect(function()
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            updateESPVisibility(player)
        end
    end
    currentTarget = nil
end)

-- Inputs
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode.Insert then
        ESP_ENABLED = not ESP_ENABLED
        if not ESP_ENABLED then currentTarget = nil end
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer then
                updateESPVisibility(player)
            end
        end
    elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
        HoldingRMB = true
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        HoldingRMB = false
        currentTarget = nil
    end
end)

RunService.RenderStepped:Connect(aimbotLoop)
