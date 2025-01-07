local category_blacklist = {}
local machine_blacklist = {}
local mods = (script and script.active_mods) or mods
if mods["promethium-quality"] then
	category_blacklist["refining"] = true
	machine_blacklist["refinery"] = true
end
return {category_blacklist, machine_blacklist}