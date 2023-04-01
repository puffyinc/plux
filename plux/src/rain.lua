-- This module handles the rain procedural effect. Basically, it works by projecting a noise texture all over the map, and if the normal of the trace result
-- is somewhat pointing up and is unobscured, then it will use a big perlin noise texture to sample the roughness, making puddles appear.
-- To be honest, this is worse than using a water normal map. However, that requires replacing the textures, and this technique is much more faster and customizable, at the cost of
-- not looking that well at grazing angles.
-- Great to use for cloudy/overcast HDRIs.

local NOISE_PATH = "plux/noise"
local CHECK_SKY = true

local SCALE = 0.0001
local CONTRAST = 2
local UP = Vector(0, 0, 1)

local supported = file.Exists("materials/" .. NOISE_PATH .. ".vtf", "GAME")
if not supported then
	return {
		supported = false,
	}
end

local noiseTex = vistrace.LoadTexture(NOISE_PATH)

--- Checks if the trace result is in rain
---@param result any
---@param bvh any
---@return boolean inRain
local function inRain(result, bvh)
	local hitWorld = result:Entity():EntIndex() == 0
	local skyVisible = true

	if CHECK_SKY then
		local skyTrace = bvh:Traverse(
			vistrace.CalcRayOrigin(result:Pos(), result:GeometricNormal()),
			UP
		)

		skyVisible = not skyTrace or skyTrace:HitSky()
	end

	return hitWorld and result:GeometricNormal():Dot(UP) > 0.85 and skyVisible
end

--- Samples the roughness at the given trace result
---@param result any
---@return number roughness
local function sampleRoughness(result)
	local pos = Vector(result:Pos()[1] * SCALE, result:Pos()[2] * SCALE, 0)
	pos[1] = pos[1] % 1
	pos[2] = pos[2] % 1

	local roughnessVector = noiseTex:Sample(pos[1], pos[2])
	local roughness = roughnessVector[1] ^ CONTRAST
	return roughness
end

return {
	supported = true,
	inRain = inRain,
	sampleRoughness = sampleRoughness,
}
