local function generate_upcrafting_recipe(recipe, n)
	local solid_product_found = false
	local main_product = nil
	for k,v in pairs(recipe.results) do
	  if v.type == "item" then
	  	solid_product_found = true
		main_product = v.name
		break
	  end
	end

	local cost_factor = 1.0 + n * settings.startup["quality-cost-increase"].value
	local energy_factor = 1.0 + n * settings.startup["quality-crafting-time-increase"].value
	local cpy = table.deepcopy(recipe)
	cpy.name = recipe.name.."-upcrafting-"..n
	if recipe.localised_name == nil then
		cpy.localised_name = {"?", {"recipe-name." .. recipe.name}, {"item-name." .. (recipe.main_product or recipe.name)}, {"entity-name." .. (recipe.main_product or main_product or recipe.name)}}
	end
	cpy.category = (recipe.category or "crafting").."-upcrafting-"..n
	cpy.allow_decomposition = false
	cpy.hide_from_player_crafting = true
	cpy.hidden_in_factoriopedia = true

	-- Quality does nothing for pure fluid recipes.
	local disable_recipe = false
	if solid_product_found == true then
		cpy.maximum_productivity = (recipe.maximum_productivity or 3.0) * cost_factor
		-- cpy.emissions_multiplier = (recipe.emissions_multiplier or 1.0) * cost_factor / energy_factor
		cpy.energy_required = (recipe.energy_required or 0.5) * energy_factor
		if cpy.ingredients and #cpy.ingredients > 0 then
			for i, item in ipairs(cpy.ingredients) do
				cpy.ingredients[i].amount = item.amount * cost_factor
				if cpy.ingredients[i].amount > 65535 then
					disable_recipe = true
				end
			end
		else
			cpy.energy_required = (recipe.energy_required or 0.5) * (energy_factor * cost_factor)
		end
	end

	if disable_recipe then
		cpy.ingredients = table.deepcopy(recipe.ingredients or {})
		cpy.localised_description = {"quality-crafting-impossible", tostring(n)}
		cpy.allow_quality = false
	end
  
	data:extend(
		{cpy}
	)
end

local function generate_recipe_variants(recipe)
	if string.find(recipe.name, "upcraft") then
		return
	end

	if recipe.results == nil then
		log("Skipped "..recipe.name)
		return
	end

	local max = settings.startup["quality-module-cap"].value
	for n=1,max do
		generate_upcrafting_recipe(recipe, n)
	end
end

local function contains(arr, item)
    for i = 1, #arr do
        if arr[i] == item then
            return true
        end
    end
    return false
end

local function generate_crafting_machine_variants(entity)
	if string.find(entity.name, "upcraft") then
		return
	end

	-- Make sure to scale quality so that other mods keep working (not used in vanilla)
	if entity and entity.effect_receiver and entity.effect_receiver.base_effect and entity.effect_receiver.base_effect.quality then
		entity.effect_receiver.base_effect.quality = entity.effect_receiver.base_effect.quality * (0.1 / settings.startup["quality-skip-chance"].value)
	end

	-- Mod Compatibility: Some mods use crafting machines for weird things. If it can't use modules, don't create variants.
	if entity.effect_receiver and entity.uses_module_effects ~= nil and entity.uses_module_effects == false then return end
	if entity.allowed_effects and contains(entity.allowed_effects, "quality") == false then return end
	if entity.allowed_module_categories and contains(entity.allowed_module_categories, "quality") == false then return end
	if entity.module_slots == nil or entity.module_slots == 0 then return end

	local max = settings.startup["quality-module-cap"].value
	for n=1,max do
		local cpy = table.deepcopy(entity)
		cpy.name = entity.name.."-upcrafting-"..n
		for i, category in ipairs(entity.crafting_categories) do
			cpy.crafting_categories[i] = category.."-upcrafting-"..n
		end
		if entity.localised_name == nil then
			cpy.localised_name = {"entity-name." .. entity.name}
		end

		local cost_increase = 100.0 + settings.startup['quality-cost-increase'].value * 100.0 * n
		local time_increase = 100.0 + settings.startup['quality-crafting-time-increase'].value * 100.0 * n
		cpy.localised_description = { "", {"description.quality-cost-increase", tostring(cost_increase)} }
		if time_increase > 101.0 then
			cpy.localised_description = { "", {"description.quality-cost-increase", tostring(cost_increase)}, "\n", {"description.quality-crafting-time-increase", tostring(time_increase)} }
		end

		cpy.localised_description = description

		if entity.fixed_recipe ~= nil then
			cpy.fixed_recipe = entity.fixed_recipe.."-upcrafting-"..n
		end

		local mining_result = entity.mineable and (entity.mineable.result or entity.mineable.results[0].name)
		
		if cpy.placeable_by and cpy.placeable_by[1] == nil then
			cpy.placeable_by = {{item = cpy.placeable_by, count = 1}}
		end
		if mining_result ~= nil then
			cpy.placeable_by = cpy.placeable_by or {}
			table.insert(cpy.placeable_by, {item = mining_result, count = 1})
		end

		cpy.deconstruction_alternative = entity.name
		cpy.hidden = true
		data:extend(
			{cpy}
		)
	end
end

local function generate_crafting_category_variants(category)
	if string.find(category.name, "upcraft") then
		return
	end

	local max = settings.startup["quality-module-cap"].value
	for n=1,max do
		local cpy = table.deepcopy(category)
		cpy.name = category.name.."-upcrafting-"..n
		if category.localised_name == nil then
			cpy.localised_name = {"recipe-category." .. category.name}
		end
		cpy.hidden = true
		data:extend(
			{cpy}
		)
	end
end

local function technology_add_recipes(technology)
	if technology.effects == nil then
		return
	end

	local old_effects = table.deepcopy(technology.effects)
	local max = settings.startup["quality-module-cap"].value
	technology.effects = {}
	for i, effect in ipairs(old_effects) do
		table.insert(technology.effects, effect)
		if effect.type == "unlock-recipe" then
			local base_recipe = effect.recipe
			for n=1,max do
				local name = base_recipe.."-upcrafting-"..n
				if data.raw['recipe'][name] then
					table.insert(technology.effects, {type = "unlock-recipe", recipe = name, hidden = true})
				end
			end
		end
	end
end

local function quality_adjust_upgrade_chance(quality)
	if quality.next_probability then
		quality.next_probability = settings.startup["quality-skip-chance"].value * quality.next_probability / 0.1
	end
end

local function module_adjust_upgrade_chance(mod)
	if mod and mod.effect and mod.effect.quality then
		if mod.effect.quality < 0.0 and settings.startup["speed-module-dont-affect-quality"].value then
			mod.effect.quality = 0.0
		else
			mod.effect.quality = mod.effect.quality * (0.1 / settings.startup["quality-skip-chance"].value)
		end
	end
end

local lib = {}
lib.generate_recipe_variants = generate_recipe_variants
lib.generate_crafting_machine_variants = generate_crafting_machine_variants
lib.generate_crafting_category_variants = generate_crafting_category_variants
lib.module_adjust_upgrade_chance = module_adjust_upgrade_chance
lib.quality_adjust_upgrade_chance = quality_adjust_upgrade_chance
lib.technology_add_recipes = technology_add_recipes
return lib
