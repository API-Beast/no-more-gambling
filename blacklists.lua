local category_blacklist = {}
local machine_blacklist = {}
local mods = (script and script.active_mods) or mods
if mods["promethium-quality"] then
	category_blacklist["refining"] = true
	machine_blacklist["refinery"] = true
end
if mods["maraxsis"] then
	machine_blacklist["electric-mining-drill-sand-extractor"] = true
	machine_blacklist["big-mining-drill-sand-extractor"] = true
end
return {category_blacklist, machine_blacklist}