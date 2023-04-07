---@diagnostic disable: param-type-mismatch, missing-parameter, undefined-field
---@alias settingmenu.Features {mis: boolean, psr: boolean, russianRoulette: boolean, absorption: boolean, rain: boolean}
---@alias settingmenu.Settings {width: number, height: number, samples: number, maxBounces: number, focalLength: number, sensorHeight: number, hdri: string, hdriExposure: string, features: settingmenu.Features}

-- Matches decimal numbers with a colon separating them.
-- Adapted from: https://stackoverflow.com/a/6192354
local ASPECT_RATIO_PATTERN =
	"(%f[%.%d]%d*%.?%d*%f[^%.%d%]]):(%f[%.%d]%d*%.?%d*%f[^%.%d%]])"

--- Helper to create a form with the proper margins.
---@param name string
---@param frame GPanel
---@return GPanel form
local function makeForm(name, frame)
	local form = frame:Add("DForm")
	form:SetName(name)
	form:DockMargin(0, 10, 0, 0)
	form:Dock(TOP)
	return form
end

--- Creates the setting menu and waits until the user submits the new settings. Calls the supplied callback with those settings.
---@param callback fun(settings: settingmenu.Settings)
local function getSettings(callback)
	local frame = vgui.Create("DFrame")
	frame:SetTitle("Plux Render Settings")
	frame:SetWide(600)
	frame:SetTall(700)
	frame:Center()
	frame:MakePopup()

	---@diagnostic disable-next-line: param-type-mismatch
	--#region Resolution form
	local resolutionForm = makeForm("Resolution", frame)
	local widthSlider = resolutionForm:NumSlider("Width", "", 0, 2048, 0)
	resolutionForm:Help(
		"Enter aspect ratio as a ratio, e.g: '4:3', '16:9', '1:1'"
	)
	local ratioTextEntry = resolutionForm:TextEntry("Aspect Ratio", "")
	ratioTextEntry:SetPlaceholderText("1:1, press enter to set aspect ratio!")

	local aspectX, aspectY = 1, 1
	local height = 0
	local heightLabel = resolutionForm:Help("Height: 0")
	local function updateHeight()
		height = math.floor(widthSlider:GetValue() * (aspectY / aspectX))
		heightLabel:SetText("Height: " .. height)
	end

	widthSlider.OnValueChanged = updateHeight
	function ratioTextEntry:OnEnter(ratio)
		local validRatio = ratio:match(ASPECT_RATIO_PATTERN) ~= nil

		if not validRatio then
			Derma_Message(
				"Aspect ratio is not in correct format!",
				"Incorrect Aspect Ratio Format",
				"OK"
			)
		else
			local aspectXStr, aspectYStr = ratio:match(ASPECT_RATIO_PATTERN)
			-- The type is validated by the lua pattern.
			---@diagnostic disable-next-line: cast-local-type
			aspectX, aspectY = tonumber(aspectXStr), tonumber(aspectYStr)

			updateHeight()
		end
	end
	--#endregion

	--#region Path tracing form
	local pathtraceForm = makeForm("Path Tracing", frame)

	local sampleSlider = pathtraceForm:NumSlider("Samples", "", 1, 512, 0)
	local bouncesSlider = pathtraceForm:NumSlider("Max Bounces", "", 3, 12, 0)
	-- Odd hack around a bug where the slider value is overriden meaning you can't set a default.
	timer.Simple(0, function()
		bouncesSlider:SetValue(3)
		sampleSlider:SetValue(1)
	end)
	--#endregion

	--#region Camera form
	local cameraForm = makeForm("Camera", frame)
	local focalLengthSlider =
		cameraForm:NumSlider("Focal Length", "", 5, 150, 0)
	local sensorHeightSlider =
		cameraForm:NumSlider("Sensor Height", "", 5, 150, 0)

	timer.Simple(0, function()
		focalLengthSlider:SetValue(35)
		sensorHeightSlider:SetValue(25)
	end)
	--#endregion

	--#region HDRI form
	local hdriForm = makeForm("HDRI", frame)
	local hdriTextEntry = hdriForm:TextEntry("HDRI", "")
	local hdriExposureSlider = hdriForm:NumSlider("HDRI Exposure", "", 0, 45, 0)
	hdriTextEntry:SetPlaceholderText(
		"HDRI name in 'data/vistrace_hdris'. Example: pizzo_pernice_4k"
	)

	timer.Simple(0, function()
		hdriExposureSlider:SetValue(1)
	end)
	--#endregion

	--#region Feature form
	local featureForm = makeForm("Features", frame)
	local misCheckBox = featureForm:CheckBox("MIS", "")
	local psrCheckBox = featureForm:CheckBox("PSR", "")
	local rrCheckBox = featureForm:CheckBox("Russian Roulette", "")
	local absorptionCheckBox = featureForm:CheckBox("Absorption", "")
	local rainCheckBox = featureForm:CheckBox("Rain", "")

	timer.Simple(0, function()
		rainCheckBox:SetValue(false)
	end)
	--#endregion

	local submitButton = frame:Add("DButton")
	submitButton:Dock(BOTTOM)
	submitButton:SetText("Submit")
	function submitButton:DoClick()
		-- Enforce certain things to be filled out
		if #hdriTextEntry:GetValue() <= 0 then
			Derma_Message("An HDRI must be set!", "HDRI Not Set", "OK")
			return
		end

		if widthSlider:GetValue() <= 0 or height <= 0 then
			Derma_Message(
				"Width and height must be greater than zero!",
				"Bad Resolution",
				"OK"
			)
			return
		end

		---@type settingmenu.Settings
		local settings = {
			width = math.floor(widthSlider:GetValue()),
			height = height,
			samples = sampleSlider:GetValue(),
			maxBounces = math.floor(bouncesSlider:GetValue()),
			focalLength = focalLengthSlider:GetValue(),
			sensorHeight = sensorHeightSlider:GetValue(),
			hdri = hdriTextEntry:GetValue(),
			hdriExposure = hdriExposureSlider:GetValue(),
			features = {
				mis = misCheckBox:GetChecked(),
				psr = psrCheckBox:GetChecked(),
				russianRoulette = rrCheckBox:GetChecked(),
				absorption = absorptionCheckBox:GetChecked(),
				rain = rainCheckBox:GetChecked(),
			},
		}

		callback(settings)
		frame:Remove()
	end
end

return {
	getSettings = getSettings,
}
