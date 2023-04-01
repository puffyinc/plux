---@alias lights.Sample {valid: boolean, weight: GVector, pdf: number, distance: number, dir: GVector, toLight: GVector}

--- Base light class which all lights derive from
---@class lights.Light
---@field sample fun(self: lights.Light, sampler: vistrace.Sampler, shadingPoint: GVector, selectionPDF: number): lights.Sample
---@field intensity GVector
---@field surfaceArea number
---@field transform GVMatrix

--- Area light, also known as a rect light.
---@class lights.AreaLight: lights.Light
---@field entity GEntity
---@field width number
---@field height number

--- Helper class to manage and create a collection of lights and also to sample from it.
---@class lights.LightCollection
---@field lights lights.Light[]
---@field newAreaLight fun(self: lights.LightCollection, entity: GEntity, intensity: GVector)
---@field sample fun(self: lights.LightCollection, sampler: vistrace.Sampler, shadingPoint: GVector):lights.Sample

--- Helper function to make a class
---@generic T
---@param name `T`
---@return T class
local function class(name)
	local classMeta = {}
	classMeta._name = name
	classMeta.__index = classMeta

	return classMeta
end

local AreaLight = class("lights.AreaLight")

--- Creates a new area light
---@param transform GVMatrix
---@param intensity GVector
---@param width number
---@param height number
---@return lights.AreaLight light
function AreaLight.new(entity, transform, intensity, width, height)
	local light = {
		entity = entity,
		transform = transform,
		width = width,
		height = height,
		intensity = intensity,
		surfaceArea = width * height,
	}

	return setmetatable(light, AreaLight)
end

--- Samples the area light, adapted from Falcor 5.0
--- Source: https://github.com/NVIDIAGameWorks/Falcor/blob/8c85b5a0abacc918e3c0ce2d04fa16b6ee488d3d/Source/Falcor/Rendering/Lights/LightHelpers.slang
---@param sampler vistrace.Sampler
---@param shadingPoint GVector
---@param selectionPDF number
---@return lights.Sample sample
function AreaLight:sample(sampler, shadingPoint, selectionPDF)
	local u, v = sampler:GetFloat2D()
	---@type GVector
	local worldPos = self.transform
		* Vector(0, (u * 2 - 1) * self.width, (v * 2 - 1) * self.height)

	---@type GVector
	local toLight = worldPos - shadingPoint
	local distSqr = math.max(toLight:Dot(toLight), 1e-9)

	---@type lights.Sample
	local sample = {}
	sample.valid = true
	sample.toLight = toLight
	sample.distance = math.sqrt(distSqr)
	sample.dir = toLight / sample.distance

	local normal = self.transform:GetUp()
	---@diagnostic disable-next-line: param-type-mismatch
	local cosTheta = normal:Dot(-sample.dir)

	if
		cosTheta <= 0
		and IsValid(self.entity)
		---@diagnostic disable-next-line: undefined-field
		and not self.entity.plux_doublesided
	then
		return { valid = false }
	end

	sample.pdf = distSqr / (cosTheta * self.surfaceArea)
	-- TODO: Is this correct? I'd assume so.
	sample.pdf = sample.pdf * selectionPDF
	sample.weight = self.intensity / sample.pdf

	return sample
end

local LightCollection = class("lights.LightCollection")

--- Creates a light collection
---@return lights.LightCollection collection
function LightCollection.new()
	return setmetatable({
		lights = {},
	}, LightCollection)
end

--- Samples from the light collection
---@param sampler vistrace.Sampler
---@param shadingPoint GVector
---@return lights.Sample sample
function LightCollection:sample(sampler, shadingPoint)
	if #self.lights == 0 then
		return { valid = false }
	end

	local selectionPDF = 1 / #self.lights
	local light = self.lights[math.random(1, #self.lights)]

	local lightSample = light:sample(sampler, shadingPoint, selectionPDF)
	if not lightSample.valid then
		return { valid = false }
	end

	return lightSample
end

--- Creates a new area light from the entity's dimensions
---@param entity GEntity
---@param intensity GVector RGB triple with each channel being the intensity of that.. channel.
function LightCollection:newAreaLight(entity, intensity)
	local obbSize = entity:OBBMaxs() - entity:OBBMins()
	---@type number
	local width = obbSize[2]
	---@type number
	local height = obbSize[3]

	self.lights[#self.lights + 1] = AreaLight.new(
		entity,
		entity:GetWorldTransformMatrix(),
		intensity,
		width,
		height
	)
end

return {
	LIGHT_MATERIAL = "models/shiny",
	LightCollection = LightCollection,
}
