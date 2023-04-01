-- ACES, using the Stephen Hill fit which is more realistic than a luminance-only fit, such as the one from Krzysztof Narkowicz
-- Source: https://github.com/TheRealMJP/BakingLab/blob/master/BakingLab/ACES.hlsl

--[[
	static const float3x3 ACESInputMat =
	{
		{0.59719, 0.35458, 0.04823},
		{0.07600, 0.90834, 0.01566},
		{0.02840, 0.13383, 0.83777}
	};

	// ODT_SAT => XYZ => D60_2_D65 => sRGB
	static const float3x3 ACESOutputMat =
	{
		{ 1.60475, -0.53108, -0.07367},
		{-0.10208,  1.10813, -0.00605},
		{-0.00327, -0.07276,  1.07602}
	};

	float3 RRTAndODTFit(float3 v)
	{
		float3 a = v * (v + 0.0245786f) - 0.000090537f;
		float3 b = v * (0.983729f * v + 0.4329510f) + 0.238081f;
		return a / b;
	}

	float3 ACESFitted(float3 color)
	{
		color = mul(ACESInputMat, color);

		// Apply RRT and ODT
		color = RRTAndODTFit(color);

		color = mul(ACESOutputMat, color);

		// Clamp to [0, 1]
		color = saturate(color);

		return color;
	}
]]

local ACESInputMat = Matrix({
	{ 0.59719, 0.35458, 0.04823, 0 },
	{ 0.07600, 0.90834, 0.01566, 0 },
	{ 0.02840, 0.13383, 0.83777, 0 },
	{ 0, 0, 0, 1 },
})

local ACESOutputMat = Matrix({
	{ 1.60475, -0.53108, -0.07367, 0 },
	{ -0.10208, 1.10813, -0.00605, 0 },
	{ -0.00327, -0.07276, 1.07602, 0 },
	{ 0, 0, 0, 1 },
})

--- Used for mocking the vector-number operations in HLSL
local function numToVec(number)
	return Vector(number, number, number)
end

--- Clips a vector to 0-1
---@param vec GVector
---@return GVector saturated
local function saturate(vec)
	return Vector(
		math.Clamp(vec[1], 0, 1),
		math.Clamp(vec[2], 0, 1),
		math.Clamp(vec[3], 0, 1)
	)
end

local function RRTAndODTFit(v)
	local a = v * (v + numToVec(0.0245786)) - numToVec(0.000090537)
	local b = v * (0.983729 * v + numToVec(0.4329510)) + numToVec(0.238081)
	return Vector(a[1] / b[1], a[2] / b[2], a[3] / b[3])
end

--[[
	Source: https://github.com/TheRealMJP/BakingLab/blob/1a043117506ac5b5bcade5c86d808485f3c70b12/BakingLab/ToneMapping.hlsl#L31-L42
	float3 LinearTosRGB(in float3 color)
	{
		float3 x = color * 12.92f;
		float3 y = 1.055f * pow(saturate(color), 1.0f / 2.4f) - 0.055f;

		float3 clr = color;
		clr.r = color.r < 0.0031308f ? x.r : y.r;
		clr.g = color.g < 0.0031308f ? x.g : y.g;
		clr.b = color.b < 0.0031308f ? x.b : y.b;

		return clr;
	}
]]

local function powVec(vec, power)
	return Vector(
		math.pow(vec[1], power),
		math.pow(vec[2], power),
		math.pow(vec[3], power)
	)
end

--- Transforms a linear RGB color to a sRGB-encoded color.
---@param color GVector
---@return GVector srgb
local function linearTosRGB(color)
	local x = color * 12.92
	local y = 1.055 * powVec(saturate(color), 1.0 / 2.4) - numToVec(0.055)

	local clr = color
	clr[1] = color[1] < 0.0031308 and x[1] or y[1]
	clr[2] = color[2] < 0.0031308 and x[2] or y[2]
	clr[3] = color[3] < 0.0031308 and x[3] or y[3]

	return clr
end

--- Converts a FFF VisTrace RT to a 888 VisTrace RT by clipping any values that are out of the [0, 1] range
---@param rt any
---@return any rt New RT
local function fffto888(rt)
	local newRT = vistrace.CreateRenderTarget(
		rt:GetWidth(),
		rt:GetHeight(),
		VisTraceRTFormat.RGB888
	)

	for y = 0, rt:GetHeight() - 1 do
		for x = 0, rt:GetWidth() - 1 do
			newRT:SetPixel(x, y, saturate(rt:GetPixel(x, y)))
		end
	end

	return newRT
end

--- Performs an ACES tonemap on the given linear RGB vector.
---@param color GVector
---@return GVector tonemapped
local function tonemap(color)
	color = ACESInputMat * color

	-- Apply RRT and ODT
	color = RRTAndODTFit(color)
	color = ACESOutputMat * color

	color = Vector(
		math.Clamp(color[1], 0, 1),
		math.Clamp(color[2], 0, 1),
		math.Clamp(color[3], 0, 1)
	)

	return color
end

--- Converts a Color into a normalized 0-1 RGB Vector
---@param color GColor
---@return GVector vecColor
local function toNormalizedVector(color)
	return Vector(color.r / 255, color.g / 255, color.b / 255)
end

--- Converts a Color into a Vector, nothing modified
---@param color GColor
---@return GVector vecColor
local function toVector(color)
	return Vector(color.r, color.g, color.b)
end

return {
	tonemap = tonemap,
	linearTosRGB = linearTosRGB,
	saturate = saturate,
	fffto888 = fffto888,
	toNormalizedVector = toNormalizedVector,
	toVector = toVector,
}
