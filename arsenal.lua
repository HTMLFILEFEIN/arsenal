local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

local ARSENAL_PLACE_ID = 286090429
local isArsenal = game.PlaceId == ARSENAL_PLACE_ID

local ESP_ENABLED = true
local HoldingRMB = false

local OUTER_FOV_DEG = 20
local AIMBOT_FOV_DEG = 10
local STICKY_THRESHOLD = 0.8

local currentTarget = nil

-- Outer circle (awareness)
local outerCircle = Drawing.new("Circle")
outerCircle.Color = Color3.fromRGB(255, 255, 255)
outerCircle.Thickness = 2
outerCircle.NumSides = 100
outerCircle.Radius = 0
outerCircle.Filled = false
outerCircle.Transparency = 0
outerCircle.Visible = false

-- Inner circle (aimbot zone)
local innerCircle = Drawing.new("Circle")
innerCircle.Color = Color3.fromRGB(180, 180, 255)
innerCircle.Thickness = 1.5
innerCircle.NumSides = 100
innerCircle.Radius = 0
innerCircle.Filled = false
innerCircle.Transparency = 0
innerCircle.Visible = false

local function shouldShowESP(player)
    if player == LocalPlayer then return false end
    if not ESP_ENABLED then return false end
    if isArsenal and player.Team == LocalPlayer.Team then return false end
    return true
end

local function updateESPVisibility(player)
    if not player.Character then return end
    
    local hl = player.Character:FindFirstChild("WhiteChamsESP")
    if hl then
        hl.Enabled = shouldShowESP(player)
    end
    
    local head = player.Character:FindFirstChild("Head")
    if head then
        local bb = head:FindFirstChild("NameESP")
        if bb then
            bb.Enabled = shouldShowESP(player)
        end
    end
end

local function createESP(player)
    if player == LocalPlayer then return end
    
    local function onCharAdded(char)
        task.wait(0.1)
        
        -- Clean old
        local oldHl = char:FindFirstChild("WhiteChamsESP")
        if oldHl then oldHl:Destroy() end
        
        local head = char:FindFirstChild("Head")
        if head and head:FindFirstChild("NameESP") then
            head.NameESP:Destroy()
        end
        
        -- White chams
        local highlight = Instance.new("Highlight")
        highlight.Name = "WhiteChamsESP"
        highlight.FillColor = Color3.new(1,1,1)
        highlight.OutlineColor = Color3.new(1,1,1)
        highlight.FillTransparency = 0.45
        highlight.OutlineTransparency = 0
        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        highlight.Adornee = char
        highlight.Parent = char
        highlight.Enabled = shouldShowESP(player)
        
        -- Name tag
        local bb = Instance.new("BillboardGui")
        bb.Name = "NameESP"
        bb.Size = UDim2.new(0, 220, 0, 50)
        bb.StudsOffset = Vector3.new(0, 3.2, 0)
        bb.AlwaysOnTop = true
        bb.LightInfluence = 0
        bb.Enabled = shouldShowESP(player)
        bb.Parent = char:WaitForChild("Head")
        
        local txt = Instance.new("TextLabel")
        txt.Size = UDim2.new(1,0,1,0)
        txt.BackgroundTransparency = 1
        txt.Text = player.DisplayName
        txt.TextColor3 = Color3.new(1,1,1)
        txt.TextStrokeTransparency = 0.4
        txt.TextStrokeColor3 = Color3.new(0,0,0)
        txt.Font = Enum.Font.GothamBold
        txt.TextSize = 16
        txt.TextXAlignment = Enum.TextXAlignment.Center
        txt.Parent = bb
        
        local nameConn = player:GetPropertyChangedSignal("DisplayName"):Connect(function()
            txt.Text = player.DisplayName
        end)
        
        local ancestryConn = char.AncestryChanged:Connect(function()
            if not char.Parent then
                highlight:Destroy()
                bb:Destroy()
                nameConn:Disconnect()
                ancestryConn:Disconnect()
            end
        end)
    end
    
    player.CharacterAdded:Connect(onCharAdded)
    if player.Character then onCharAdded(player.Character) end
    
    -- Team change listener
    player:GetPropertyChangedSignal("Team"):Connect(function()
        updateESPVisibility(player)
    end)
end

-- Aimbot loop
local function aimbotLoop()
    if not ESP_ENABLED or not HoldingRMB then
        currentTarget = nil
        return
    end
    
    local myChar = LocalPlayer.Character
    if not myChar or not myChar:FindFirstChild("HumanoidRootPart") then
        currentTarget = nil
        return
    end
    
    local rayParams = RaycastParams.new()
    rayParams.FilterDescendantsInstances = {myChar}
    rayParams.FilterType = Enum.RaycastFilterType.Blacklist
    
    local center = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
    local innerRadiusPx = (Camera.ViewportSize.X / 2) * math.tan(math.rad(AIMBOT_FOV_DEG / 2)) / math.tan(math.rad(Camera.FieldOfView / 2))
    
    local closestHead = nil
    local closestDist = math.huge
    
    for _, plr in Players:GetPlayers() do
        if plr == LocalPlayer then continue end
        if isArsenal and plr.Team == LocalPlayer.Team then continue end
        
        local char = plr.Character
        if not char then continue end
        
        local hum = char:FindFirstChild("Humanoid")
        if not hum or hum.Health <= 0 then continue end
        
        local head = char:FindFirstChild("Head")
        if not head then continue end
        
        local screen, onScreen = Camera:WorldToViewportPoint(head.Position)
        local pos2d = Vector2.new(screen.X, screen.Y)
        
        if onScreen and pos2d.X >= 0 and pos2d.X <= Camera.ViewportSize.X and pos2d.Y >= 0 and pos2d.Y <= Camera.ViewportSize.Y then
            local dist = (pos2d - center).Magnitude
            if dist > innerRadiusPx then continue end
            
            local dir = head.Position - Camera.CFrame.Position
            local res = workspace:Raycast(Camera.CFrame.Position, dir.Unit * dir.Magnitude, rayParams)
            local visible = not res or res.Instance:IsDescendantOf(char)
            
            if visible and dist < closestDist then
                closestDist = dist
                closestHead = head
            end
        end
    end
    
    if not closestHead then
        currentTarget = nil
        return
    end
    
    -- Sticky
    local aimAt = closestHead
    if currentTarget and currentTarget.Parent then
        local oldChar = currentTarget.Parent
        local oldPlr = Players:GetPlayerFromCharacter(oldChar)
        if oldPlr and oldPlr ~= LocalPlayer and (not isArsenal or oldPlr.Team ~= LocalPlayer.Team) then
            local oldHum = oldChar:FindFirstChild("Humanoid")
            if oldHum and oldHum.Health > 0 then
                local oldScreen, oldOn = Camera:WorldToViewportPoint(currentTarget.Position)
                local oldPos = Vector2.new(oldScreen.X, oldScreen.Y)
                local oldDist = (oldPos - center).Magnitude
                
                if oldOn and oldDist <= innerRadiusPx then
                    local dir = currentTarget.Position - Camera.CFrame.Position
                    local res = workspace:Raycast(Camera.CFrame.Position, dir.Unit * dir.Magnitude, rayParams)
                    local vis = not res or res.Instance:IsDescendantOf(oldChar)
                    
                    if vis and closestDist >= oldDist * STICKY_THRESHOLD then
                        aimAt = currentTarget
                    end
                end
            end
        end
    end
    
    local targetCF = CFrame.lookAt(Camera.CFrame.Position, aimAt.Position)
    Camera.CFrame = Camera.CFrame:Lerp(targetCF, 0.12)
    
    currentTarget = aimAt
end

-- Circles
RunService.Heartbeat:Connect(function()
    local center = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
    outerCircle.Position = center
    innerCircle.Position = center
    
    local outerR = (Camera.ViewportSize.X / 2) * math.tan(math.rad(OUTER_FOV_DEG / 2)) / math.tan(math.rad(Camera.FieldOfView / 2))
    outerCircle.Radius = math.floor(outerR)
    
    local innerR = (Camera.ViewportSize.X / 2) * math.tan(math.rad(AIMBOT_FOV_DEG / 2)) / math.tan(math.rad(Camera.FieldOfView / 2))
    innerCircle.Radius = math.floor(innerR)
    
    outerCircle.Visible = ESP_ENABLED
    innerCircle.Visible = ESP_ENABLED
end)

-- Initialization
for _, p in Players:GetPlayers() do
    createESP(p)
end
Players.PlayerAdded:Connect(createESP)

LocalPlayer:GetPropertyChangedSignal("Team"):Connect(function()
    for _, p in Players:GetPlayers() do
        if p ~= LocalPlayer then
            updateESPVisibility(p)
        end
    end
    currentTarget = nil
end)

UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.Insert then
        ESP_ENABLED = not ESP_ENABLED
        if not ESP_ENABLED then currentTarget = nil end
        for _, p in Players:GetPlayers() do
            if p ~= LocalPlayer then
                updateESPVisibility(p)
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
