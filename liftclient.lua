-- In StarterPlayer.StarterPlayerScripts > LiftClientInterpolator (LocalScript)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

-- Wait for the necessary assets to exist
local CFrameUpdateEvent = ReplicatedStorage:WaitForChild("LiftCFrameUpdate", 30)
local activeGripsParent = Workspace:WaitForChild("ActiveLiftGrips", 30)

-- Configuration
local INTERPOLATION_FACTOR = 0.25 
local MAX_INTERPOLATION_DISTANCE = 50 

-- HIERARCHY CONFIGURATION
local GRIP_HIERARCHY = {"Grip", "GripPart"}
local CABIN_HIERARCHY = {"Cabin", "PrimaryPart"}

-- This table stores data for carriers we are animating
local activeGripsData = {}
local localPlayer = Players.LocalPlayer

-- This function finds a carrier model using its unique ID attribute
local function getGripModelByAttributeId(id)
	for _, model in ipairs(activeGripsParent:GetChildren()) do
		if model:GetAttribute("LiftGripID") == id then
			return model
		end
	end
	return nil
end

-- This helper gets a specific part from a model using a hierarchy table
local function getPartFromModel(model, hierarchy)
	if not model then return nil end
	local currentInstance = model
	for _, childName in ipairs(hierarchy) do
		local foundChild = currentInstance:FindFirstChild(childName, true)
		if not foundChild then return nil end
		currentInstance = foundChild
	end
	return currentInstance:IsA("BasePart") and currentInstance or nil
end

-- Listen for the batch of CFrame updates from the server
CFrameUpdateEvent.OnClientEvent:Connect(function(updates)
	for _, update in ipairs(updates) do
		local gripId = update.id

		if not activeGripsData[gripId] then
			local gripModel = getGripModelByAttributeId(gripId)
			local gripPart = getPartFromModel(gripModel, GRIP_HIERARCHY)
			local cabinPart = getPartFromModel(gripModel, CABIN_HIERARCHY)

			if gripPart then
				activeGripsData[gripId] = {
					part = gripPart,
					cabin = cabinPart,
					currentGripCFrame = gripPart.CFrame,
					targetGripCFrame = update.gripCFrame,
					currentCabinCFrame = cabinPart and cabinPart.CFrame or nil,
					targetCabinCFrame = update.cabinCFrame,
				}
			end
		else
			local data = activeGripsData[gripId]
			-- IMPORTANT: We ONLY update the target CFrame. We do not touch the part's CFrame here.
			data.targetGripCFrame = update.gripCFrame
			if data.cabin then
				data.targetCabinCFrame = update.cabinCFrame
			end
		end
	end
end)

-- This loop runs on every frame to create smooth visual movement
RunService.RenderStepped:Connect(function(deltaTime)
	-- First, check if the local player is currently seated in one of the carriers
	local seatedGripId = nil
	if localPlayer.Character then
		local humanoid = localPlayer.Character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.SeatPart and humanoid.SeatPart:IsDescendantOf(activeGripsParent) then
			-- We are seated. Find the carrier's root model to get its ID.
			local currentPart = humanoid.SeatPart
			while currentPart and currentPart.Parent ~= activeGripsParent do
				currentPart = currentPart.Parent
			end
			if currentPart then
				seatedGripId = currentPart:GetAttribute("LiftGripID")
			end
		end
	end

	for gripId, data in pairs(activeGripsData) do
		-- If this is the carrier we are seated in, DO NOTHING.
		-- Let the default Roblox replication handle its position, which you found to be smoothest.
		if gripId == seatedGripId then
			-- We must also update the 'current' CFrame here, so that if we stand up,
			-- the interpolation doesn't jump from an old visual position.
			data.currentGripCFrame = data.part.CFrame
			if data.cabin and data.currentCabinCFrame then
				data.currentCabinCFrame = data.cabin.CFrame
			end
			continue -- Skip all interpolation logic for this carrier
		end

		if data.part and data.part.Parent then
			-- For all other carriers, smoothly interpolate them as a spectator.
			data.currentGripCFrame = data.currentGripCFrame:Lerp(data.targetGripCFrame, INTERPOLATION_FACTOR)
			data.part.CFrame = data.currentGripCFrame

			if data.cabin and data.currentCabinCFrame and data.targetCabinCFrame then
				data.currentCabinCFrame = data.currentCabinCFrame:Lerp(data.targetCabinCFrame, INTERPOLATION_FACTOR)
				data.cabin.CFrame = data.currentCabinCFrame
			end
		else
			-- If the grip part has been destroyed, remove it from our list
			activeGripsData[gripId] = nil
		end
	end
end)

print("Lift Client Interpolator with 'Hands-Off' Seated Logic is active.")
