---@module 'settings'
local settings = include("../settings.lua")

---@module 'experimental/psr'
local psr = include("psr.lua")

---@module 'pathtracer'
local pathtracer = include("../pathtracer.lua")

---@module 'colors'
local colors = include("../colors.lua")

---@alias csfr.Input {x: number, y: number, result: any, sampler: vistrace.Sampler, bvh: any, albedo: vistrace.RenderTarget, normal: vistrace.RenderTarget, csfrBuffer: vistrace.RenderTarget, onMiss: fun(dir:GVector):GVector}

--- Checks if a pixel has been rendered with CSFR
---@param x number
---@param y number
---@param csfrBuffer any
---@return boolean
local function isCsfrRendered(x, y, csfrBuffer)
	local csfrRendered = csfrBuffer:GetPixel(x, y)[1] == 1
	return csfrRendered
end

--- Applies a cross spatial filter to the G-buffer for CSFR-rendered objects. This merges two rays into one to save properly in the G-buffer. Has noticeable artifacts at low-res.
---@param buffer any
---@param x number
---@param y number
---@param csfrBuffer any
local function crossFilter(buffer, x, y, csfrBuffer)
	local color = Vector(0, 0, 0)
	local neighbors = 0

	local function addNeighbor(x, y)
		if
			(x >= 0 and x < settings.WIDTH)
			and (y >= 0 and y < settings.HEIGHT)
			and isCsfrRendered(x, y, csfrBuffer)
		then
			color = color + buffer:GetPixel(x, y)
			neighbors = neighbors + 1
		end
	end

	addNeighbor(x, y)
	addNeighbor(x, y + 1) -- Top
	addNeighbor(x + 1, y) -- Left
	addNeighbor(x - 1, y) -- Right
	addNeighbor(x, y - 1) -- Bottom

	buffer:SetPixel(x, y, color / math.max(1, neighbors))
end

--- Apply CSFR and PSR with the given input.
---@param input csfr.Input
---@return boolean anyCsfrApplied True if any CSFR was applied and a cross filter is needed.
local function applyCSFRPSR(input)
	local anyCsfrRendered = false

	if psr.isQualifiedSurface(pathtracer.getMaterial(input.result)) then
		-- Creates the checkerboard pattern we filter out.
		local reflection = (input.x + input.y) % 2 == 0

		-- To check if a surface requires CSFR or not.
		if psr.isMirror(pathtracer.getMaterial(input.result)) then
			reflection = true
		else
			-- Diffuse specular and glass are CSFR-enabled because they split into two rays.
			input.csfrBuffer:SetPixel(input.x, input.y, Vector(1, 0, 0))
			anyCsfrRendered = true
		end

		local surface = psr.findSecondarySurface(
			input.result,
			reflection,
			input,
			input.sampler,
			input.bvh
		)

		if surface.valid then
			if surface.isSky then
				-- Update G-buffer but only replace the albedo with the miss program

				input.albedo:SetPixel(
					input.x,
					input.y,
					colors.saturate(input.onMiss(surface.direction))
				)

				input.normal:SetPixel(input.x, input.y, Vector(0, 0, 0))
			else
				input.albedo:SetPixel(input.x, input.y, surface.albedo)
				input.normal:SetPixel(input.x, input.y, surface.normal)
			end
		end
	end

	return anyCsfrRendered
end

return {
	applyCSFRPSR = applyCSFRPSR,
	isCsfrRendered = isCsfrRendered,
	crossFilter = crossFilter,
}
