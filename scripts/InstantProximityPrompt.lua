local function makePromptInstant(prompt)
	if not prompt:IsA("ProximityPrompt") then
		return
	end

	prompt.HoldDuration = 0

	prompt:GetPropertyChangedSignal("HoldDuration"):Connect(function()
		if prompt.HoldDuration ~= 0 then
			prompt.HoldDuration = 0
		end
	end)
end

for _, obj in ipairs(workspace:GetDescendants()) do
	makePromptInstant(obj)
end

workspace.DescendantAdded:Connect(function(obj)
	makePromptInstant(obj)
end)
