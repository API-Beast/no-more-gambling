local prevent_mining_entity = nil

local function get_base(name)
	return name:gsub("%-upcrafting%-%d+", "")
end

local function count_modules(entity)
	local mods = entity.get_module_inventory()
	local count = 0
	for i = 1, #mods do
		local mod = mods[i]
		if mod.valid_for_read == true and mod.valid == true then
			if mod.name == "quality-module" or mod.name == "quality-module-2" or  mod.name == "quality-module-3" then
				count = count + 1
			end
		end
	end
	return math.min(count, settings.startup["quality-module-cap"].value)
end

local function adjust_recipe(recipe_name, crafter_name)
	if recipe_name == nil or crafter_name == nil then
		return recipe_name
	end
	local match = string.match(crafter_name, "%-upcrafting%-(%d+)")
    local num_quality_mods = match and tonumber(match) or 0
	local base_recipe = get_base(recipe_name)
	local target_recipe = base_recipe.."-upcrafting-"..num_quality_mods
	if num_quality_mods == 0 then
		target_recipe = base_recipe
	end
	return target_recipe
end

local function set_recipe(entity, recipe, quality)
	if recipe == nil then
		return
	end
	
	local num_quality_mods = count_modules(entity)
	local base_recipe = get_base(recipe.name)
	local target_recipe = base_recipe.."-upcrafting-"..num_quality_mods
	if num_quality_mods == 0 then
		target_recipe = base_recipe
	end
	entity.set_recipe(target_recipe, quality)
end


local function patch_undo_action(action, position, old_name, new_name)
	if action.target ~= nil then
		if action.target.position.x == position.x and action.target.position.y == position.y and action.target.name == old_name then
			log("-----------")
			log(serpent.block(action))
			action.target.name = new_name
			if action.target.recipe then
				action.target.recipe = adjust_recipe(action.target.recipe, new_name)
			end
			log("---------->")
			log(serpent.block(action))
			log("-----------")
			return action
		else
			return nil
		end
	end
end

local function patch_undo_history(position, old_name, new_name)
	for i = 1, #game.connected_players do
		local player = game.connected_players[i]
		local undo_stack = player.undo_redo_stack
		if undo_stack then
			local undo_count = undo_stack.get_undo_item_count()
			local redo_count = undo_stack.get_redo_item_count()
			local l = 1
			local to_delete = {}
			-- Remove the last "Player Removes Entity" action and "Player Places Entity" action
			-- Then patch the remaining actions to reference the new entity
			for j = 1, undo_count do
				local actions = undo_stack.get_undo_item(j)
				for k, action in ipairs(actions) do
					if patch_undo_action(action, position, old_name, new_name) then
						if l <= 2 then
							to_delete[l] = {j, k}
							l = l + 1
							log("--- To be deleted ---")
						end
					end
				end
			end
			for j = 1, redo_count do
				local actions = undo_stack.get_redo_item(j)
				for _, action in ipairs(actions) do
					patch_undo_action(action, old_entity, new_name)
				end
			end
			for _, index in ipairs(to_delete) do
				undo_stack.remove_undo_action(index[1], index[2])
			end
		end
	end
end

local function reinsert_preserved_undo_history(preserved_actions)
	for i, action in ipairs(preserved_actions) do
		local undo_item = nil
		local undo_stack = action.stack
		if action.type == "undo" then
			undo_item = undo_stack.get_undo_item(action.item)
		else
			undo_item = undo_stack.get_redo_item(action.item)
		end
		table.insert(undo_item, action.data)
	end
end

local function update_entity(entity, recipe, recipe_quality, actor)
	local mods = entity.get_module_inventory()
	if mods == nil then
		return false
	end

	-- Don't mess with random, modded, possibly scripted entities
	if entity.has_flag("not-selectable-in-game") then
		return false
	end

	local num_quality_mods = count_modules(entity)
	local base_name = get_base(entity.name)
	local target_name = base_name.."-upcrafting-"..num_quality_mods
	if num_quality_mods == 0 then
		target_name = base_name
	end

	if entity.name == target_name then
		return false
	end
	log("Patching "..entity.name.." to "..target_name)

	local inventories = {
		entity.get_inventory(defines.inventory.assembling_machine_input),
		entity.get_inventory(defines.inventory.assembling_machine_output),
		-- entity.get_inventory(defines.inventory.assembling_machine_modules), -- Modules get transfered automatically due to "fast_replace"
		entity.get_inventory(defines.inventory.assembling_machine_dump),
		-- entity.get_inventory(defines.inventory.fuel),
		-- entity.get_inventory(defines.inventory.burnt_result),
	}
	local item_stacks = {}
	for _, inventory in ipairs(inventories) do
		if inventory then
			for i = 1, #inventory do
				local item_stack = inventory[i]
				if item_stack and item_stack.valid_for_read then
					table.insert(item_stacks, {
						name = item_stack.name,
						count = item_stack.count,
						quality = item_stack.quality,
						health = item_stack.health,
						durability = (item_stack.is_tool and item_stack.durability) or nil,
						ammo = (item_stack.is_ammo and item_stack.ammo) or nil,
						tags = (item_stack.is_item_with_tags and item_stack.tags) or nil,
						custom_description = (item_stack.is_item_with_tags and item_stack.custom_description) or nil,
						spoil_percent = item_stack.spoil_percent
					})
				end
			end
			inventory.clear()
		end
	end
	
	local player = entity.last_user
	local has_open = (player and player.opened == entity)
	local old_name = entity.name
	local info = {
		name = target_name,
		position = entity.position,
		quality = entity.quality,	
		direction = entity.direction,
		fast_replace = true,
		force = entity.force,
		preserve_ghosts_and_corpses = true,
		create_build_effect_smoke = false,
		spawn_decorations = false,
		move_stuck_players = false,
		spill = false,
		player = player
		-- Else it will duplicate the mineable entity
	}
	local extra = {
		health = entity.health,
		direction = entity.direction,
		mirroring = entity.mirroring,
		orientation = entity.orientation,
		products_finished = entity.products_finished,
		last_user = entity.last_user
	}
	if entity.type == 'assembling-machine' then
		info.recipe = adjust_recipe(recipe_name, target_name)
	end


	local item_request_proxies = entity.surface.find_entities_filtered{area=entity.bounding_box, name='item-request-proxy', force=entity.force}
	local to_request = {}
	for _, request in ipairs(item_request_proxies) do
		if request.proxy_target == entity then
			for _, request in ipairs(request.item_requests) do
				table.insert(to_request, request)
			end
		end
	end

	-- Catch the next on_mined event
	prevent_mining_entity = entity
	local new_entity = entity.surface.create_entity(info)
	patch_undo_history(info.position, old_name, target_name)
	if new_entity.type == 'assembling-machine' then
		set_recipe(new_entity, recipe, recipe_quality)
	end
	for prop, value in pairs(extra) do
		new_entity[prop] = value
	end
	if has_open then
		player.opened = new_entity
	end

	-- Give back overflowing items.
	local dump = new_entity.get_inventory(defines.inventory.assembling_machine_dump) or new_entity.get_inventory(defines.inventory.burnt_result) or new_entity.get_inventory(defines.inventory.assembling_machine_output)
	if actor then
		dump = actor
	end
	for i = 1, #item_stacks do
		if new_entity.can_insert(item_stacks[i]) then
			new_entity.insert(item_stacks[i])
		else
			dump.insert(item_stacks[i])
		end
	end

	-- Recover the item requests.
	local stack = 0
	for _, request in ipairs(to_request) do
		for i = 1, request.count do
			local new_request = new_entity.surface.create_entity({
				name = "item-request-proxy",
				target = new_entity,
				modules = {{id = {name = request.name, quality = request.quality}, items = {in_inventory = {{inventory = defines.inventory.assembling_machine_modules, stack = stack, count = 1}}, grid_count = nil}}},
				fast_replace = true,
				position = new_entity.position,
				force = new_entity.force
			})
			stack = stack + 1
		end
	end
	return true
end

local function on_built(event)
	if event.entity == nil then
		return
	end
	if event.entity.type == "crafting-machine" or event.entity.type == "assembling-machine" or event.entity.type == "furnace" then
		local recipe, quality = event.entity.get_recipe()
		local actor = (event.robot or event.platform or (event.player_index and game.get_player(event.player_index).character) or (event.player_index and game.get_player(event.player_index)))
		update_entity(event.entity, recipe, quality)
	end
end

local function on_mined(event)
	if event.entity and event.buffer and event.entity == prevent_mining_entity then
		local minables = event.entity.prototype and event.entity.prototype.mineable_properties and event.entity.prototype.mineable_properties.products
		for _, minable in ipairs(minables) do
			if minable.type == "item" then
				event.buffer.remove({name = minable.name, count = minable.amount or minable.amount_max, quality = minable.quality or nil})
			end
		end
		prevent_mining_entity = nil
	end
end

local function rescan()
    for _, surface in pairs(game.surfaces) do
        for _, entity in pairs(surface.find_entities_filtered{type={"furnace", "assembling-machine"}}) do
			local recipe, quality = entity.get_recipe()
			update_entity(entity, recipe, quality)
        end
    end
end

script.on_init(rescan)
script.on_configuration_changed(rescan)
script.on_nth_tick(30, rescan)

local filter = {filter = "crafting-machine"}
script.on_event(defines.events.on_built_entity, on_built, {filter})
script.on_event(defines.events.on_robot_built_entity, on_built, {filter})
script.on_event(defines.events.on_space_platform_built_entity, on_built, {filter})
script.on_event(defines.events.on_player_fast_transferred, on_built)
script.on_event(defines.events.on_player_flipped_entity, on_built)
script.on_event(defines.events.on_entity_settings_pasted, on_built)

script.on_event(defines.events.on_player_mined_entity, on_mined, {filter})
script.on_event(defines.events.on_space_platform_mined_entity, on_mined, {filter})