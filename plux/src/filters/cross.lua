--- Applies a cross spatial filter to the given render target buffer.
---@param buffer vistrace.RenderTarget
---@param x number
---@param y number
local function crossFilter(buffer, x, y)
	local color = Vector(0, 0, 0)
	local neighbors = 0

	local function addNeighbor(x, y)
		if
			(x >= 0 and x < buffer:GetWidth())
			and (y >= 0 and y < buffer:GetHeight())
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

return {
	filter = crossFilter,
}
