local upcrafting = require("prototypes.upcrafting")

for name, category in pairs(data.raw['recipe-category']) do
	upcrafting.generate_crafting_category_variants(category)
end
for name, recipe in pairs(data.raw['recipe']) do
	upcrafting.generate_recipe_variants(recipe)
end
for name, entity in pairs(data.raw['assembling-machine']) do
	upcrafting.generate_crafting_machine_variants(entity)
end
for name, entity in pairs(data.raw['furnace']) do
	upcrafting.generate_crafting_machine_variants(entity)
end
for name, tech in pairs(data.raw['technology']) do
	upcrafting.technology_add_recipes(tech)
end

-- Apply Quality Curve
for name, quality in pairs(data.raw['quality']) do
	local depth = 0.0
	if quality.next == "epic" then
		while quality.next do
			depth = depth + 1.0
			quality.next_probability = quality.next_probability * math.pow(settings.startup["quality-epic-legendary-quality-curve"].value, depth)
			quality = data.raw['quality'][quality.next]
		end
		break
	end
end

for name, quality in pairs(data.raw['quality']) do
	upcrafting.quality_adjust_upgrade_chance(quality)
end


for name, mod in pairs(data.raw['module']) do
	upcrafting.module_adjust_upgrade_chance(mod)
end