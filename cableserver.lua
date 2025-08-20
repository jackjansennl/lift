-- In ServerScriptService > CableServer (Script) -- Final Stabilized Version

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local RenderCablesEvent = ReplicatedStorage:WaitForChild("RenderCablesEvent")
local CarriersRegeneratedSignal = ReplicatedStorage:WaitForChild("CarriersRegeneratedSignal")

--- GLOBAL CONFIGURATION ---
local ENABLE_DEBUG_LOGGING = false
local UPDATE_INTERVAL = 0.02
local SEGMENT_BUFFER_DISTANCE = 0
local MAX_LATERAL_DISTANCE = 9
local CABLE_SUBDIVISION_POINTS = 0
local CABLE_POSITION_CHANGE_TOLERANCE = 0

local function debugPrint(...)
	if ENABLE_DEBUG_LOGGING then
		print(...)
	end
end

--- FOLDER AND OBJECT SETUP ---
local towersFolder = workspace.gtowers
local gipfelSpeedValue = workspace:FindFirstChild("GipfelSpeed")
local chairsRoot = nil

--- CACHED DATA TABLES ---
local uphillTowers = {}
local downhillTowers = {}
local allChairGripAttachments = {}
local previousSegmentData = {}
local phantomGripStates = {}

--- HELPER FUNCTIONS ---

local function setupTowers()
	uphillTowers = {}
	downhillTowers = {}

	for _, towerPart in ipairs(towersFolder:GetChildren()) do
		if towerPart:IsA("BasePart") then
			local towerTopAttachment = towerPart:FindFirstChild("TopAttachment")
			if not towerTopAttachment or not towerTopAttachment:IsA("Attachment") then
				towerTopAttachment = Instance.new("Attachment")
				towerTopAttachment.Name = "TopAttachment"
				towerTopAttachment.Parent = towerPart
				towerTopAttachment.Position = Vector3.new(0, towerPart.Size.Y / 2, 0)
			end

			local lowerCaseName = towerPart.Name:lower()
			if lowerCaseName:find("uphill") then
				table.insert(uphillTowers, towerPart)
			elseif lowerCaseName:find("downhill") then
				table.insert(downhillTowers, towerPart)
			end
		end
	end

	local function sortTowers(a, b)
		local numA = tonumber(a.Name:match("%d+")) or 0
		local numB = tonumber(b.Name:match("%d+")) or 0
		if numA ~= numB then
			return numA < numB
		else
			return a.Name < b.Name
		end
	end

	table.sort(uphillTowers, sortTowers)
	table.sort(downhillTowers, sortTowers)
end

local function updatePhantomGripStates(dt)
	local currentSpeed = (gipfelSpeedValue and gipfelSpeedValue.Value) or 0
	if currentSpeed < 0.01 then return end

	local function processTowerList(towersList)
		for i = 1, #towersList - 1 do
			local towerA, towerB = towersList[i], towersList[i+1]

			-- #################### START OF STABILITY FIX ####################
			-- Added a check to ensure towers exist before using them. This prevents crashes
			-- if a tower is deleted while the script is running.
			if not towerA or not towerB then
				continue
			end
			-- #################### END OF STABILITY FIX ####################

			local numA = tonumber(towerA.Name:match("%d+"))
			local numB = tonumber(towerB.Name:match("%d+"))

			if numA and numB and numA == numB then
				local segmentId = towerA.Name .. "_" .. towerB.Name
				local segmentLength = (towerA.Position - towerB.Position).Magnitude

				if segmentLength > 0 then
					if not phantomGripStates[segmentId] then
						phantomGripStates[segmentId] = { currentDistance = 0 }
					end

					local state = phantomGripStates[segmentId]
					state.currentDistance = (state.currentDistance + (currentSpeed * dt)) % segmentLength
				end
			end
		end
	end

	processTowerList(uphillTowers)
	processTowerList(downhillTowers)
end

local function findChairGripAttachment(chairModel)
	local grip = chairModel:FindFirstChild("Grip", true)
	if grip and grip:IsA("Model") then
		local gripPart = grip:FindFirstChild("GripPart", true)
		if gripPart and gripPart:IsA("BasePart") then
			local gripAttachment = gripPart:FindFirstChild("GripAttachment")
			if not gripAttachment or not gripAttachment:IsA("Attachment") then
				gripAttachment = Instance.new("Attachment")
				gripAttachment.Name = "GripAttachment"
				gripAttachment.Parent = gripPart
				gripAttachment.Position = Vector3.new(0, 0, 0)
			end
			return gripAttachment
		end
	end
	return nil
end

local function setupChairs()
	allChairGripAttachments = {}
	if chairsRoot and (chairsRoot:IsA("Folder") or chairsRoot:IsA("Model")) then
		for _, chairModel in ipairs(chairsRoot:GetChildren()) do
			if chairModel:IsA("Model") then
				local gripAtt = findChairGripAttachment(chairModel)
				if gripAtt then
					table.insert(allChairGripAttachments, gripAtt)
				end
			end
		end
		debugPrint("DEBUG: Found", #allChairGripAttachments, "valid chair grip attachments.")
	end
end

local function areSegmentPointsEqual(pointsA, pointsB)
	if not pointsA or not pointsB or #pointsA ~= #pointsB then return false end
	for i = 1, #pointsA do
		if (pointsA[i] - pointsB[i]).Magnitude > CABLE_POSITION_CHANGE_TOLERANCE then
			return false
		end
	end
	return true
end

local function buildSegmentsFromTowerList(towersList, pathDescription)
	local currentSegments = {}
	for i = 1, #towersList - 1 do
		local towerA, towerB = towersList[i], towersList[i + 1]

		-- Also adding the safety check here for good measure.
		if not towerA or not towerB then
			continue
		end

		local towerA_Att, towerB_Att = towerA:FindFirstChild("TopAttachment"), towerB:FindFirstChild("TopAttachment")
		local segmentId = pathDescription .. "_" .. towerA.Name .. "_" .. towerB.Name

		if not towerA_Att or not towerB_Att then continue end

		local majorPointsInSegment = { towerA_Att }
		local towerA_Pos, towerB_Pos = towerA_Att.WorldPosition, towerB_Att.WorldPosition

		local numA = tonumber(towerA.Name:match("%d+"))
		local numB = tonumber(towerB.Name:match("%d+"))

		if not numA or not numB or numA ~= numB then
			-- ### DEFAULT SAG LOGIC ###
			local segmentChairsAttachments = {}
			local segmentDirection = (towerB_Pos - towerA_Pos).Unit

			for _, chairGripAttachment in ipairs(allChairGripAttachments) do
				if chairGripAttachment and chairGripAttachment.Parent and chairGripAttachment.Parent.Parent then
					local chairPos = chairGripAttachment.WorldPosition
					local vecAToChair = chairPos - towerA_Pos

					if vecAToChair:Dot(segmentDirection) >= -SEGMENT_BUFFER_DISTANCE and (chairPos - towerB_Pos):Dot(segmentDirection) <= SEGMENT_BUFFER_DISTANCE then
						local segmentVector = towerB_Pos - towerA_Pos
						if segmentVector.Magnitude > 0 then
							local closestPointOnSegment = towerA_Pos + segmentVector * math.clamp(vecAToChair:Dot(segmentVector) / segmentVector.Magnitude^2, 0, 1)
							if (chairPos - closestPointOnSegment).Magnitude <= MAX_LATERAL_DISTANCE then
								table.insert(segmentChairsAttachments, chairGripAttachment)
							end
						end
					end
				end
			end
			table.sort(segmentChairsAttachments, function(a, b) return (a.WorldPosition - towerA_Pos):Dot(segmentDirection) < (b.WorldPosition - towerA_Pos):Dot(segmentDirection) end)
			for _, chairAtt in ipairs(segmentChairsAttachments) do table.insert(majorPointsInSegment, chairAtt) end
		else
			-- ### PHANTOM GRIP LOGIC ###
			local stateId = towerA.Name .. "_" .. towerB.Name
			local state = phantomGripStates[stateId]

			if state then
				local segmentVector = towerB_Pos - towerA_Pos
				if segmentVector.Magnitude > 0 then
					local phantomGripPosition = towerA_Pos + segmentVector.Unit * state.currentDistance
					local phantomGrip = { WorldPosition = phantomGripPosition }
					table.insert(majorPointsInSegment, phantomGrip)
				end
			end
		end

		table.insert(majorPointsInSegment, towerB_Att)

		local subdividedSegmentWorldPositions = {}
		for k = 1, #majorPointsInSegment - 1 do
			local startAtt, endAtt = majorPointsInSegment[k], majorPointsInSegment[k+1]
			if not startAtt or not endAtt then continue end
			local startPos, endPos = startAtt.WorldPosition, endAtt.WorldPosition
			table.insert(subdividedSegmentWorldPositions, startPos)
		end
		if #majorPointsInSegment > 0 and majorPointsInSegment[#majorPointsInSegment] then
			table.insert(subdividedSegmentWorldPositions, majorPointsInSegment[#majorPointsInSegment].WorldPosition)
		end
		currentSegments[segmentId] = subdividedSegmentWorldPositions
	end
	return currentSegments
end


local function updateCablesServer(player)
	if not chairsRoot or not chairsRoot.Parent then allChairGripAttachments = {} return end
	local segmentsToSend, currentProcessedSegments = {}, {}
	local newUphillSegments = buildSegmentsFromTowerList(uphillTowers, "Uphill")
	local newDownhillSegments = buildSegmentsFromTowerList(downhillTowers, "Downhill")
	local tempFullCableData = {}
	for segmentId, points in pairs(newUphillSegments) do tempFullCableData[segmentId] = points end
	for segmentId, points in pairs(newDownhillSegments) do tempFullCableData[segmentId] = points end
	for segmentId, points in pairs(tempFullCableData) do
		currentProcessedSegments[segmentId] = true
		if not previousSegmentData[segmentId] or not areSegmentPointsEqual(previousSegmentData[segmentId], points) then
			segmentsToSend[segmentId] = points
			previousSegmentData[segmentId] = points
		end
	end
	for segmentId, _ in pairs(previousSegmentData) do
		if not currentProcessedSegments[segmentId] then
			segmentsToSend[segmentId] = nil
			previousSegmentData[segmentId] = nil
		end
	end
	if player then
		local fullDataToSend = {}
		for id, points in pairs(previousSegmentData) do fullDataToSend[id] = points end
		RenderCablesEvent:FireClient(player, fullDataToSend)
	elseif next(segmentsToSend) ~= nil then
		RenderCablesEvent:FireAllClients(segmentsToSend)
	end
end

--- INITIALIZATION ---
print("CableServer: Waiting for lift system...")
task.wait(10)
print("CableServer: Initializing...")

setupTowers()
chairsRoot = workspace:WaitForChild("ActiveLiftGrips", 30)
if chairsRoot then setupChairs() debugPrint("DEBUG: Initial chairsRoot setup complete.") end


Players.PlayerAdded:Connect(function(player)
	task.wait(2)
	pcall(updateCablesServer, player)
end)

CarriersRegeneratedSignal.Event:Connect(function(newCarriersFolder)
	if newCarriersFolder and newCarriersFolder:IsA("Folder") and newCarriersFolder.Name == "ActiveLiftGrips" then
		debugPrint("DEBUG: 'CarriersRegeneratedSignal' received. Re-initializing.")
		chairsRoot = newCarriersFolder
		setupTowers()
		setupChairs()
		previousSegmentData = {}
		phantomGripStates = {}
		RenderCablesEvent:FireAllClients({})
		updateCablesServer()
	end
end)

local lastUpdateTime = 0
RunService.Heartbeat:Connect(function(dt)
	pcall(updatePhantomGripStates, dt)

	if os.clock() - lastUpdateTime >= UPDATE_INTERVAL then
		pcall(updateCablesServer)
		lastUpdateTime = os.clock()
	end
end)

print("CableServer: Started. Cable rendering handled by clients.")







