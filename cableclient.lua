
-- Final Script with Simplified and Corrected CFrame Logic

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

-- Get the event and the mesh template from ReplicatedStorage
local RenderCablesEvent = ReplicatedStorage:WaitForChild("RenderCablesEvent")
local cableTemplate = ReplicatedStorage:WaitForChild("CableMeshTemplate")

--- CLIENT-SIDE VISUAL CONFIGURATION ---
local CABLE_DIAMETER = 0.2
local CABLE_COLOR = Color3.new(0.667063, 0.643488, 0.656733)
local CABLE_MATERIAL = Enum.Material.Fabric
local INTERPOLATION_FACTOR = 0.25
local SNAP_DISTANCE = 10

local cablesFolder = Instance.new("Folder")
cablesFolder.Name = "LiftCablesClient"
cablesFolder.Parent = Workspace

local activeCableParts = {}

--- PART CREATION ---
local function getOrCreatePart(segmentId, partIndex)
	if not activeCableParts[segmentId] then
		activeCableParts[segmentId] = {}
	end
	if activeCableParts[segmentId][partIndex] then return end

	local cablePart = cableTemplate:Clone()
	cablePart.Name = "Cable_" .. segmentId .. "_" .. tostring(partIndex)
	cablePart.Color = CABLE_COLOR
	cablePart.Material = CABLE_MATERIAL
	cablePart.Parent = cablesFolder

	activeCableParts[segmentId][partIndex] = {
		part = cablePart,
		currentCFrame = CFrame.new(0, -20000, 0),
		targetCFrame = CFrame.new(0, -20000, 0),
		currentSize = Vector3.new(0, CABLE_DIAMETER, CABLE_DIAMETER),
		targetSize = Vector3.new(0, CABLE_DIAMETER, CABLE_DIAMETER)
	}
end

--- TRANSFORM CALCULATION ---
local function calculateTransformBetweenPoints(posA, posB, diameter)
	local vecAB = posB - posA
	local distance = vecAB.Magnitude
	local midpoint = posA + (vecAB / 2)

	-- SIZE: The custom mesh has its length on the X-axis. This is correct.
	local size = Vector3.new(distance, diameter, diameter)

	-- *** THE NEW, SIMPLER CFRAME LOGIC ***
	-- Step 1: Aim the part's Front (-Z axis) along the cable. This is very robust.
	local aimAtTarget = CFrame.new(midpoint, posB)

	-- Step 2: Apply a simple -90 degree swivel around the Y-axis.
	-- This turns the part so its Right side (+X axis) points where the Front was aiming.
	local swivelToAlignX = CFrame.Angles(0, math.rad(90), 0)

	-- Combine them to get the final, correct rotation.
	local cframe = aimAtTarget * swivelToAlignX

	return cframe, size
end

--- EVENT HANDLER ---
RenderCablesEvent.OnClientEvent:Connect(function(changedSegmentsData)
	if not next(changedSegmentsData) then
		for _, segment in pairs(activeCableParts) do
			for _, partData in pairs(segment) do
				partData.part:Destroy()
			end
		end
		activeCableParts = {}
		return
	end

	for segmentId, segmentWorldPositions in pairs(changedSegmentsData) do
		if not segmentWorldPositions then
			if activeCableParts[segmentId] then
				for _, partData in pairs(activeCableParts[segmentId]) do
					partData.part:Destroy()
				end
				activeCableParts[segmentId] = nil
			end
		else
			local partsNeededInSegment = {}
			for pointIdx = 1, #segmentWorldPositions - 1 do
				local posA = segmentWorldPositions[pointIdx]
				local posB = segmentWorldPositions[pointIdx + 1]

				if posA and posB and (posA - posB).Magnitude > 0.01 then
					getOrCreatePart(segmentId, pointIdx)
					local partData = activeCableParts[segmentId][pointIdx]
					local targetCFrame, targetSize = calculateTransformBetweenPoints(posA, posB, CABLE_DIAMETER)
					partData.targetCFrame = targetCFrame
					partData.targetSize = targetSize
					if (partData.currentCFrame.Position - partData.targetCFrame.Position).Magnitude > SNAP_DISTANCE then
						partData.currentCFrame = targetCFrame
						partData.currentSize = targetSize
					end
				end
				partsNeededInSegment[pointIdx] = true
			end
			if activeCableParts[segmentId] then
				for partIndex, partData in pairs(activeCableParts[segmentId]) do
					if not partsNeededInSegment[partIndex] then
						partData.part:Destroy()
						activeCableParts[segmentId][partIndex] = nil
					end
				end
			end
		end
	end
end)

--- RENDER LOOP ---
RunService.RenderStepped:Connect(function(deltaTime)
	local alpha = math.min(INTERPOLATION_FACTOR * deltaTime * 60, 1)
	for _, segmentData in pairs(activeCableParts) do
		for _, partData in pairs(segmentData) do
			if partData.part and partData.part.Parent then
				partData.currentCFrame = partData.currentCFrame:Lerp(partData.targetCFrame, alpha)
				partData.currentSize = partData.currentSize:Lerp(partData.targetSize, alpha)
				partData.part.CFrame = partData.currentCFrame
				partData.part.Size = partData.currentSize
			end
		end
	end
end)

print("Final Cable Client (Simple Rotation) is active.")





