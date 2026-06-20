-- LocalScript (put in StarterPlayer > StarterPlayerScripts)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local localPlayer = Players.LocalPlayer
local highlightColor = Color3.fromRGB(255, 0, 0) -- Red

local espData = {} -- Stores highlight and billboard per character

local function createESP(character, player)
    if not character or espData[character] then return end
    
    local root = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("Head", 2)
    if not root then return end

    -- Red Highlight
    local highlight = Instance.new("Highlight")
    highlight.Name = "RedPlayerHighlight"
    highlight.FillColor = highlightColor
    highlight.OutlineColor = highlightColor
    highlight.FillTransparency = 0.7
    highlight.OutlineTransparency = 0
    highlight.Adornee = character
    highlight.Parent = character

    -- BillboardGui for Name + Distance
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "PlayerESP"
    billboard.Adornee = character:WaitForChild("Head")
    billboard.Size = UDim2.new(0, 250, 0, 80)
    billboard.StudsOffset = Vector3.new(0, 4, 0)
    billboard.AlwaysOnTop = true
    billboard.LightInfluence = 0
    billboard.Parent = character

    -- Distance (Top)
    local distanceLabel = Instance.new("TextLabel")
    distanceLabel.Size = UDim2.new(1, 0, 0.5, 0)
    distanceLabel.BackgroundTransparency = 1
    distanceLabel.TextColor3 = Color3.fromRGB(255, 50, 50)
    distanceLabel.TextStrokeTransparency = 0
    distanceLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
    distanceLabel.Font = Enum.Font.GothamBold
    distanceLabel.TextSize = 16
    distanceLabel.Text = "0 studs"
    distanceLabel.Parent = billboard

    -- Name (Bottom)
    local nameLabel = Instance.new("TextLabel")
    nameLabel.Size = UDim2.new(1, 0, 0.5, 0)
    nameLabel.Position = UDim2.new(0, 0, 0.5, 0)
    nameLabel.BackgroundTransparency = 1
    nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    nameLabel.TextStrokeTransparency = 0
    nameLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.TextSize = 18
    nameLabel.Text = player and player.Name or "Unknown"
    nameLabel.Parent = billboard

    espData[character] = {
        highlight = highlight,
        billboard = billboard,
        distanceLabel = distanceLabel
    }
end

local function updateDistances()
    for character, data in pairs(espData) do
        if character and character.Parent then
            local root = character:FindFirstChild("HumanoidRootPart")
            local localRoot = localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart")
            
            if root and localRoot then
                local distance = (root.Position - localRoot.Position).Magnitude
                data.distanceLabel.Text = string.format("%.0f studs", distance)
            end
        else
            -- Cleanup
            if data.highlight then data.highlight:Destroy() end
            if data.billboard then data.billboard:Destroy() end
            espData[character] = nil
        end
    end
end

local function onCharacterAdded(character, player)
    createESP(character, player)
end

local function setupPlayer(player)
    if player == localPlayer then return end
    
    if player.Character then
        createESP(player.Character, player)
    end
    player.CharacterAdded:Connect(function(char)
        onCharacterAdded(char, player)
    end)
end

-- Setup existing players
for _, player in ipairs(Players:GetPlayers()) do
    setupPlayer(player)
end

Players.PlayerAdded:Connect(setupPlayer)

-- Update distances every frame
RunService.RenderStepped:Connect(updateDistances)

print("Red ESP with name + distance enabled (fixed)")
