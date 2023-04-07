local denoisingSupported, failReason = pcall(require, "gmdenoiser")
if not denoisingSupported then
	print(("Plux: Denoising is not supported! Reason: '%s'"):format(failReason))
end

-- Loads the context menu extension for Plux.
include("adjustments.lua")

---@module 'settings'
local settings = include("settings.lua")

---@module 'colors'
local colors = include("colors.lua")

---@module 'lights'
local lights = include("lights.lua")

---@module 'experimental/psr'
local psr = include("experimental/psr.lua")

---@module 'pathtracer'
local pathtracer = include("pathtracer.lua")

local lightCollection = lights.LightCollection.new()

--- Curve which allows you to crank up the intensity while also keeping low intensity by using a quadratic curve.
--- Tuned in Desmos, basically means low alpha values will be treated as low intensity, but high alpha values will be treated as extreme intensity.
--- This is done to reduce the amount of complexity when setting up a scene.
---@return number x
local function intensityCurve(x)
	return (x * x) * 0.07
end

local props = ents.FindByClass("prop_*")
local filteredProps = {}
for _, prop in pairs(props) do
	if prop:GetMaterial() == lights.LIGHT_MATERIAL then
		-- Registers a light, lights are hunter plastic plates which emit light from the top or from all sides if toggled.
		-- The RGB of the entity color is used as the light color, and the alpha is used as the intensity. 0 = no light, 255 = insane amount of light.
		-- 100 is usually enough to light up a room.

		local color = prop:GetColor()
		local intensity = colors.toNormalizedVector(color)

		intensity = intensity * intensityCurve(color.a)
		lightCollection:newAreaLight(prop, intensity)
	else
		filteredProps[#filteredProps + 1] = prop
	end
end

local bvh = vistrace.CreateAccel(filteredProps)
local hdri = vistrace.LoadHDRI(settings.HDRI)
---@type vistrace.Sampler
local sampler = vistrace.CreateSampler()

local camScaleVertical = 0.5 * settings.SENSOR_HEIGHT / settings.FOCAL_LENGTH
local camScaleHorizontal = settings.WIDTH / settings.HEIGHT * camScaleVertical
local camPos, camAng = LocalPlayer():EyePos(), LocalPlayer():EyeAngles()
--- Currently disabled due to a VisTrace regression.
local camConeAngle = math.atan(2 * camScaleVertical / settings.HEIGHT)

local albedo = vistrace.CreateRenderTarget(
	settings.WIDTH,
	settings.HEIGHT,
	VisTraceRTFormat.RGBFFF
)
local normal = vistrace.CreateRenderTarget(
	settings.WIDTH,
	settings.HEIGHT,
	VisTraceRTFormat.RGBFFF
)
local output = vistrace.CreateRenderTarget(
	settings.WIDTH,
	settings.HEIGHT,
	VisTraceRTFormat.RGBFFF
)

--- Transforms a radiance value to a display color.
--- Pretty much just tonemaps and converts to sRGB.
---@param radiance GVector Radiance value
---@return GVector color 0-1 RGB color
local function display(radiance)
	return colors.linearTosRGB(colors.tonemap(radiance))
end

--- Miss program. In the future, this will be extended to trace the map's skybox.
---@param dir GVector
---@return GVector radiance Computed radiance.
local function miss(dir)
	return hdri:GetPixel(dir)
end

--- Generates a camera ray given a pixel
---@param x number
---@param y number
---@return GVector
local function generateRay(x, y)
	local camX = (1 - 2 * (x + 0.5) / settings.WIDTH) * camScaleHorizontal
	local camY = (1 - 2 * (y + 0.5) / settings.HEIGHT) * camScaleVertical

	local camDir = Vector(1, camX, camY)
	camDir:Rotate(camAng)
	camDir:Normalize()

	return camDir
end

--- Renders a pixel (x, y).
---@param x number
---@param y number
---@return GVector radiance Computed radiance.
local function renderPixel(x, y)
	local camDir = generateRay(x, y)
	local result = bvh:Traverse(camPos, camDir)
	if not result or result:HitSky() then
		return miss(camDir)
	end

	albedo:SetPixel(x, y, colors.linearTosRGB(result:Albedo()))
	normal:SetPixel(x, y, result:Normal())

	if settings.FEATURES.PSR then
		if
			psr.apply({
				x = x,
				y = y,
				albedo = albedo,
				normal = normal,
				bvh = bvh,
				sampler = sampler,
				result = result,

				onMiss = miss,
			})
		then
			-- Convert surface albedo to sRGB
			albedo:SetPixel(x, y, colors.linearTosRGB(albedo:GetPixel(x, y)))
		end
	end

	-- Average the computed radiance of n amount of samples.
	local radiance = Vector(0, 0, 0)

	---@type pathtracer.PathtraceInput
	local pathtracerInput = {
		bvh = bvh,
		lightCollection = lightCollection,
		hdri = hdri,
		sampler = sampler,
		result = result,
	}

	for _ = 1, settings.SAMPLES do
		radiance = radiance + pathtracer.pathtrace(pathtracerInput)
	end

	radiance = radiance / settings.SAMPLES
	return radiance
end

local startTime = os.clock()

for y = 0, settings.HEIGHT - 1 do
	for x = 0, settings.WIDTH - 1 do
		output:SetPixel(x, y, display(renderPixel(x, y)))
	end
end

output:Save("plux_render_noisy")
if denoisingSupported then
	output:Denoise({
		Albedo = albedo,
		Normal = normal,

		AlbedoNoisy = false,
		NormalNoisy = false,

		sRGB = true,
	})
end

print(("Render took %.2f seconds!"):format(os.clock() - startTime))
print(
	("Render info:\nDimensions: %dx%d\nSamples: %d\nMax Bounces: %d\nFocal Length: %d\nSensor Height: %d"):format(
		settings.WIDTH,
		settings.HEIGHT,
		settings.SAMPLES,
		settings.MAX_BOUNCES,
		settings.FOCAL_LENGTH,
		settings.SENSOR_HEIGHT
	)
)

print("Settings dump:")
---@diagnostic disable-next-line: missing-parameter
PrintTable(settings)

-- We want the full render to be viewed as a PNG, so we transform it to RGB888.
local outputPNG = colors.fffto888(output)
outputPNG:Save("plux_render")

if settings.DEBUG_GBUFFER then
	albedo:Save("plux_albedo")
	-- To identify normals, this is converted to 0, 1 for debugging.
	for y = 0, settings.HEIGHT - 1 do
		for x = 0, settings.WIDTH - 1 do
			normal:SetPixel(
				x,
				y,
				normal:GetPixel(x, y) * 0.5 + Vector(0.5, 0.5, 0.5)
			)
		end
	end
	normal:Save("plux_normal")
end
