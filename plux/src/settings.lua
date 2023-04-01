-- This file contains settings meant to be manually edited. Not a good idea for source control and UX.
-- TODO: Replace this with a better alternative

-- Reverse the ratio, eg. 16:9 = 9 / 16, 4:3 = 3 / 4
local ASPECT_RATIO = 9 / 16
local WIDTH = 1366

return {
	WIDTH = WIDTH,
	HEIGHT = math.floor(WIDTH * ASPECT_RATIO),
	FOCAL_LENGTH = 45,
	SENSOR_HEIGHT = 35,
	MAX_BOUNCES = 8,
	SAMPLES = 4,
	HDRI = "forgotten_miniland_4k",
	DEBUG_GBUFFER = true,

	FEATURES = {
		MIS = true,
		CSFR_PSR = true,
		RUSSIAN_ROULETTE = true,
		ABSORPTION = true,
		RAIN = false,
	},
}
