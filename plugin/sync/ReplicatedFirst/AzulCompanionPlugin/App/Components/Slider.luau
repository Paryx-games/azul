--!strict
--[[
	Horizontal number slider with an editable value box on its left.
	Click or drag along the track to pick a value, or type one into the box.
]]

local Azul = script:FindFirstAncestor("AzulCompanionPlugin")
local App = Azul.App
local Components = App.Components
local Util = Components.Util

local Fusion = require(Azul.Packages.fusion)

local Theme = require(App.Theme)
local animate = require(Util.animate)
local getState = require(Util.getState)
local stripProps = require(Util.stripProps)

local Box = require(Components.Box)
local Container = require(Components.Container)
local Corner = require(Components.Corner)
local Input = require(Components.Input)
local Padding = require(Components.Padding)

local New = Fusion.New
local Value = Fusion.Value
local Computed = Fusion.Computed
local Observer = Fusion.Observer
local Hydrate = Fusion.Hydrate
local Children = Fusion.Children
local OnEvent = Fusion.OnEvent
local Ref = Fusion.Ref
local peek = Fusion.peek

local BOX_WIDTH = 48
local GAP = 10
local RAIL_HEIGHT = 4
local TICK_HEIGHT = 10
local KNOB_SIZE = 14
-- ponytail: above this many steps, ticks mark every Nth step so the rail doesn't turn into a solid comb
local MAX_TICKS = 25

local COMPONENT_ONLY_PROPS = {
	"Value",
	"Min",
	"Max",
	"Step",
	"Format",
	"Changed",
}

type Props = {
	Value: Fusion.Value<number>?,
	Min: number,
	Max: number,
	Step: number?,
	-- Turns a value into the box text, e.g. to show the minimum as "∞"
	Format: ((value: number) -> string)?,
	-- Fires once the user releases the slider or confirms a typed value, if the value changed
	Changed: ((value: number) -> ())?,
	[any]: any,
}

--[=[
	Creates a slider bound to `props.Value`, snapping to multiples of `props.Step` (default 1) between `Min` and `Max`.
	Typed values are only held to `Min`, so values above `Max` can still be entered by hand.
]=]
return function(props: Props): Instance
	local value: Fusion.Value<number> = props.Value or Value(props.Min)
	local min, max, step = props.Min, props.Max, props.Step or 1
	local format: (number) -> string = props.Format or tostring

	local railRef: Fusion.Value<GuiObject?> = Value(nil)
	local boxRef: Fusion.Value<TextBox?> = Value(nil)
	local isHovered = Value(false)
	local isDragging = Value(false)

	local color = animate(
		Theme.Colors.Brand,
		getState({
			Hovered = isHovered,
			Pressed = isDragging,
		})
	)

	-- Knob/fill position; out-of-range values are pinned to the ends
	local ratio = Computed(function(use) return math.clamp((use(value) - min) / (max - min), 0, 1) end)

	local function commit(newValue: number)
		if newValue == peek(value) then return end
		value:set(newValue)
		if props.Changed then props.Changed(newValue) end
	end

	-- Keeps the box in sync with the value, including changes made by dragging or from outside
	local function refreshBox()
		local box = peek(boxRef)
		if box then box.Text = format(peek(value)) end
	end
	Observer(value):onChange(refreshBox)

	local function setFromX(x: number)
		local rail = peek(railRef)
		if not rail then return end
		local fraction = math.clamp((x - rail.AbsolutePosition.X) / rail.AbsoluteSize.X, 0, 1)
		local stepped = math.clamp(min + math.round(fraction * (max - min) / step) * step, min, max)
		if stepped ~= peek(value) then value:set(stepped) end
	end

	local function startDrag(x: number)
		local rail = peek(railRef)
		if not rail then return end
		local startValue = peek(value)
		isDragging:set(true)
		setFromX(x)

		-- A full-size overlay keeps receiving mouse input once the cursor leaves the track;
		-- UserInputService doesn't see input inside plugin widgets
		local overlay: Instance
		local function stopDrag()
			if not peek(isDragging) then return end
			isDragging:set(false)
			overlay:Destroy()
			if props.Changed and peek(value) ~= startValue then props.Changed(peek(value)) end
		end

		overlay = New("TextButton")({
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Text = "",
			ZIndex = 10000,
			Parent = rail:FindFirstAncestorWhichIsA("LayerCollector"),
			[OnEvent("InputChanged")] = function(input: InputObject)
				if input.UserInputType == Enum.UserInputType.MouseMovement then setFromX(input.Position.X) end
			end,
			[OnEvent("MouseButton1Up")] = stopDrag,
			[OnEvent("MouseLeave")] = stopDrag,
		})
	end

	-- One tick per step (or per Nth step on long ranges), laid out on the same span the knob centre travels
	local steps = math.round((max - min) / step)
	local tickEvery = math.ceil(steps / MAX_TICKS)
	local ticks: { Instance } = {}
	local function addTick(i: number)
		table.insert(
			ticks,
			Container({
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(i / steps, 0.5),
				Size = UDim2.fromOffset(1, TICK_HEIGHT),
				AutomaticSize = Enum.AutomaticSize.None,
				BackgroundColor3 = Theme.Colors.TextDimmed,
				BackgroundTransparency = 0.5,
			})
		)
	end
	for i = 0, steps, tickEvery do
		addTick(i)
	end
	-- Always mark the maximum, even when it isn't a multiple of `tickEvery`
	if steps % tickEvery ~= 0 then addTick(steps) end

	return Hydrate(Container({
		Size = UDim2.new(1, 0, 0, Theme.CompSizeY.Small),
		AutomaticSize = Enum.AutomaticSize.None,
		[Children] = {
			Box({
				Size = UDim2.new(0, BOX_WIDTH, 1, 0),
				AutomaticSize = Enum.AutomaticSize.None,
				[Children] = {
					Padding({
						Padding = 6,
						Vertical = false,
					}),
					Input({
						Text = format(peek(value)),
						TextXAlignment = Enum.TextXAlignment.Center,
						TextSize = Theme.TextSize.Medium,
						PlaceholderText = "",
						Size = UDim2.fromScale(1, 1),
						[Ref] = boxRef,
						Finished = function(text)
							local typed = tonumber(text)
							if typed then commit(math.max(typed, min)) end
							refreshBox()
						end,
					}),
				} :: { Instance },
			}),
			-- Track (hit area), inset so the knob centre can reach both ends of the rail
			New("TextButton")({
				Position = UDim2.fromOffset(BOX_WIDTH + GAP, 0),
				Size = UDim2.new(1, -(BOX_WIDTH + GAP), 1, 0),
				BackgroundTransparency = 1,
				Text = "",
				[OnEvent("MouseEnter")] = function() isHovered:set(true) end,
				[OnEvent("MouseLeave")] = function() isHovered:set(false) end,
				[OnEvent("InputBegan")] = function(input: InputObject)
					if input.UserInputType == Enum.UserInputType.MouseButton1 then startDrag(input.Position.X) end
				end,
				[Children] = {
					Padding({
						Padding = KNOB_SIZE / 2,
						Vertical = false,
					}),
					Container({
						Size = UDim2.fromScale(1, 1),
						AutomaticSize = Enum.AutomaticSize.None,
						[Ref] = railRef,
						[Children] = {
							Container({
								Size = UDim2.fromScale(1, 1),
								AutomaticSize = Enum.AutomaticSize.None,
								[Children] = ticks,
							}),
							-- Rail
							Container({
								AnchorPoint = Vector2.new(0, 0.5),
								Position = UDim2.fromScale(0, 0.5),
								Size = UDim2.new(1, 0, 0, RAIL_HEIGHT),
								AutomaticSize = Enum.AutomaticSize.None,
								BackgroundColor3 = Theme.Colors.Border,
								BackgroundTransparency = 0,
								[Children] = {
									Corner({ Radius = RAIL_HEIGHT }),
									-- Fill
									Container({
										Size = Computed(function(use) return UDim2.fromScale(use(ratio), 1) end),
										AutomaticSize = Enum.AutomaticSize.None,
										BackgroundColor3 = color,
										BackgroundTransparency = 0,
										[Children] = Corner({ Radius = RAIL_HEIGHT }),
									}),
								} :: { Instance },
							}),
							-- Knob
							Container({
								AnchorPoint = Vector2.new(0.5, 0.5),
								Position = Computed(function(use) return UDim2.fromScale(use(ratio), 0.5) end),
								Size = UDim2.fromOffset(KNOB_SIZE, KNOB_SIZE),
								AutomaticSize = Enum.AutomaticSize.None,
								BackgroundColor3 = color,
								BackgroundTransparency = 0,
								[Children] = Corner({ Radius = KNOB_SIZE }),
							}),
						},
					}),
				} :: { Instance },
			}),
		} :: { Instance },
	}))(stripProps(props, COMPONENT_ONLY_PROPS))
end
