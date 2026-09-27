--!strict
--[[
	Rojo-style toast notifications, stacked in the bottom-right corner of the Studio viewport.
]]

local CoreGui = game:GetService("CoreGui")

local Azul = script:FindFirstAncestor("AzulCompanionPlugin")
local App = Azul.App
local Components = App.Components

local Fusion = require(Azul.Packages.fusion)

local Assets = require(App.Assets)
local Theme = require(App.Theme)

local Box = require(Components.Box)
local Image = require(Components.Image)
local List = require(Components.List)
local Padding = require(Components.Padding)
local Text = require(Components.Text)

local New = Fusion.New
local Value = Fusion.Value
local Computed = Fusion.Computed
local Spring = Fusion.Spring
local Children = Fusion.Children
local OnEvent = Fusion.OnEvent

local WIDTH = 320
local LOGO_SIZE = 32
local DEFAULT_TIMEOUT = 5
local FADE_TIME = 0.4

type Props = {
	Logo: Fusion.CanBeState<string>,
	-- Sounds only play in Edit mode when parented to a plugin widget
	SoundParent: Instance,
}

export type Notify = (text: string, timeout: number?) -> ()

--[=[
	Creates the notifications ScreenGui in CoreGui.
	Returns it along with a function that shows a notification (and plays a sound) for `timeout` seconds.
]=]
return function(props: Props): (ScreenGui, Notify)
	local holder = New("Frame")({
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		[Children] = {
			List({
				Spacing = 6,
				HorizontalAlignment = Enum.HorizontalAlignment.Right,
				VerticalAlignment = Enum.VerticalAlignment.Bottom,
			}),
			Padding({ Padding = 10 }),
		},
	})

	local screenGui = New("ScreenGui")({
		Name = "AzulNotifications",
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		ResetOnSpawn = false,
		DisplayOrder = 100,
		Parent = CoreGui,
		[Children] = holder,
	})

	local count = 0

	local function notify(text: string, timeout: number?)
		count += 1

		local visibility = Value(0)
		local alpha = Spring(visibility, 15, 1)
		local transparency = Computed(function(use) return 1 - use(alpha) end)

		local toast: TextButton
		local dismissed = false
		local function dismiss()
			if dismissed then return end
			dismissed = true
			visibility:set(0)
			task.delay(FADE_TIME, function() toast:Destroy() end)
		end

		toast = New("TextButton")({
			Size = UDim2.fromOffset(WIDTH, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Text = "",
			LayoutOrder = count,
			Parent = holder,
			[OnEvent("Activated")] = dismiss,
			[Children] = Box({
				Size = UDim2.fromScale(1, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = transparency,
				BorderTransparency = transparency,
				[Children] = {
					Padding({ Padding = 10 }),
					List({
						FillDirection = Enum.FillDirection.Horizontal,
						VerticalAlignment = Enum.VerticalAlignment.Center,
						Spacing = 10,
					}),
					Image({
						Size = UDim2.fromOffset(LOGO_SIZE, LOGO_SIZE),
						Image = props.Logo,
						ImageTransparency = transparency,
					}),
					Text({
						Text = text,
						TextSize = Theme.TextSize.Medium,
						TextWrapped = true,
						TextTransparency = transparency,
						Size = UDim2.new(1, -(LOGO_SIZE + 10), 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
					}),
				},
			}),
		})

		visibility:set(1)
		task.delay(timeout or DEFAULT_TIMEOUT, dismiss)

		local sound = New("Sound")({
			SoundId = Assets.Sounds.Notification,
			Parent = props.SoundParent,
		}) :: Sound
		sound.Ended:Once(function() sound:Destroy() end)
		sound:Play()
	end

	return screenGui, notify
end
