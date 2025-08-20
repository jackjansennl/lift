local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

-- Configuration for smoothing. Higher values catch up to the server's true position faster.
local SMOOTHING_SPEED = 5 
local BIND_NAME = "SeatedLiftControllerUpdate" 

-- RemoteEvents and Values
local TakeControlEvent = ReplicatedStorage:WaitForChild("TakeControlOfLiftCarrier")
local LiftPathInfo = ReplicatedStorage:WaitForChild("LiftPathInfo", 30)
local PathDefinitionValue = LiftPathInfo:WaitForChild("PathDefinition")

-- Local State
local controlledCarrier = nil
local localPlayer = Players.LocalPlayer

-- These now act as our "master checkpoint" from the server
local lastServerPathPercent = 0
local timeOfLastServerUpdate = 0

-- Path Information
local pathDefinition = nil
local totalPathTime = 0
local speedPercentPerSecond = 0

-- Visual State for smooth interpolation
local currentVisualCFrame = CFrame.new()

-- The getTargetCFrameAtTime and decodePathData functions remain the same
local function getTargetCFrameAtTime(time, usePathTime)
	if not pathDefinition or #pathDefinition == 0 then return CFrame.new() end
	local pathTime = usePathTime or totalPathTime
	if not pathTime or pathTime <= 0 then return pathDefinition[1] and pathDefinition[1].startCFrame or CFrame.new() end
	local adjustedTime = time % pathTime
	local segment
	for i = 1, #pathDefinition do
		local seg = pathDefinition[i]
		if adjustedTime >= seg.startTime and adjustedTime < seg.endTime then segment = seg; break; end
	end
	if not segment then segment = pathDefinition[#pathDefinition] or { startCFrame = CFrame.new() } end
	local segmentDuration = segment.endTime - segment.startTime
	if segmentDuration <= 0 then return segment.startCFrame end
	local segmentProgress = (adjustedTime - segment.startTime) / segmentDuration
	local lerpedCFrame = segment.startCFrame:Lerp(segment.endCFrame, segmentProgress)
	if segment.applySag and segment.segmentSag and segment.segmentSag > 0 then
		local sagOffset = 4 * segment.segmentSag * segmentProgress * (1 - segmentProgress)
		return lerpedCFrame * CFrame.new(0, -sagOffset, 0)
	else
		return lerpedCFrame
	end
end

local function decodePathData()
	local success, result = pcall(function() return HttpService:JSONDecode(PathDefinitionValue.Value) end)
	if success then
		pathDefinition = result
		if #pathDefinition > 0 then
			totalPathTime = pathDefinition[#pathDefinition].endTime
			if totalPathTime > 0 then
				speedPercentPerSecond = 1.0 / totalPathTime
			end
		end
		print("LiftSeatedController: Path definition loaded.")
	else
		warn("LiftSeatedController: Failed to decode path definition! Error: ", result)
	end
end

-- This is our main update function, now much simpler and more robust.
local function updateSeatedController(deltaTime)
	if not controlledCarrier or not controlledCarrier.PrimaryPart or speedPercentPerSecond == 0 then return end

	-- 1. PREDICT using a stable clock
	-- We calculate our position based on how much time has passed since the LAST server update.
	-- This is perfectly smooth because os.clock() is stable and not dependent on deltaTime.
	local timeSinceUpdate = os.clock() - timeOfLastServerUpdate
	local predictedPercent = (lastServerPathPercent + (speedPercentPerSecond * timeSinceUpdate)) % 1.0

	-- 2. CALCULATE TARGET
	local timeForLookup = predictedPercent * totalPathTime
	local targetCFrame = getTargetCFrameAtTime(timeForLookup, totalPathTime)

	-- 3. INTERPOLATE VISUALS
	-- Our frame-rate independent Lerp will smoothly move the carrier to the target.
	-- If a new server packet arrives and changes our prediction, this Lerp will absorb the change seamlessly.
	local alpha = 1 - math.exp(-SMOOTHING_SPEED * deltaTime)
	currentVisualCFrame = currentVisualCFrame:Lerp(targetCFrame, alpha)
	controlledCarrier:SetPrimaryPartCFrame(currentVisualCFrame)
end

-- This connection now ONLY handles starting and stopping control.
TakeControlEvent.OnClientEvent:Connect(function(carrierModel, pathPercent)
	local humanoid = localPlayer.Character and localPlayer.Character:FindFirstChildOfClass("Humanoid")

	if carrierModel and pathPercent then -- Player sat down
		controlledCarrier = carrierModel

		-- Set the initial checkpoint from the server
		lastServerPathPercent = pathPercent
		timeOfLastServerUpdate = os.clock()

		if controlledCarrier.PrimaryPart then
			currentVisualCFrame = controlledCarrier.PrimaryPart.CFrame
		end

		if humanoid then humanoid.PlatformStand = true end

		RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value - 1, updateSeatedController)
		print("LiftSeatedController: Control bound to RenderStep.")

	else -- Player stood up
		if controlledCarrier then 
			RunService:UnbindFromRenderStep(BIND_NAME)
			print("LiftSeatedController: Control unbound from RenderStep.")
		end

		controlledCarrier = nil
		if humanoid then humanoid.PlatformStand = false end
	end
end)

-- This second connection is now solely responsible for updating our server checkpoint.
TakeControlEvent.OnClientEvent:Connect(function(_, pathPercent)
	if controlledCarrier and pathPercent then
		-- A new update arrived. We just update our reference point.
		-- The main loop will now calculate its prediction from this new, more accurate checkpoint.
		lastServerPathPercent = pathPercent
		timeOfLastServerUpdate = os.clock()
	end
end)

-- Initial setup
decodePathData()
PathDefinitionValue.Changed:Connect(decodePathData)

print("Lift Seated Controller (Network Resilient) is active and ready.")
