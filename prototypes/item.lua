local item_sounds = require("__base__.prototypes.item_sounds")

local cost_increase = settings.startup['quality-cost-increase'].value * 100.0
local time_increase = settings.startup['quality-crafting-time-increase'].value * 100.0
local description = { "", {"item-description.quality-module"}, "\n", {"description.quality-cost-increase", tostring(cost_increase)} }
if time_increase > 0.0 then
	description = { "", {"item-description.quality-module"}, "\n", {"description.quality-cost-increase", tostring(cost_increase)}, "\n", {"description.quality-crafting-time-increase", tostring(time_increase)} }
end


data:extend
({
  {
    type = "module",
    name = "quality-module",
    localised_description = description,
    icon = "__quality__/graphics/icons/quality-module.png",
    subgroup = "module",
    color_hint = { text = "Q" },
    category = "quality",
    tier = 1,
    order = "d[quality]-a[quality-module-1]",
    inventory_move_sound = item_sounds.module_inventory_move,
    pick_sound = item_sounds.module_inventory_pickup,
    drop_sound = item_sounds.module_inventory_move,
    stack_size = 50,
    weight = 20 * kg,
    effect = { quality = 2.50 }
  },
  {
    type = "module",
    name = "quality-module-2",
	localised_description = description,
    icon = "__quality__/graphics/icons/quality-module-2.png",
    subgroup = "module",
    color_hint = { text = "Q" },
    category = "quality",
    tier = 2,
    order = "d[quality]-b[quality-module-2]",
    inventory_move_sound = item_sounds.module_inventory_move,
    pick_sound = item_sounds.module_inventory_pickup,
    drop_sound = item_sounds.module_inventory_move,
    stack_size = 50,
    weight = 20 * kg,
    effect = { quality = 3.75 }
  },
  {
    type = "module",
    name = "quality-module-3",
	localised_description = description,
    icon = "__quality__/graphics/icons/quality-module-3.png",
    subgroup = "module",
    color_hint = { text = "Q" },
    category = "quality",
    tier = 3,
    order = "d[quality]-c[quality-module-3]",
    inventory_move_sound = item_sounds.module_inventory_move,
    pick_sound = item_sounds.module_inventory_pickup,
    drop_sound = item_sounds.module_inventory_move,
    stack_size = 50,
    weight = 20 * kg,
    effect = { quality = 5.00 }
  }
})