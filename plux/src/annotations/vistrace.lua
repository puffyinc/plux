---@meta
-- Handmade annotations for my sanity, and thus these are incomplete and not stable.

---@class vistrace.Sampler
---@field GetFloat2D fun(self: vistrace.Sampler): number, number
---@field GetFloat fun(self: vistrace.Sampler): number

---@class vistrace.RenderTarget
---@field GetPixel fun(self: vistrace.RenderTarget, x: number, y: number): GVector
---@field SetPixel fun(self: vistrace.RenderTarget, x: number, y: number, pixel: GVector)
---@field GetWidth fun(self: vistrace.RenderTarget):number
---@field GetHeight fun(self: vistrace.RenderTarget):number
