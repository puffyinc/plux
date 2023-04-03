-- This file contains settings meant to be manually edited. Not a good idea for source control and UX.
-- TODO: Replace this with a better alternative

-- Reverse the ratio, eg. 16:9 = 9 / 16, 4:3 = 3 / 4
local ASPECT_RATIO = 9 / 16
local WIDTH = 1920

return {
	WIDTH = WIDTH,
	HEIGHT = math.floor(WIDTH * ASPECT_RATIO),
	FOCAL_LENGTH = 60,
	SENSOR_HEIGHT = 35,
	MAX_BOUNCES = 8,
	SAMPLES = 16,
	HDRI = "forgotten_miniland_4k",
	DEBUG_GBUFFER = true,
	WATER_ABSORPTION = Vector(0.01, 0, 0.005),

	FEATURES = {
		MIS = true,
		CSFR_PSR = true,
		RUSSIAN_ROULETTE = true,
		ABSORPTION = true,
		RAIN = false,
	},
}
