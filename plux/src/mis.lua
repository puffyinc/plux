--- Power heuristic with beta = 2 and only for two sampling techniques.
---@param pdf1 number
---@param pdf2 number
---@return number weight
local function powerHeuristic2(pdf1, pdf2)
	local pdf1Raised = pdf1 * pdf1
	local pdf2Raised = pdf2 * pdf2

	return pdf1Raised / (pdf1Raised + pdf2Raised)
end

return {
	powerHeuristic2 = powerHeuristic2,
}
