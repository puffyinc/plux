-- Allows the user to adjust certain Plux settings

properties.Add("plux.doublesided", {
	MenuLabel = "Emit Light On All Sides",
	Order = 3000,
	MenuIcon = "icon16/weather_sun.png",
	PrependSpacer = true,

	Filter = function(self, ent)
		if not IsValid(ent) then
			return false
		end

		return ent:GetMaterial() == "models/shiny" and not ent.plux_doublesided
	end,

	Action = function(self, ent)
		ent.plux_doublesided = true
	end,
})

properties.Add("plux.singlesided", {
	MenuLabel = "Emit Light On Front Side",
	Order = 3000,
	MenuIcon = "icon16/weather_sun.png",
	PrependSpacer = true,

	Filter = function(self, ent)
		if not IsValid(ent) then
			return false
		end

		return ent:GetMaterial() == "models/shiny"
			and ent.plux_doublesided == true
	end,

	Action = function(self, ent)
		ent.plux_doublesided = false
	end,
})
