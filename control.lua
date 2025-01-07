local prevent_mining_entity = nil

_, _, major, minor, patch = string.find(script.active_mods["base"], "(%d+).(%d+).(%d+)")
local history_patching_enabled = major == 2 and minor == 0 and patch < 20

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
	local base_name = get_base(crafter_name)
	local num_base_quality_mods = (base_name == "fabricator" and 1 or 0)
    local num_quality_mods = match and tonumber(match) or num_base_quality_mods
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
	local target_recipe = adjust_recipe(recipe and (recipe.name or recipe), entity.name)
	entity.set_recipe(target_recipe, quality)
end

local function patch_undo_action(action, position, base_name, new_name)
	if action.target ~= nil and action.target.position ~= nil then
		if action.target.position.x == position.x and action.target.position.y == position.y and get_base(action.target.name) == base_name then
			action.target.name = new_name
			if action.target.recipe then
				action.target.recipe = adjust_recipe(action.target.recipe, new_name)
			end
			return action
		else
			return nil
		end
	end
end

local function log_undo_stack(prefix)
	for i = 1, #game.connected_players do
		local player = game.connected_players[i]
		local undo_stack = player.undo_redo_stack
		log("--- "..prefix.."Undo for Player "..i.." ---")
		for j = 1, undo_stack.get_undo_item_count() do
			log(""..prefix.."Undo Item")
			for k, action in ipairs(undo_stack.get_undo_item(j)) do
				log(""..prefix.."Undo: "..serpent.dump(action))
			end
		end
		for j = 1, undo_stack.get_redo_item_count() do
			log(""..prefix.."Redo Item")
			for k, action in ipairs(undo_stack.get_redo_item(j)) do
				log(""..prefix.."Redo: "..serpent.dump(action))
			end
		end
	end
end

local function patch_history(position, base_name, new_name)
	local result = {}
	for i = 1, #game.connected_players do
		local player = game.connected_players[i]
		local undo_stack = player.undo_redo_stack
		result[i] = {undo = {}, redo = {}}
		if undo_stack then
			for j = 1, undo_stack.get_undo_item_count() do
				result[i].undo[j] = undo_stack.get_undo_item(j)
				for k, action in ipairs(result[i].undo[j]) do
					patch_undo_action(action, position, base_name, new_name)
				end
			end
			for j = 1, undo_stack.get_redo_item_count() do
				result[i].redo[j] = undo_stack.get_redo_item(j)
				for k, action in ipairs(result[i].redo[j]) do
					patch_undo_action(action, position, old_entity, new_name)
				end
			end
		end
	end
	return result
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

	local base_name = get_base(entity.name)
	local num_base_quality_mods = (base_name == "fabricator" and 1 or 0)
	local num_quality_mods = num_base_quality_mods + count_modules(entity)
	local target_name = base_name.."-upcrafting-"..num_quality_mods
	if num_quality_mods == num_base_quality_mods then
		target_name = base_name
	end

	if entity.name == target_name then
		return false
	end

	local item_stacks = {}
	for key, inventory_id in pairs(defines.inventory) do
		local inventory = entity.get_inventory(inventory_id)
		if inventory then
			for i = 1, #inventory do
				local item_stack = inventory[i]
				if item_stack and item_stack.valid_for_read then
					item_stacks[inventory_id] = item_stacks[inventory_id] or {}
					item_stacks[inventory_id][i] = {
						name = item_stack.name,
						count = item_stack.count,
						quality = item_stack.quality,
						health = item_stack.health,
						durability = (item_stack.is_tool and item_stack.durability) or nil,
						ammo = (item_stack.is_ammo and item_stack.ammo) or nil,
						tags = (item_stack.is_item_with_tags and item_stack.tags) or nil,
						custom_description = (item_stack.is_item_with_tags and item_stack.custom_description) or nil,
						spoil_percent = item_stack.spoil_percent
					}
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

	-- Remember what item requests were enabled for this entity.
	local item_request_proxies = entity.surface.find_entities_filtered{area=entity.bounding_box, name='item-request-proxy', force=entity.force}
	local requests = {}
	for _, request in ipairs(item_request_proxies) do
		if request.proxy_target == entity then
			table.insert(requests, {position = request.position, insert_plan = request.insert_plan, removal_plan = request.removal_plan})
		end
	end
	
	-- Flush all fluidboxes so the liquids don't get lost.
	for i=1,#entity.fluidbox do
		entity.fluidbox.flush(i)
	end
 
	-- Catch the next on_mined event
	prevent_mining_entity = entity
	
	-- History patching only works in old versions of Factorio (at least 2.0.7 confirmed)
	local new_entity = nil
	if history_patching_enabled then
		log_undo_stack("Before ")
		patch_history(info.position, base_name, target_name)

		info.fast_replace = true
		info.player = player
		new_entity = entity.surface.create_entity(info)

		local undo_stack = player.undo_redo_stack
		undo_stack.remove_undo_action(1, 2)
		undo_stack.remove_undo_action(1, 1)
		log_undo_stack("After ")
	else
		info.fast_replace = false
		info.player = player
		new_entity = entity.surface.create_entity(info)
		entity.destroy()
	end


	if new_entity.type == 'assembling-machine' then
		set_recipe(new_entity, recipe, recipe_quality)
	end
	for prop, value in pairs(extra) do
		new_entity[prop] = value
	end
	if has_open then
		player.opened = new_entity
	end

	-- Give back items.
	local dump = new_entity.get_inventory(defines.inventory.assembling_machine_dump) or new_entity.get_inventory(defines.inventory.burnt_result) or new_entity.get_inventory(defines.inventory.assembling_machine_output)
	if actor then
		dump = actor
	end
	for inventory_id, items in pairs(item_stacks) do
		local inventory = new_entity.get_inventory(inventory_id)
		for i, stack in pairs(items) do
			if inventory and inventory[i] and inventory[i].can_set_stack(stack) then
				inventory[i].transfer_stack(stack)
			elseif inventory and inventory.can_insert(items[i]) then
				inventory.insert(items[i])
			elseif new_entity.can_insert(items[i]) then
				new_entity.insert(items[i])
			else
				dump.insert(items[i])
			end
		end
	end

	-- Recover the item requests.
	for _, request in ipairs(requests) do
		new_entity.surface.create_entity({
			name = "item-request-proxy",
			target = new_entity,
			modules = request.insert_plan,
			removal_plan = request.removal_plan,
			position = request.position,
			force = new_entity.force
		})
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

local function on_entity_settings_pasted(event)
	if event.source.type == "crafting-machine" or event.source.type == "assembling-machine" then
		if event.destination.type == "crafting-machine" or event.destination.type == "assembling-machine" then
			local recipe, quality = event.source.get_recipe()
			local actor = (event.player_index and game.get_player(event.player_index).character) or (event.player_index and game.get_player(event.player_index))
			set_recipe(event.destination, recipe, quality, actor)
		end
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
script.on_event(defines.events.on_entity_settings_pasted, on_entity_settings_pasted)

script.on_event(defines.events.on_player_mined_entity, on_mined, {filter})
script.on_event(defines.events.on_space_platform_mined_entity, on_mined, {filter})