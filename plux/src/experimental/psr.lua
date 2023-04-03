-- Primary surface replacement (PSR)
-- https://developer.nvidia.com/blog/rendering-perfect-reflections-and-refractions-in-path-traced-games/

-- All this does is try to resolve secondary surfaces for objects that support it, such as perfect glass and perfect mirrors.
-- After that, the results are saved in the G-buffer which allows OIDN to denoise much more effectively.

---@module 'settings'
local settings = include("../settings.lua")

---@module 'pathtracer'
local pathtracer = include("../pathtracer.lua")

---@alias psr.SecondarySurface {valid: boolean, direction: GVector, isSky: boolean, albedo: GVector, normal: GVector}

local MAX_PSR_DEPTH = 24

--- Checks if the given material is a mirror
---@param mat any
---@return boolean
local function isMirror(mat)
	return mat:Metalness() == 1 and mat:Roughness() == 0
end

--- Checks if the given material is a mirror
---@param mat any
---@return boolean
local function isGlass(mat)
	return mat:Roughness() == 0 and mat:SpecularTransmission() == 1
end

--- Checks if a material is qualified for PSR
---@param mat any
---@return boolean
local function isQualifiedSurface(mat)
	return isMirror(mat) or isGlass(mat)
end

--- Finds a secondary surface for a primary perfect glass/mirror surface.
---@param result any Result of hitting the mirror.
---@param reflection boolean If true, trace only reflections, if false, trace only refractions and diffuse surfaces.
---@param sampler vistrace.Sampler Sampler to use.
---@param bvh any
---@return psr.SecondarySurface result
local function findSecondarySurface(result, reflection, sampler, bvh)
	local result = result
	-- Required for some effects like absorption.
	local throughput = Vector(1, 1, 1)

	for _ = 1, MAX_PSR_DEPTH do
		if result:HitSky() then
			return {
				valid = true,
				isSky = true,
				direction = -result:Incident(),
			}
		end

		local mat, absorption = pathtracer.getMaterial(result)

		if not isQualifiedSurface(mat) then
			return {
				valid = true,
				direction = -result:Incident(),
				albedo = result:Albedo() * throughput,
				normal = result:Normal(),
			}
		elseif isQualifiedSurface(mat) then
			local oldLobes = mat:ActiveLobes()
			mat:ActiveLobes(
				reflection and LobeType.Reflection or LobeType.Transmission
			)

			local sample = result:SampleBSDF(sampler, mat)
			mat:ActiveLobes(oldLobes)

			if sample then
				local viewside = bit.band(LobeType.Transmission, sample.lobe)
					== 0

				local transmitOut = viewside == result:FrontFacing()
				local origin = vistrace.CalcRayOrigin(
					result:Pos(),
					transmitOut and result:GeometricNormal()
						or -result:GeometricNormal()
				)

				result = bvh:Traverse(origin, sample.scattered)

				if not result then
					return {
						valid = true,
						isSky = true,
						direction = sample.scattered,
					}
				end

				-- Absorption for refractive objects
				if
					settings.FEATURES.ABSORPTION
					and not reflection
					and absorption
					and not transmitOut
					and IsValid(result:Entity())
				then
					local dist = origin:Distance(result:Pos())
					local absorptionWeight = -absorption * dist
					absorptionWeight = Vector(
						math.exp(absorptionWeight[1]),
						math.exp(absorptionWeight[2]),
						math.exp(absorptionWeight[3])
					)

					throughput = throughput * absorptionWeight
				end
			end
		end
	end

	return {
		valid = false,
	}
end

return {
	isQualifiedSurface = isQualifiedSurface,
	isMirror = isMirror,
	findSecondarySurface = findSecondarySurface,
}
