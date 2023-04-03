---@module 'settings'
local settings = include("settings.lua")

---@module 'colors'
local colors = include("colors.lua")

---@module 'rain'
local rain = include("rain.lua")

---@module 'mis'
local mis = include("mis.lua")

---@alias pathtracer.PathtraceInput {result: any, sampler: vistrace.Sampler, lightCollection: lights.LightCollection, hdri: any, bvh: any}

local basicMaterial = vistrace.CreateMaterial()
local waterMaterial = vistrace.CreateMaterial()
waterMaterial:Roughness(0)
waterMaterial:Metalness(0)
waterMaterial:SpecularTransmission(1)

--- Gets a material from a TraceResult. This can be a custom material or the basic material or even the water material. It can also return an absorption vector.
---@param result any
---@return any material, GVector|nil absorption
local function getMaterial(result)
	if result:HitWater() then
		return waterMaterial, settings.WATER_ABSORPTION
	end

	local absorption = nil
	if IsValid(result:Entity()) then
		absorption = colors.toVector(result:Entity():GetColor())
		return result:Entity():GetBSDFMaterial(), absorption
	end

	return basicMaterial
end

--- Pathtraces the given input.
---@param input pathtracer.PathtraceInput
---@return GVector
local function pathtrace(input)
	-- Path sampling implemented according to:
	-- https://graphics.stanford.edu/courses/cs348b-01/course29.hanrahan.pdf
	-- Multi sample model estimator.
	-- https://blog.demofox.org/2020/11/25/multiple-importance-sampling-in-1d/
	-- https://graphics.stanford.edu/courses/cs348b-03/papers/veach-chapter9.pdf

	-- Color is the result affected by throughput and other lighting (HDRI, lights).
	-- Throughput is affected by the surfaces the path bounces off of, and absorption.

	local color = Vector(0, 0, 0)
	local throughput = Vector(1, 1, 1)
	local result = input.result

	for _ = 1, settings.MAX_BOUNCES do
		if result then
			local mat, absorption = getMaterial(result)

			local oldRoughness = mat:Roughness()

			if
				settings.FEATURES.RAIN
				and rain.supported
				and rain.inRain(result, input.bvh)
			then
				mat:Roughness(rain.sampleRoughness(result))
			end

			local bsdfSample = result:SampleBSDF(input.sampler, mat)

			if
				settings.FEATURES.RAIN
				and rain.supported
				and rain.inRain(result, input.bvh)
			then
				mat:Roughness(oldRoughness)
			end

			if bsdfSample then
				local lobe = bsdfSample.lobe
				local delta = bit.band(LobeType.Delta, lobe) ~= 0
				local viewside = bit.band(LobeType.Transmission, lobe) == 0
				local transmitOut = viewside == result:FrontFacing()

				local origin = vistrace.CalcRayOrigin(
					result:Pos(),
					transmitOut and result:GeometricNormal()
						or -result:GeometricNormal()
				)

				if settings.FEATURES.MIS then
					-- Samples the HDRI and uses MIS to properly weight it.
					local skyValid, skyDir, skyCol, skyPdf =
						input.hdri:Sample(input.sampler)
					if skyValid then
						local skyResult = input.bvh:Traverse(origin, skyDir)
						if not skyResult or skyResult:HitSky() then
							local skyWeight = skyCol / skyPdf
							local misWeight = delta and 1
								or mis.powerHeuristic2(
									skyPdf,
									result:EvalPDF(mat, skyDir)
								)

							color = color
								+ throughput
									* skyWeight
									* misWeight
									* result:EvalBSDF(mat, skyDir)
						end
					end

					-- Samples the light collection and uses MIS to properly weight it.
					-- TODO: Is the MIS weight valid in this case?
					local lightSample =
						input.lightCollection:sample(input.sampler, origin)
					if lightSample.valid then
						local lightResult = input.bvh:Traverse(
							origin,
							lightSample.dir,
							0,
							lightSample.distance
						)

						local misWeight = delta and 1
							or mis.powerHeuristic2(
								lightSample.pdf,
								result:EvalPDF(mat, lightSample.dir)
							)

						if not lightResult then
							color = color
								+ throughput
									* lightSample.weight
									* result:EvalBSDF(mat, lightSample.dir)
									* misWeight
						end
					end
				end

				-- Attenuate throughput
				throughput = throughput * bsdfSample.weight

				if settings.FEATURES.RUSSIAN_ROULETTE then
					-- Russian roulette
					local terminationProb = math.max(
						throughput[1],
						math.max(throughput[2], throughput[3])
					)

					if input.sampler:GetFloat() > terminationProb then
						break
					end

					-- Add the lost energy back.
					throughput = throughput * (1 / terminationProb)
				end

				result = input.bvh:Traverse(origin, bsdfSample.scattered)

				if not result or result:HitSky() then
					local misWeight

					if settings.FEATURES.MIS then
						misWeight = mis.powerHeuristic2(
							bsdfSample.pdf,
							input.hdri:EvalPDF(bsdfSample.scattered)
						)
					else
						misWeight = 1
					end

					color = color
						+ throughput
							* input.hdri:GetPixel(bsdfSample.scattered)
							* misWeight
					break
				end

				-- Absorption for refractive objects
				if
					settings.FEATURES.ABSORPTION
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

	return color
end

return {
	pathtrace = pathtrace,
	getMaterial = getMaterial,
}
