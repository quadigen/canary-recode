local vr = game:GetService("VRService")
local run = game:GetService("RunService")
local hands = { Enum.UserCFrame.LeftHand, Enum.UserCFrame.RightHand }
local markers = {}
local pressed = {}
for index, hand in ipairs(hands) do
	local part = Instance.new("Part")
	part.Name = index == 1 and "VRLeftHand" or "VRRightHand"
	part.Size = Vector3.new(0.12, 0.12, 0.18)
	part.Anchored = true
	part.CanCollide = false
	part.Transparency = 1
	part.Parent = workspace
	markers[hand] = part
end

run.RenderStepped:Connect(function()
	local camera = workspace.CurrentCamera
	for _, hand in ipairs(hands) do
		local marker = markers[hand]
		local tracked = vr.VREnabled and camera ~= nil and vr:GetUserCFrameEnabled(hand)
		marker.Transparency = tracked and 0 or 1
		if tracked then
			marker.CFrame = camera.CFrame * vr:GetUserCFrame(hand)
		end
		local state = vr:GetControllerState(hand)
		local down = state.TriggerAvailable and state.Trigger >= 0.7
		marker.Color = down and Color3.fromRGB(90, 255, 130) or Color3.fromRGB(255, 160, 70)
		if down and not pressed[hand] then
			print("VR trigger:", hand, state.Trigger)
			vr:SetControllerHaptic(hand, 0.5, 0.08)
		end
		pressed[hand] = down
	end
end)
