-- This file contains settings meant to be manually edited. Not a good idea for source control and UX.
-- TODO: Replace this with a better alternative

-- Reverse the ratio, eg. 16:9 = 9 / 16, 4:3 = 3 / 4
local ASPECT_RATIO = 9 / 16
local WIDTH = 512

return {
	WIDTH = WIDTH,
	HEIGHT = math.floor(WIDTH * ASPECT_RATIO),
	FOCAL_LENGTH = 60,
	SENSOR_HEIGHT = 35,
	MAX_BOUNCES = 8,
	SAMPLES = 4,
	HDRI = "pizzo_pernice_4k",
	HDRI_EXPOSURE = 2,
	DEBUG_GBUFFER = true,
	WATER_ABSORPTION = Vector(0.05, 0, 0.1),

	FEATURES = {
		MIS = true,
		CSFR_PSR = true,
		RUSSIAN_ROULETTE = true,
		ABSORPTION = true,
		RAIN = false,
	},
}
