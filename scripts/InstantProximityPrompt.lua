local ProximityPromptService = game:GetService("ProximityPromptService")

local processed = setmetatable({}, { __mode = "k" })

local function instant(prompt)
	if not prompt:IsA("ProximityPrompt") then
		return
	end

	processed[prompt] = true
	prompt.HoldDuration = 0
end

-- Existing prompts, chunked
task.spawn(function()
	local list = workspace:GetDescendants()

	for i, obj in ipairs(list) do
		if obj:IsA("ProximityPrompt") then
			instant(obj)
		end

		if i % 1000 == 0 then
			task.wait()
		end
	end
end)

-- New prompts
workspace.DescendantAdded:Connect(function(obj)
	if obj:IsA("ProximityPrompt") then
		instant(obj)
	end
end)

-- Most important part: prompts that appear / stream in / get reset
ProximityPromptService.PromptShown:Connect(function(prompt)
	instant(prompt)

	-- tiny delayed re-apply in case the game changes it right as it appears
	task.defer(function()
		if prompt and prompt.Parent then
			prompt.HoldDuration = 0
		end
	end)
end)
print("Made all prompts instant!")
