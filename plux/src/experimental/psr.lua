-- Primary surface replacement (PSR)
-- https://developer.nvidia.com/blog/rendering-perfect-reflections-and-refractions-in-path-traced-games/

-- All this does is try to resolve secondary surfaces for objects that support it, such as perfect glass and perfect mirrors.
-- After that, the results are saved in the G-buffer which allows OIDN to denoise much more effectively.

---@module 'settings'
local settings = include("../settings.lua")

---@module 'pathtracer'
local pathtracer = include("../pathtracer.lua")

---@alias psr.SecondarySurface {valid: boolean, direction: GVector, isSky: boolean, albedo: GVector, normal: GVector}

local MAX_PSR_DEPTH = 8

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

--- Schlick's approximation
---@param cosTheta number
---@param mat any
---@return number coefficient
local function schlicksFresnel(cosTheta, mat)
	local n1 = mat:IoR()
	local n2 = mat:OutsideIoR()

	local R0 = (n1 - n2) / (n1 + n2)
	R0 = R0 * R0

	return R0 + (1 - R0) * math.pow(1 - cosTheta, 5)
end

local cnt = 0
local function resolveGlass(result, _, input, sampler, bvh, depth)
	depth = depth or 0

	if depth > MAX_PSR_DEPTH then
		return {
			albedo = Vector(0, 0, 0),
			normal = Vector(0, 0, 0),
		}
	end

	local mat = pathtracer.getMaterial(result)
	if not isGlass(mat) then
		if result:HitSky() then
			return {
				albedo = input.onMiss(-result:Incident()),
				normal = Vector(0, 0, 0),
			}
		end
		return {
			albedo = result:Albedo(),
			normal = result:Normal(),
		}
	end

	local fresnel = schlicksFresnel(
		result:Incident():Dot(
			result:FrontFacing() and result:GeometricNormal()
				or -result:GeometricNormal()
		),
		mat
	)
	local refraction = {
		albedo = Vector(0, 0, 0),
		normal = Vector(0, 0, 0),
	}

	local reflection = {
		albedo = Vector(0, 0, 0),
		normal = Vector(0, 0, 0),
	}

	-- 3 cases are considered.
	-- 1. Refraction
	-- 2. Reflection
	-- 3. Total Internal Reflection

	-- Because there's so many possibilities, all the cases are calculated recursively according to a max depth, just like naive recursive ray tracing!

	-- Refraction
	local oldLobes = mat:ActiveLobes()
	mat:ActiveLobes(LobeType.Transmission)
	local sample = result:SampleBSDF(sampler, mat)
	mat:ActiveLobes(oldLobes)

	local tir = false

	if sample then
		local viewside = bit.band(LobeType.Transmission, sample.lobe) == 0

		local transmitOut = viewside == result:FrontFacing()
		local origin = vistrace.CalcRayOrigin(
			result:Pos(),
			transmitOut and result:GeometricNormal()
				or -result:GeometricNormal()
		)

		local refractionResult = bvh:Traverse(origin, sample.scattered)

		if not refractionResult then
			refraction.albedo = Vector(0, 0, 0)
			refraction.normal = Vector(0, 0, 0)

			tir = true
		else
			local surface = resolveGlass(
				refractionResult,
				_,
				input,
				sampler,
				bvh,
				depth + 1
			)
			refraction = surface
		end
	end

	-- Refraction
	local oldLobes = mat:ActiveLobes()
	mat:ActiveLobes(LobeType.Reflection)
	local sample = result:SampleBSDF(sampler, mat)
	mat:ActiveLobes(oldLobes)

	if sample then
		local outside = result:FrontFacing()
		local origin = vistrace.CalcRayOrigin(
			result:Pos(),
			outside and result:GeometricNormal() or -result:GeometricNormal()
		)

		local reflectionResult = bvh:Traverse(origin, sample.scattered)

		if not reflectionResult then
			reflection.albedo = Vector(0, 0, 0)
			reflection.normal = Vector(0, 0, 0)
		else
			local surface = resolveGlass(
				reflectionResult,
				_,
				input,
				sampler,
				bvh,
				depth + 1
			)
			reflection = surface
		end
	end

	if tir then
		return {
			albedo = reflection.albedo,
			normal = reflection.normal,
		}
	end

	local mixedAlbedo = reflection.albedo * fresnel
		+ refraction.albedo * (1 - fresnel)
	local mixedNormal = reflection.normal * fresnel
		+ refraction.normal * (1 - fresnel)

	return {
		albedo = mixedAlbedo,
		normal = mixedNormal,
	}
end

--- Finds a secondary surface for a primary perfect glass/mirror surface.
---@param result any Result of hitting the mirror.
---@param reflection boolean If true, trace only reflections, if false, trace only refractions and diffuse surfaces.
---@param sampler vistrace.Sampler Sampler to use.
---@param bvh any
---@return psr.SecondarySurface result
local function findSecondarySurface(result, reflection, input, sampler, bvh)
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
			if isGlass(mat) then
				local surface =
					resolveGlass(result, reflection, input, sampler, bvh)
				return {
					valid = true,
					direction = -result:Incident(),
					albedo = surface.albedo,
					normal = surface.normal,
				}
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
