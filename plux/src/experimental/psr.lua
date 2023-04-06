-- Primary surface replacement (PSR)
-- https://developer.nvidia.com/blog/rendering-perfect-reflections-and-refractions-in-path-traced-games/

-- All this does is try to resolve secondary surfaces for objects that support it, such as perfect glass and perfect mirrors.
-- After that, the results are saved in the G-buffer which allows OIDN to denoise much more effectively.

---@module 'pathtracer'
local pathtracer = include("../pathtracer.lua")

---@alias psr.Input {x: number, y: number, albedo: vistrace.RenderTarget, normal: vistrace.RenderTarget, result: any, sampler: vistrace.Sampler, bvh: any, onMiss: fun(dir:GVector):GVector}
---@alias psr.SecondarySurface {valid: boolean, albedo: GVector, normal: GVector}

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

--- Recursive function which resolves a path's albedo and normal from tracing the reflection and refraction rays.
---@param result any
---@param onMiss fun(dir:GVector):GVehicle
---@param sampler vistrace.Sampler
---@param bvh any
---@param depth number|nil
---@return {albedo: GVector, normal: GVector}
local function resolveGlass(result, onMiss, sampler, bvh, depth)
	depth = depth or 0

	if depth > MAX_PSR_DEPTH then
		return {
			albedo = Vector(0, 0, 0),
			normal = Vector(0, 0, 0),
		}
	end

	if result:HitSky() then
		return {
			---@diagnostic disable-next-line: param-type-mismatch
			albedo = onMiss(-result:Incident()),
			normal = Vector(0, 0, 0),
		}
	end

	local mat = pathtracer.getMaterial(result)
	if not isGlass(mat) then
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

	local tir = false

	local function sampleWithLobe(lobe)
		local oldLobes = mat:ActiveLobes()
		mat:ActiveLobes(lobe)
		local sample = result:SampleBSDF(sampler, mat)
		mat:ActiveLobes(oldLobes)

		return sample
	end

	local refractionSample = sampleWithLobe(LobeType.Transmission)
	if refractionSample then
		local viewside = bit.band(LobeType.Transmission, refractionSample.lobe)
			== 0

		local transmitOut = viewside == result:FrontFacing()
		local origin = vistrace.CalcRayOrigin(
			result:Pos(),
			transmitOut and result:GeometricNormal()
				or -result:GeometricNormal()
		)

		local refractionResult =
			bvh:Traverse(origin, refractionSample.scattered)

		if not refractionResult then
			refraction.albedo = Vector(0, 0, 0)
			refraction.normal = Vector(0, 0, 0)

			tir = true
		else
			local surface =
				resolveGlass(refractionResult, onMiss, sampler, bvh, depth + 1)
			refraction = surface
		end
	end

	-- Refraction
	local reflectionSample = sampleWithLobe(LobeType.Reflection)
	if reflectionSample then
		local outside = result:FrontFacing()
		local origin = vistrace.CalcRayOrigin(
			result:Pos(),
			outside and result:GeometricNormal() or -result:GeometricNormal()
		)

		local reflectionResult =
			bvh:Traverse(origin, reflectionSample.scattered)

		if not reflectionResult then
			reflection.albedo = Vector(0, 0, 0)
			reflection.normal = Vector(0, 0, 0)
		else
			local surface =
				resolveGlass(reflectionResult, onMiss, sampler, bvh, depth + 1)
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
---@param onMiss fun(dir:GVector):GVector Function which returns a color based on the given direction when the ray misses.
---@param sampler vistrace.Sampler Sampler to use.
---@param bvh any
---@return psr.SecondarySurface result
local function findSecondarySurface(result, onMiss, sampler, bvh)
	local result = result

	for _ = 1, MAX_PSR_DEPTH do
		if result:HitSky() then
			return {
				valid = true,
				---@diagnostic disable-next-line: param-type-mismatch
				albedo = onMiss(-result:Incident()),
				normal = Vector(0, 0, 0),
			}
		end

		local mat = pathtracer.getMaterial(result)

		if not isQualifiedSurface(mat) then
			return {
				valid = true,
				albedo = result:Albedo(),
				normal = result:Normal(),
			}
		elseif isQualifiedSurface(mat) then
			if isGlass(mat) then
				local surface = resolveGlass(result, onMiss, sampler, bvh)
				return {
					valid = true,
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

--- Applies PSR to the given input.
---@param input psr.Input
---@return boolean applied True if any PSR was applied
local function apply(input)
	if isQualifiedSurface(pathtracer.getMaterial(input.result)) then
		local secondarySurface = findSecondarySurface(
			input.result,
			input.onMiss,
			input.sampler,
			input.bvh
		)

		if secondarySurface.valid then
			input.albedo:SetPixel(input.x, input.y, secondarySurface.albedo)
			input.normal:SetPixel(input.x, input.y, secondarySurface.normal)
		end

		return true
	end

	return false
end

return {
	isQualifiedSurface = isQualifiedSurface,
	apply = apply,
	isMirror = isMirror,
	findSecondarySurface = findSecondarySurface,
}
