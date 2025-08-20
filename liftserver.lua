-- Roblox Services
local Workspace = game:GetService("Workspace")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

-- ##################################################################
-- #################### CONTROL SYSTEM CONFIG #####################
-- ##################################################################

-- Team and Control Panel Configuration
local CONTROL_PANELS_FOLDER_NAME = "LiftControlPanels"
local ALLOWED_TEAMS = {"Owner", "Lift operator"}

-- Lift States
local liftState = "STOPPED"
local currentSpeedSetting = "fast" -- This is the default/initial speed
local SPEED_PRESETS = { slow = 3, medium = 5, fast = 8 }
local SPEED_CHANGE_RATE = 1.9
local EMERGENCY_STOP_RATE = 0.75
local currentActualSpeed = 0
local currentTargetSpeed = 0

-- #################### NEW STARTUP CONFIG ####################
local STARTUP_DURATION = 7.5
local startupTimer = 0
-- #################### NEW EASING CONTROL ####################
local STARTUP_EASING_POWER = 1 -- Higher numbers = starts slower, speeds up more sharply at the end. 2 is linear acceleration, 3 is cubic, etc.
-- ############################################################

local ROTATION_LERP_SPEED = 2.0

-- #################### DYNAMIC INTENSITY CONFIG ####################
local SPEED_INTENSITY_SCALARS = {
	fast = 1.0,
	medium = 0.6,
	slow = 0.3
}
-- #####################################################################

-- #################### GLOBAL ANIMATION FX CONFIG ####################
-- BFX (Bounce FX) for Speed Changes
local SPEED_CHANGE_BFX_DURATION = 5.5
local SPEED_CHANGE_BFX_MAGNITUDE = 2.4
local SPEED_CHANGE_BFX_FREQUENCY = 1.5

local START_FX_DURATION = 3.5
local START_BOUNCE_MAGNITUDE = 0.8
local START_BOUNCE_FREQUENCY = 3.0
local START_SWING_MAGNITUDE = math.rad(2)
local START_SWING_FREQUENCY = 2.5

local NORMAL_STOP_FX_DURATION = 9.0
local NORMAL_STOP_BOUNCE_MAGNITUDE = 2.2
local NORMAL_STOP_BOUNCE_FREQUENCY = 3.0
local NORMAL_STOP_SWING_MAGNITUDE = math.rad(4)
local NORMAL_STOP_SWING_FREQUENCY = 3.5

local EMERGENCY_FX_DURATION = 15
local EMERGENCY_BOUNCE_MAGNITUDE = 3.6
local EMERGENCY_BOUNCE_FREQUENCY = 2
local EMERGENCY_SWING_MAGNITUDE = math.rad(12)
local EMERGENCY_SWING_FREQUENCY = 2

local fxTimer = 0
local speedChangeFxTimer = 0
-- #################### END GLOBAL FX CONFIG ####################

-- #################### SECONDARY ANIMATION FX CONFIG ####################
local STATION_TURN_FX_DURATION = 4.5
local STATION_TURN_SWING_MAGNITUDE = math.rad(5)
local STATION_TURN_SWING_FREQUENCY = 2.0

local CREST_SWING_FX_DURATION = 8.0
local CREST_SWING_MAGNITUDE = math.rad(6)
local CREST_SWING_FREQUENCY = 2.5

local RANDOM_TOWER_SWING_MAGNITUDE = math.rad(3.7)
local RANDOM_TOWER_SWING_FREQUENCY = 2.0

local TOWER_IMPULSE_SWING_DURATION = 15.0
local TOWER_IMPULSE_SWING_MAGNITUDE = math.rad(7.0)
local TOWER_IMPULSE_SWING_FREQUENCY = 3.0
local TOWER_IMPULSE_SWING_DECAY_RATE = 1.0
-- #################### END NEW FX CONFIG ####################

local lastCalculatedSpeed = -1
local PATH_REBUILD_THRESHOLD = 0.1
local pathTimeAtStop = 0
local speedSettingAtStop = "fast"

local TakeControlEvent = ReplicatedStorage:WaitForChild("TakeControlOfLiftCarrier")
local CFrameUpdateEvent = ReplicatedStorage:WaitForChild("LiftCFrameUpdate")

local CarriersRegeneratedSignal = ReplicatedStorage:FindFirstChild("CarriersRegeneratedSignal") or Instance.new("BindableEvent", ReplicatedStorage)
CarriersRegeneratedSignal.Name = "CarriersRegeneratedSignal"

--- General Lift Configuration
local GTOWERS_FOLDER_NAME = "gtowers"
local CARRIERS_FOLDER_NAME = "CWA-carriers"
local CARRIER_MODEL_NAME = "CWA-cab"
local GRIP_HIERARCHY = {"Grip", "GripPart"}
local CABIN_HIERARCHY = {"Cabin", "PrimaryPart"}
local SEAT_HIERARCHY = {"Grip", "Seat"}
local GIPFEL_SPEED_VALUE_NAME = "GipfelSpeed"
local SAG_AMOUNT_VALUE_NAME = "SagAmount"
local DESIRED_DISTANCE_BETWEEN_CARRIERS = 100
local STATION_SPEED_MULTIPLIER = 1
local MAX_DELTA_TIME = 0.5
local INITIAL_START_DELAY = 10
local SAG_NORMALIZATION_LENGTH = 100

local ACTIVE_GRIPS_PARENT_NAME = "ActiveLiftGrips"
local activeGripsParent = Workspace:FindFirstChild(ACTIVE_GRIPS_PARENT_NAME) or Instance.new("Folder", Workspace)
activeGripsParent.Name = ACTIVE_GRIPS_PARENT_NAME

local gtowersFolder = Workspace:WaitForChild(GTOWERS_FOLDER_NAME)
local cwaCarriersFolder = Workspace:WaitForChild(CARRIERS_FOLDER_NAME)
local carrierTemplateModel = cwaCarriersFolder:WaitForChild(CARRIER_MODEL_NAME)
local gipfelSpeedValue = Workspace:FindFirstChild(GIPFEL_SPEED_VALUE_NAME) or Instance.new("NumberValue", Workspace)
gipfelSpeedValue.Name = GIPFEL_SPEED_VALUE_NAME
local sagAmountValue = Workspace:FindFirstChild(SAG_AMOUNT_VALUE_NAME)
local sagAmount = 2
if sagAmountValue and sagAmountValue:IsA("NumberValue") then sagAmount = sagAmountValue.Value end

local TOP_STATION_PLATFORM_PART_NAMES = {"TopStation_Entry", "TopStation_Mid", "TopStation_Exit"}
local BOTTOM_STATION_PLATFORM_PART_NAMES = {"BottomStation_Entry", "BottomStation_Mid", "BottomStation_Mid2","BottomStation_Mid3", "BottomStation_Exit"}

local pathDefinition = {}
local totalPathTime = 0
local activeGrips = {}
local pathNodes = {}

--- Helper Functions
local function getPartFromHierarchy(carrierModelInstance, hierarchy)
	local currentInstance = carrierModelInstance
	for _, childName in ipairs(hierarchy) do
		currentInstance = currentInstance:FindFirstChild(childName)
		if not currentInstance then return nil end
	end
	return currentInstance
end

local function getTargetCFrameAtTime(time, usePathTime)
	if #pathDefinition == 0 then return CFrame.new() end

	local pathTime = usePathTime or totalPathTime
	if not pathTime or pathTime <= 0 then
		return pathDefinition[1] and pathDefinition[1].startCFrame or CFrame.new()
	end
	local adjustedTime = time % pathTime

	local segment
	for i = 1, #pathDefinition do
		local seg = pathDefinition[i]
		if adjustedTime >= seg.startTime and adjustedTime < seg.endTime then
			segment = seg
			break
		end
	end
	if not segment then segment = pathDefinition[#pathDefinition] end

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

local function getSegmentAtTime(time)
	if #pathDefinition == 0 then return nil end
	for i = 1, #pathDefinition do
		local segment = pathDefinition[i]
		if time >= segment.startTime and time < segment.endTime then
			return segment, i
		end
	end
	return pathDefinition[#pathDefinition], #pathDefinition
end


local function updatePathTiming()
	if #pathNodes < 2 then return end; local currentTime = 0; local mainSpeed = currentActualSpeed; local stationSpeed = mainSpeed * STATION_SPEED_MULTIPLIER
	if mainSpeed < 0.1 then totalPathTime = 0; return; end
	for i = 1, #pathDefinition do
		local segment = pathDefinition[i]; local n1 = pathNodes[i]; local n2 = pathNodes[i+1] or pathNodes[1]; local segmentLength = (n2.part.Position - n1.part.Position).Magnitude; local startSpeed, endSpeed
		if segment.type == "accel" then startSpeed = stationSpeed; endSpeed = mainSpeed elseif segment.type == "decel" then startSpeed = mainSpeed; endSpeed = stationSpeed elseif segment.type == "station" then startSpeed = stationSpeed; endSpeed = stationSpeed else startSpeed = mainSpeed; endSpeed = mainSpeed; end; local duration
		if startSpeed == endSpeed then duration = startSpeed > 0 and segmentLength / startSpeed or math.huge else local avgSpeed = (startSpeed + endSpeed) / 2; duration = avgSpeed > 0 and segmentLength / avgSpeed or math.huge; end
		segment.startTime = currentTime; segment.duration = duration; segment.endTime = currentTime + duration; currentTime += duration
	end
	totalPathTime = currentTime; lastCalculatedSpeed = currentActualSpeed; local pathInfoValue = ReplicatedStorage:FindFirstChild("LiftPathInfo")
	if pathInfoValue then local pathTimeValue = pathInfoValue:FindFirstChild("TotalPathTime") if pathTimeValue then pathTimeValue.Value = totalPathTime end end
end

local function setupAndSpawnInitialCarriers()
	if not gtowersFolder then warn("LIFT FATAL ERROR: 'gtowers' folder could not be found, even after waiting.") return end
	if not cwaCarriersFolder then warn("LIFT FATAL ERROR: 'CWA-carriers' folder could not be found, even after waiting.") return end

	local function getSortedParts(nameFilter, names)
		local parts = {}
		if names then
			for _, name in ipairs(names) do
				local p = gtowersFolder:FindFirstChild(name)
				if p and p:IsA("BasePart") then
					table.insert(parts, p)
				end
			end
		else
			local temp = {}
			for _, obj in ipairs(gtowersFolder:GetChildren()) do
				if obj:IsA("BasePart") and obj.Name:lower():find(nameFilter) then
					table.insert(temp, obj)
				end
			end
			table.sort(temp, function(a, b)
				local numA = tonumber(a.Name:match("%d+")) or 0
				local numB = tonumber(b.Name:match("%d+")) or 0
				if numA ~= numB then
					return numA < numB
				else
					return a.Name < b.Name
				end
			end)
			parts = temp
		end
		return parts
	end

	local nodeOrder = {{parts = getSortedParts(nil, BOTTOM_STATION_PLATFORM_PART_NAMES), type = "station"},{parts = getSortedParts("uphill"), type = "uphill"},{parts = getSortedParts(nil, TOP_STATION_PLATFORM_PART_NAMES), type = "station"},{parts = getSortedParts("downhill"), type = "downhill"},}; for _, entry in ipairs(nodeOrder) do for _, part in ipairs(entry.parts) do table.insert(pathNodes, {part = part, type = entry.type}) end end
	if #pathNodes < 2 then warn("Lift System Warning: Not enough path nodes found.") return end

	pathDefinition = {}
	for i = 1, #pathNodes do
		local n1 = pathNodes[i]; local n2 = pathNodes[i+1] or pathNodes[1]
		local p1, p2 = n1.part.Position, n2.part.Position
		local segmentVector = p2 - p1
		local isN1Station = n1.type:find("station"); local isN2Station = n2.type:find("station"); local segmentType
		local tempSpeed = SPEED_PRESETS[currentSpeedSetting]
		if math.abs((tempSpeed * STATION_SPEED_MULTIPLIER) - tempSpeed) < 0.1 then segmentType = n1.type
		else
			if isN1Station and not isN2Station then segmentType = "accel" elseif not isN1Station and isN2Station then segmentType = "decel"
			elseif isN1Station and isN2Station then segmentType = "station" else segmentType = n1.type; end
		end
		local r1 = CFrame.lookAt(p1, p1 + segmentVector); local r2 = CFrame.lookAt(p2, p2 + segmentVector)
		if segmentType == "uphill" or segmentType == "downhill" or segmentType == "accel" or segmentType == "decel" then
			local dir, right, up = segmentVector.Unit, segmentVector.Unit:Cross(Vector3.yAxis).Unit, segmentVector.Unit:Cross(Vector3.yAxis).Unit:Cross(segmentVector.Unit).Unit
			r1, r2 = CFrame.fromMatrix(p1, right, up), CFrame.fromMatrix(p2, right, up)
		end

		local applySag = false
		local segmentLength = segmentVector.Magnitude
		local segmentSagAmount = 0
		if segmentType == "uphill" or segmentType == "downhill" then
			if not isN1Station and not isN2Station then
				local num1 = tonumber(n1.part.Name:match("%d+"))
				local num2 = tonumber(n2.part.Name:match("%d+"))
				if not (num1 and num2 and num1 == num2) then
					applySag = true
				end
			end
		end
		if applySag and (n1.part.Name:upper():find("NS") or n2.part.Name:upper():find("NS")) then
			applySag = false
		end
		if applySag then
			segmentSagAmount = sagAmount * (segmentLength / SAG_NORMALIZATION_LENGTH)
		end

		table.insert(pathDefinition, {
			type = segmentType,
			startCFrame = r1,
			endCFrame = r2,
			startNodeType = n1.type,
			endNodeType = n2.type,
			applySag = applySag,
			segmentSag = segmentSagAmount
		})
	end

	local actualInitialSpeed = currentActualSpeed
	currentActualSpeed = SPEED_PRESETS[currentSpeedSetting]
	updatePathTiming()

	local pathInfoValue = ReplicatedStorage:FindFirstChild("LiftPathInfo") or Instance.new("Folder", ReplicatedStorage); pathInfoValue.Name = "LiftPathInfo"
	local pathDefValue = pathInfoValue:FindFirstChild("PathDefinition") or Instance.new("StringValue", pathInfoValue); pathDefValue.Name = "PathDefinition"; pathDefValue.Value = HttpService:JSONEncode(pathDefinition)
	local sagValue = pathInfoValue:FindFirstChild("SagAmount") or Instance.new("NumberValue", pathInfoValue); sagValue.Name = "SagAmount"; sagValue.Value = sagAmount
	for _, grip in ipairs(activeGrips) do grip.model:Destroy() end; activeGrips = {}

	local mainLineSpeed = SPEED_PRESETS[currentSpeedSetting];
	if mainLineSpeed <= 0 or totalPathTime <= 0 then warn("Could not calculate number of grips. Check path and speed."); return end
	local timeInterval = DESIRED_DISTANCE_BETWEEN_CARRIERS / mainLineSpeed; local numGrips = math.floor(totalPathTime / timeInterval)
	if numGrips <= 0 then warn("Could not calculate number of grips. Path or speed resulted in zero grips."); return end
	local actualTimeSpacing = totalPathTime / numGrips

	local templateGripPart = getPartFromHierarchy(carrierTemplateModel, GRIP_HIERARCHY)
	local templateCabinPart = getPartFromHierarchy(carrierTemplateModel, CABIN_HIERARCHY)
	local modelCabinOffset = Vector3.new()
	if templateGripPart and templateCabinPart then
		modelCabinOffset = templateGripPart.CFrame:PointToObjectSpace(templateCabinPart.CFrame.Position)
	else
		warn("Could not find template GripPart or Cabin PrimaryPart to calculate the model offset!")
	end

	for i = 1, numGrips do
		local newCarrierModel = carrierTemplateModel:Clone(); local gripId = "Grip_" .. i
		newCarrierModel:SetAttribute("LiftGripID", gripId); newCarrierModel.PrimaryPart = getPartFromHierarchy(newCarrierModel, GRIP_HIERARCHY)
		local initialTime = (i - 1) * actualTimeSpacing;
		local pathPercent = initialTime / totalPathTime
		local initialGripCFrame = getTargetCFrameAtTime(initialTime, totalPathTime);
		newCarrierModel:SetPrimaryPartCFrame(initialGripCFrame); newCarrierModel.Parent = activeGripsParent
		local gripPartInstance = newCarrierModel.PrimaryPart; local cabinPartInstance = getPartFromHierarchy(newCarrierModel, CABIN_HIERARCHY); local seatInstance = getPartFromHierarchy(newCarrierModel, SEAT_HIERARCHY)
		if gripPartInstance then
			gripPartInstance.Anchored = true; gripPartInstance.CanCollide = false; if cabinPartInstance then cabinPartInstance.Anchored = true; cabinPartInstance.CanCollide = false end
			local gripData = {
				model = newCarrierModel, part = gripPartInstance, cabin = cabinPartInstance, id = gripId,
				pathPercent = pathPercent,
				currentVisualCFrame = initialGripCFrame,
				cabinPositionalOffset = modelCabinOffset,
				lastYaw = math.atan2(initialGripCFrame.LookVector.X, initialGripCFrame.LookVector.Z),
				lastSegmentType = "station",
				stationTurnTimer = 0,
				crestSwingTimer = 0,
				towerImpulseSwingTimer = 0,
				randomSwingOffset = math.random() * 2 * math.pi,
				randomSwingSpeedMultiplier = 1.0 + (math.random() - 0.5) * 0.4
			}
			table.insert(activeGrips, gripData)
			if seatInstance and seatInstance:IsA("Seat") then
				seatInstance:GetPropertyChangedSignal("Occupant"):Connect(function()
					local humanoid = seatInstance.Occupant; local player = humanoid and game.Players:GetPlayerFromCharacter(humanoid.Parent)
					if player then gripData.occupant = player; TakeControlEvent:FireClient(player, newCarrierModel, gripData.pathPercent)
					else if gripData.occupant then TakeControlEvent:FireClient(gripData.occupant, newCarrierModel, nil); gripData.occupant = nil; gripPartInstance.Anchored = true end end
				end)
			end
		else warn("Could not find GripPart for carrier " .. gripId .. ". Not spawned."); newCarrierModel:Destroy() end
	end

	currentActualSpeed = actualInitialSpeed
	lastCalculatedSpeed = -1

	print("Lift layout defined and", #activeGrips, "carriers spawned."); CarriersRegeneratedSignal:Fire(activeGripsParent)
end


local function playStartupSoundAndWait()
	local witoringFolder = Workspace:FindFirstChild("witoring")
	if not witoringFolder then
		warn("Sound folder 'witoring' not found in Workspace. Skipping startup sound.")
		return
	end

	local soundsToPlay = {}
	local longestDuration = 0

	for _, part in ipairs(witoringFolder:GetChildren()) do
		if part.Name:lower() == "ring" and part:IsA("BasePart") then
			local sound = part:FindFirstChild("startup")

			if sound and sound:IsA("Sound") then
				table.insert(soundsToPlay, sound)
				if sound.TimeLength > longestDuration then
					longestDuration = sound.TimeLength
				end
			else
				warn("'ring' part found, but it does not contain a Sound object named 'startup'.")
			end
		end
	end

	if #soundsToPlay > 0 then
		print("Playing 'startup' sounds...")
		for _, sound in ipairs(soundsToPlay) do
			sound:Play()
		end
		task.wait(longestDuration)
		print("Startup sounds finished.")
	else
		warn("No sounds named 'startup' found in any 'ring' parts inside the 'witoring' folder.")
	end
end


local function handleCommand(command, value)
	if (liftState == "EMERGENCY_STOPPING" or liftState == "STOPPING" or liftState == "AWAITING_RESET" or liftState == "STARTING") and command ~= "RESET" then
		return
	end

	if command == "START" and liftState == "STOPPED" then
		print("Lift command: START received. Initiating startup sequence...")
		task.spawn(function()
			playStartupSoundAndWait()
			liftState = "STARTING"
			startupTimer = 0
			currentTargetSpeed = SPEED_PRESETS[currentSpeedSetting]
			fxTimer = 0
			pathTimeAtStop = totalPathTime
		end)

	elseif command == "STOP" and (liftState == "RUNNING" or liftState == "STARTING") then
		liftState = "STOPPING"; currentTargetSpeed = 0; fxTimer = 0; pathTimeAtStop = totalPathTime
		speedSettingAtStop = currentSpeedSetting
		print("Lift command: STOP")
	elseif command == "EMERGENCY_STOP" and (liftState == "RUNNING" or liftState == "STARTING") then
		liftState = "EMERGENCY_STOPPING"; currentTargetSpeed = 0; fxTimer = 0; pathTimeAtStop = totalPathTime
		speedSettingAtStop = currentSpeedSetting
		print("Lift command: EMERGENCY_STOP")
	elseif command == "SET_SPEED" and SPEED_PRESETS[value] then
		local oldSpeed = SPEED_PRESETS[currentSpeedSetting]
		local newSpeed = SPEED_PRESETS[value]

		if newSpeed < oldSpeed and (liftState == "RUNNING" or liftState == "STARTING") then
			speedChangeFxTimer = SPEED_CHANGE_BFX_DURATION
		end

		currentSpeedSetting = value
		if (liftState == "RUNNING" or liftState == "STARTING") then
			currentTargetSpeed = newSpeed
		end
		print("Lift command: SET_SPEED to " .. value)
	elseif command == "RESET" and liftState == "AWAITING_RESET" then
		liftState = "STOPPED"
		print("Lift has been reset and is now in STOPPED state. Ready to start.")
	end
end

-- ##################################################################
-- ############## MODIFIED CONTROL PANEL SETUP ####################
-- ##################################################################
local function setupControlPanel(panelModel)
	if not panelModel:IsA("Model") then return end
	print("Setting up control panel: " .. panelModel.Name)

	-- Setup for standard buttons
	local startButton = panelModel:FindFirstChild("StartButton", true)
	local stopButton = panelModel:FindFirstChild("StopButton", true)
	local emergencyStopButton = panelModel:FindFirstChild("EmergencyStopButton", true)
	local resetButton = panelModel:FindFirstChild("ResetButton", true)

	-- Generic function to connect a click detector to a command
	local function connectClick(buttonPart, command, value)
		if not buttonPart or not buttonPart:FindFirstChildOfClass("ClickDetector") then
			warn("Control panel '" .. panelModel.Name .. "' is missing button or ClickDetector for command: " .. (command or "N/A"))
			return
		end

		buttonPart.ClickDetector.MouseClick:Connect(function(player)
			if not player or not player:IsA("Player") or not table.find(ALLOWED_TEAMS, player.Team.Name) then
				local playerName = player and player.Name or "Unknown"
				print(playerName .. " is not authorized to use the lift controls.")
				return
			end

			local commandText = tostring(command or "NIL_COMMAND")
			local valueText = value and (" with value " .. tostring(value)) or ""
			print(player.Name .. " activated command: " .. commandText .. valueText)

			handleCommand(command, value)
		end)
	end

	-- Connect the standard buttons
	connectClick(startButton, "START")
	connectClick(stopButton, "STOP")
	connectClick(emergencyStopButton, "EMERGENCY_STOP")
	connectClick(resetButton, "RESET")

	-- ## NEW ROTATOR SWITCH LOGIC ##
	-- Find the rotator part within the panel model
	local speedRotator = panelModel:FindFirstChild("SpeedRotator", true)
	if speedRotator and speedRotator:FindFirstChildOfClass("ClickDetector") then
		print("Setting up SpeedRotator for panel: " .. panelModel.Name)

		local clickDetector = speedRotator.ClickDetector
		-- The model to rotate is the direct parent of the rotator part
		local knobModel = speedRotator.Parent

		-- Validate that the parent is a model and the rotator part is its PrimaryPart
		if not knobModel or not knobModel:IsA("Model") or knobModel.PrimaryPart ~= speedRotator then
			warn("The 'SpeedRotator' part must be the PrimaryPart of its own Model (e.g., 'RotatorKnobModel'). Please check the hierarchy.")
			return
		end

		-- Store state on the model itself to support multiple independent panels
		knobModel:SetAttribute("OriginalPivot", knobModel:GetPivot())

		-- Define states and corresponding visual rotation angles
		local speedStates = {"fast", "medium", "slow"}
		local angleDegrees = {fast = 0, medium = 90, slow = 180}

		-- Function to physically rotate the knob model
		local function setRotation(state)
			local rotationAngle = angleDegrees[state] or 0
			local pivot = knobModel:GetAttribute("OriginalPivot")
			if pivot then
				-- Rotates around the X-axis (Pitch)
				knobModel:PivotTo(pivot * CFrame.Angles(math.rad(rotationAngle), 0, 0))
			end
		end

		-- Set initial state and rotation based on the script's default speed
		local initialIndex = table.find(speedStates, currentSpeedSetting) or 1
		knobModel:SetAttribute("CurrentSpeedIndex", initialIndex)
		setRotation(speedStates[initialIndex])

		-- Click handler for changing speed
		local function onRotate(player, isIncrement)
			if not player or not player:IsA("Player") or not table.find(ALLOWED_TEAMS, player.Team.Name) then
				print((player and player.Name or "Unknown") .. " is not authorized to use the lift controls.")
				return
			end

			local currentIndex = knobModel:GetAttribute("CurrentSpeedIndex")

			if isIncrement then -- Right-click: fast -> medium -> slow
				currentIndex = math.min(#speedStates, currentIndex + 1)
			else -- Left-click: slow -> medium -> fast
				currentIndex = math.max(1, currentIndex - 1)
			end

			knobModel:SetAttribute("CurrentSpeedIndex", currentIndex)
			local newState = speedStates[currentIndex]

			-- Visually rotate the knob
			setRotation(newState)

			-- Send the command to the main lift controller
			handleCommand("SET_SPEED", newState)
		end

		clickDetector.MouseClick:Connect(function(player) onRotate(player, false) end)
		clickDetector.RightMouseClick:Connect(function(player) onRotate(player, true) end)

	else
		warn("Control panel '" .. panelModel.Name .. "' is missing a part named 'SpeedRotator' with a ClickDetector. Speed controls on this panel will be disabled.")
	end
end
-- ##################################################################
-- ################# END MODIFIED FUNCTION ######################
-- ##################################################################

local updateAccumulator = 0
local UPDATE_INTERVAL = 1/60

local function onHeartbeat(deltaTime)
	if (liftState == "STOPPED" or liftState == "AWAITING_RESET") and currentActualSpeed < 0.01 then return end
	local clampedDeltaTime = math.min(deltaTime, MAX_DELTA_TIME)

	if liftState == "STARTING" then
		startupTimer = math.min(STARTUP_DURATION, startupTimer + clampedDeltaTime)
		local alpha = startupTimer / STARTUP_DURATION
		-- #################### MODIFIED: Use easing power for tunable acceleration ####################
		local easedAlpha = alpha ^ STARTUP_EASING_POWER
		currentActualSpeed = easedAlpha * currentTargetSpeed

		if startupTimer >= STARTUP_DURATION then
			liftState = "RUNNING"
			currentActualSpeed = currentTargetSpeed
			print("Lift has reached target speed. State is now RUNNING.")
		end

	elseif liftState == "RUNNING" then
		if math.abs(currentActualSpeed - currentTargetSpeed) > 0.01 then
			local lerpRate = SPEED_CHANGE_RATE
			currentActualSpeed += (currentTargetSpeed - currentActualSpeed) * (clampedDeltaTime / lerpRate)
		else
			currentActualSpeed = currentTargetSpeed
		end

	elseif liftState == "STOPPING" or liftState == "EMERGENCY_STOPPING" then
		local lerpRate = (liftState == "EMERGENCY_STOPPING") and EMERGENCY_STOP_RATE or SPEED_CHANGE_RATE
		currentActualSpeed += (currentTargetSpeed - currentActualSpeed) * (clampedDeltaTime / lerpRate)
	end

	gipfelSpeedValue.Value = currentActualSpeed

	local globalVerticalBounce, globalSwingAngle = 0, 0
	local currentFxDuration = 0

	if liftState == "EMERGENCY_STOPPING" or liftState == "STOPPING" then
		local bounceMag, bounceFreq, swingMag, swingFreq
		local intensityScalar = SPEED_INTENSITY_SCALARS[speedSettingAtStop] or 1.0

		if liftState == "EMERGENCY_STOPPING" then
			currentFxDuration = EMERGENCY_FX_DURATION
			bounceMag = EMERGENCY_BOUNCE_MAGNITUDE * intensityScalar
			swingMag = EMERGENCY_SWING_MAGNITUDE * intensityScalar
			bounceFreq = EMERGENCY_BOUNCE_FREQUENCY
			swingFreq = EMERGENCY_SWING_FREQUENCY
		else
			currentFxDuration = NORMAL_STOP_FX_DURATION
			bounceMag = NORMAL_STOP_BOUNCE_MAGNITUDE * intensityScalar
			swingMag = NORMAL_STOP_SWING_MAGNITUDE * intensityScalar
			bounceFreq = NORMAL_STOP_BOUNCE_FREQUENCY
			swingFreq = NORMAL_STOP_SWING_FREQUENCY
		end

		fxTimer += clampedDeltaTime
		if fxTimer < currentFxDuration then
			local decay = (1 - (fxTimer / currentFxDuration))^2
			globalVerticalBounce = math.sin(fxTimer * bounceFreq) * bounceMag * decay
			globalSwingAngle = math.sin(fxTimer * swingFreq) * swingMag * decay
		end
	elseif (liftState == "RUNNING" or liftState == "STARTING") and fxTimer < START_FX_DURATION then
		currentFxDuration = START_FX_DURATION
		fxTimer += clampedDeltaTime
		local decay = (1 - (fxTimer / currentFxDuration))^2
		globalVerticalBounce = math.sin(fxTimer * START_BOUNCE_FREQUENCY) * START_BOUNCE_MAGNITUDE * decay
		globalSwingAngle = math.sin(fxTimer * START_SWING_FREQUENCY) * START_SWING_MAGNITUDE * decay
	end

	if speedChangeFxTimer > 0 then
		speedChangeFxTimer = math.max(0, speedChangeFxTimer - clampedDeltaTime)
		local decay = (speedChangeFxTimer / SPEED_CHANGE_BFX_DURATION)^2
		local speedBounce = math.sin((SPEED_CHANGE_BFX_DURATION - speedChangeFxTimer) * SPEED_CHANGE_BFX_FREQUENCY) * SPEED_CHANGE_BFX_MAGNITUDE * decay
		globalVerticalBounce += speedBounce
	end

	if (liftState == "STOPPING" or liftState == "EMERGENCY_STOPPING") and currentActualSpeed < 0.01 then
		if fxTimer >= currentFxDuration then
			currentActualSpeed = 0
			currentTargetSpeed = 0
			liftState = "AWAITING_RESET"
			print("Lift has come to a stop. State is now AWAITING_RESET.")
		end
	end

	if (liftState == "RUNNING" or liftState == "STARTING") and math.abs(currentActualSpeed - lastCalculatedSpeed) > PATH_REBUILD_THRESHOLD then
		updatePathTiming()
	end

	if #activeGrips == 0 then return end
	updateAccumulator += clampedDeltaTime
	local cframeUpdates = {}

	local percentToAdvance = 0
	if liftState == "RUNNING" or liftState == "STARTING" then
		if totalPathTime > 0 then
			percentToAdvance = clampedDeltaTime / totalPathTime
		end
	elseif liftState == "STOPPING" or liftState == "EMERGENCY_STOPPING" then
		if pathTimeAtStop > 0 and lastCalculatedSpeed > 0.1 then
			local baseAdvance = clampedDeltaTime / pathTimeAtStop
			percentToAdvance = baseAdvance * (currentActualSpeed / lastCalculatedSpeed)
		end
	end

	local timeSource = totalPathTime
	if timeSource <= 0 then return end

	local runTime = os.clock()

	for _, gripData in ipairs(activeGrips) do
		gripData.pathPercent = (gripData.pathPercent + percentToAdvance) % 1.0
		local timeForLookup = gripData.pathPercent * timeSource

		if gripData.occupant then TakeControlEvent:FireClient(gripData.occupant, gripData.model, gripData.pathPercent); continue end

		local authoritativeTargetCFrame = getTargetCFrameAtTime(timeForLookup, timeSource)

		local crestSwingAngle, stationTurnSwingAngle = 0, 0
		local randomTowerSwingAngle, towerImpulseSwingAngle = 0, 0
		local carrierBounce = globalVerticalBounce
		local carrierGlobalSwing = globalSwingAngle

		local currentSegment = getSegmentAtTime(timeForLookup)

		if currentSegment then
			if currentSegment.type == "station" then
				carrierBounce = 0
				carrierGlobalSwing = 0
			elseif not currentSegment.applySag then
				carrierBounce = 0
			elseif currentSegment.type == "downhill" then
				carrierBounce = globalVerticalBounce * -1
			end

			if (liftState == "RUNNING" or liftState == "STARTING") and (currentSegment.type == "uphill" or currentSegment.type == "downhill") then
				randomTowerSwingAngle = math.sin(runTime * RANDOM_TOWER_SWING_FREQUENCY * gripData.randomSwingSpeedMultiplier + gripData.randomSwingOffset) * RANDOM_TOWER_SWING_MAGNITUDE
			end

			local lastType = gripData.lastSegmentType
			local currentType = currentSegment.type

			if currentType ~= lastType and (lastType:match("hill") or currentType:match("hill") or (lastType == "station" and currentType:match("hill"))) then
				gripData.crestSwingTimer = CREST_SWING_FX_DURATION
			end

			if currentType ~= lastType and lastType == "station" and (currentType == "uphill" or currentType == "downhill") then
				gripData.towerImpulseSwingTimer = TOWER_IMPULSE_SWING_DURATION
			end

			gripData.lastSegmentType = currentType

			local currentYaw = math.atan2(gripData.currentVisualCFrame.LookVector.X, gripData.currentVisualCFrame.LookVector.Z)
			local deltaYaw = math.abs(currentYaw - gripData.lastYaw)
			if deltaYaw > math.pi then deltaYaw = 2 * math.pi - deltaYaw end

			if deltaYaw > 0.05 and currentType == "station" then
				gripData.stationTurnTimer = STATION_TURN_FX_DURATION
			end
			gripData.lastYaw = currentYaw

			if gripData.crestSwingTimer > 0 then
				gripData.crestSwingTimer -= clampedDeltaTime
				if gripData.crestSwingTimer > 0 then
					local decay = (gripData.crestSwingTimer / CREST_SWING_FX_DURATION)^2
					crestSwingAngle = math.sin((CREST_SWING_FX_DURATION - gripData.crestSwingTimer) * CREST_SWING_FREQUENCY) * CREST_SWING_MAGNITUDE * decay
				end
			end

			if gripData.towerImpulseSwingTimer > 0 then
				gripData.towerImpulseSwingTimer -= clampedDeltaTime
				if gripData.towerImpulseSwingTimer > 0 then
					local decay = (gripData.towerImpulseSwingTimer / TOWER_IMPULSE_SWING_DURATION) ^ TOWER_IMPULSE_SWING_DECAY_RATE
					local timeSinceStart = TOWER_IMPULSE_SWING_DURATION - gripData.towerImpulseSwingTimer
					towerImpulseSwingAngle = math.sin(timeSinceStart * TOWER_IMPULSE_SWING_FREQUENCY) * TOWER_IMPULSE_SWING_MAGNITUDE * decay
				end
			end

			if gripData.stationTurnTimer > 0 then
				gripData.stationTurnTimer -= clampedDeltaTime
				if gripData.stationTurnTimer > 0 then
					local decay = (gripData.stationTurnTimer / STATION_TURN_FX_DURATION)^2
					stationTurnSwingAngle = math.sin((STATION_TURN_FX_DURATION - gripData.stationTurnTimer) * STATION_TURN_SWING_FREQUENCY) * STATION_TURN_SWING_MAGNITUDE * decay
				end
			end
		end

		local finalTargetCFrame = authoritativeTargetCFrame * CFrame.new(0, carrierBounce, 0)

		local lerpAlpha = math.clamp(ROTATION_LERP_SPEED * clampedDeltaTime, 0, 1)
		gripData.currentVisualCFrame = gripData.currentVisualCFrame:Lerp(finalTargetCFrame, lerpAlpha)

		local finalCabinCFrame
		if gripData.cabin then
			local visualLookVector = gripData.currentVisualCFrame.LookVector
			local horizontalLookVector = Vector3.new(visualLookVector.X, 0, visualLookVector.Z).Unit
			local pivotFrame = CFrame.lookAt(gripData.currentVisualCFrame.Position, gripData.currentVisualCFrame.Position + horizontalLookVector)

			local pitchAngle = carrierGlobalSwing + crestSwingAngle + towerImpulseSwingAngle
			local rollAngle = stationTurnSwingAngle + randomTowerSwingAngle

			local swingRotation = CFrame.Angles(pitchAngle, 0, rollAngle)

			finalCabinCFrame = pivotFrame * swingRotation * CFrame.new(gripData.cabinPositionalOffset)
		end

		gripData.part.CFrame = gripData.currentVisualCFrame
		if gripData.cabin and finalCabinCFrame then
			gripData.cabin.CFrame = finalCabinCFrame
		end

		if updateAccumulator >= UPDATE_INTERVAL then
			table.insert(cframeUpdates, {id = gripData.id, gripCFrame = gripData.currentVisualCFrame, cabinCFrame = finalCabinCFrame})
		end
	end

	if updateAccumulator >= UPDATE_INTERVAL and #cframeUpdates > 0 then
		CFrameUpdateEvent:FireAllClients(cframeUpdates)
		updateAccumulator = 0
	end
end

-- Main Initialization
task.spawn(function()
	print("Lift system: Waiting for "..INITIAL_START_DELAY.." seconds before initialization...")
	task.wait(INITIAL_START_DELAY)

	local controlPanelsFolder = Workspace:WaitForChild(CONTROL_PANELS_FOLDER_NAME)
	if controlPanelsFolder then
		for _, panel in ipairs(controlPanelsFolder:GetChildren()) do
			setupControlPanel(panel)
		end
		controlPanelsFolder.ChildAdded:Connect(setupControlPanel)
	else
		warn("Could not find folder for control panels: " .. CONTROL_PANELS_FOLDER_NAME)
	end

	setupAndSpawnInitialCarriers()

	print("Lift system controller is active. Initial state: "..liftState)
	RunService.Heartbeat:Connect(onHeartbeat)
	print("Lift system main loop started.")

	print("Beginning automatic startup sequence...")
	playStartupSoundAndWait()

	liftState = "STARTING"
	startupTimer = 0
	currentTargetSpeed = SPEED_PRESETS[currentSpeedSetting]
	fxTimer = 0
	pathTimeAtStop = totalPathTime

	print("Lift startup initiated. Easing to target speed.")
end)
