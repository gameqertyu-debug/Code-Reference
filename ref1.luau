--[[ SERVICES ]]--

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")

--[[ MODULES ]]--

local AssetLoader = require(ReplicatedStorage.Modules.Shared.AssetLoader)

--[[ VARIABLES ]]--

local AssetsFolder = ReplicatedStorage.Assets
local AnimationsFolder = AssetsFolder.Animations
local SoundsFolder = AssetsFolder.SFX

local Camera = workspace.CurrentCamera

local MovementStates = {
	IsRunning = false,
	IsCrouching = false,
}

local Player

local RequiredAnimations = {
	AnimationsFolder["Run"],
	AnimationsFolder["CrouchIdle"],
	AnimationsFolder["CrouchWalk"],
}

local LoadedAnimations = {}


local RunConfig = {
	RampTime = 0.6,
	SpeedRange = NumberRange.new(16, 30),
	FOVRange = NumberRange.new(70, 135),
	RunState = 0, -- 0 = not running, 1 = ramping up, 2 = running
	RunKeybind = Enum.KeyCode.LeftShift,
}

local CrouchConfig = {
	RampTime = 0.6,
	CrouchSpeed = 7,
	FOVRange = NumberRange.new(35, 70),
	CrouchState = 0, -- 0 = not crouching, 1 = crouching
	CrouchKeybind = Enum.KeyCode.C,
	CurrentAnimation = LoadedAnimations["CrouchIdle"],
}

local Actions = {
	["Run"] = function(Humanoid: Humanoid)
		if MovementStates.IsCrouching then return end
		local runAnimation = LoadedAnimations["Run"]
		runAnimation:Play()
		
		--[[ Tweens ]]--
		local fovTweenInfo = TweenInfo.new(RunConfig.RampTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local FOVTween = TweenService:Create(Camera, fovTweenInfo, {FieldOfView = RunConfig.FOVRange.Max})
		local fovTweenInfo2 = TweenInfo.new(RunConfig.RampTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local FOVTween2 = TweenService:Create(Camera, fovTweenInfo, {FieldOfView = RunConfig.FOVRange.Min})
		
		--[[ Tasks ]]--
		local rampSpeedTask = task.spawn(function()
			RunConfig.RunState = 1
			FOVTween:Play()
			local start = tick()
			while MovementStates.IsRunning do
				local elapsed = tick() - start
				local alpha = math.clamp(elapsed / RunConfig.RampTime, 0, 1)
				local speed = RunConfig.SpeedRange.Min + (RunConfig.SpeedRange.Max - RunConfig.SpeedRange.Min) * alpha
				Humanoid.WalkSpeed = speed
				if alpha >= 1 then break end
				RunService.Heartbeat:Wait()
			end
		end)
		
		local stopRunDuringRampCheck = task.spawn(function()
			if RunConfig.RunState == 1 and not MovementStates.IsRunning then
				RunConfig.RunState = 0
				Humanoid.WalkSpeed = 16
				FOVTween:Cancel()
				FOVTween2:Play()
				MovementStates.IsRunning = false
				task.cancel(rampSpeedTask)
			end
		end)
		
		--[[ Connections ]]--
		
		UserInputService.InputEnded:Connect(function(input, gpe)
			if gpe then return end
			if input.KeyCode == RunConfig.RunKeybind then
				RunConfig.RunState = 0
				Humanoid.WalkSpeed = 16
				FOVTween2:Play()
				LoadedAnimations["Run"]:Stop()
				MovementStates.IsRunning = false
				task.cancel(rampSpeedTask)
				task.cancel(stopRunDuringRampCheck)
			end
		end)
	end,
	["Crouch"] = function(Humanoid: Humanoid)
		if MovementStates.IsRunning then return end
		
		--[[ Tweens ]]--
		local FOVTweenInfo = TweenInfo.new(CrouchConfig.RampTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local FOVTween = TweenService:Create(Camera, FOVTweenInfo, {FieldOfView = CrouchConfig.FOVRange.Min})
		local FOVTweenInfo2 = TweenInfo.new(CrouchConfig.RampTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local FOVTween2 = TweenService:Create(Camera, FOVTweenInfo2, {FieldOfView = CrouchConfig.FOVRange.Max})
		
		--[[ Crouch Animations ]]--
		
		local crouchIdle = LoadedAnimations["CrouchIdle"]
		local crouchWalk = LoadedAnimations["CrouchWalk"]
		
		
		--[[ Setup Speed ]]--
		FOVTween:Play()
		Humanoid.WalkSpeed = CrouchConfig.CrouchSpeed
		
		--[[ Tasks ]]--
		local animationHandler = task.spawn(function()
			local HumanoidRootPart: Part = Humanoid.Parent:WaitForChild("HumanoidRootPart")
			crouchIdle:Play()
			while MovementStates.IsCrouching do
				task.wait()
				if HumanoidRootPart.AssemblyLinearVelocity.Magnitude < 0.1 then
					CrouchConfig.CurrentAnimation = "CrouchIdle"
					if CrouchConfig.CurrentAnimation ~= "CrouchIdle" then
						crouchIdle:Play()
						crouchWalk:Stop()
					end
				else
					CrouchConfig.CurrentAnimation = "CrouchWalk"
					if CrouchConfig.CurrentAnimation ~= "CrouchWalk" then
						crouchWalk:Play()
						crouchIdle:Stop()
					end
				end
			end
		end)
		
		UserInputService.InputEnded:Connect(function(input, gpe)
			if gpe then return end
			if input.KeyCode == CrouchConfig.CrouchKeybind then
				CrouchConfig.CrouchState = 0
				Humanoid.WalkSpeed = 16
				FOVTween2:Play()
				task.cancel(animationHandler)
				crouchIdle:Stop()
				crouchWalk:Stop()
				MovementStates.IsCrouching = false
			end
		end)
	end,
}

--[[ FUNCTIONS ]]--

local function PreloadAnims(animator)
	for _, animation in RequiredAnimations do
		local loadedAnim, err = AssetLoader:LoadAnimation(animator, animation)
		if loadedAnim then
			LoadedAnimations[loadedAnim.Name] = loadedAnim
		else
			warn("[MOVEMENT MODULE] Failed to load animation \n Error: "..err)
		end
	end
end

local function BindMobileControls()
	for _, action in Actions do
		local newButton = ContextActionService:BindAction(action, action, true)
		newButton.Position = UDim2.new(0.5, 0, 0.5, 0)
		newButton.Size = UDim2.new(0.1, 0, 0.1, 0)
		newButton.Parent = Player.PlayerGui.HUD
	end
end

--[[ MAIN MODULE ]]--

local MovementModule = {}

function MovementModule:init()
	Player = Players.LocalPlayer
	local Character = Player.Character or Player.CharacterAdded:Wait()
	local Humanoid = Character:WaitForChild("Humanoid")
	local Animator = Humanoid:WaitForChild("Animator")
	
	UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe then return end
		if input.KeyCode == RunConfig.RunKeybind then
			MovementStates.IsRunning = true
			Actions["Run"](Humanoid)
		end
	end)
	UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe then return end
		if input.KeyCode == CrouchConfig.CrouchKeybind then
			MovementStates.IsCrouching = true
			Actions["Crouch"](Humanoid)
		end
	end)
	
	PreloadAnims(Animator)
end

return MovementModule
