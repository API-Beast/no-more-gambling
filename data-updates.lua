local ore_washing = require("prototypes.ore-washing")

for name, item in pairs(data.raw['item']) do
	if name:find("-ore") or name == "scrap" then
		ore_washing.generate_washing_recipe(item)
	end
end
for name, drill in pairs(data.raw['mining-drill']) do
	ore_washing.disable_mining_drill_quality(drill)
end