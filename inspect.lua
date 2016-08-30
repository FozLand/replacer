replacer.image_replacements = {}

-- support for RealTest
if    minetest.get_modpath('trees')
  and minetest.get_modpath('core')
  and minetest.get_modpath('instruments')
  and minetest.get_modpath('anvil')
  and minetest.get_modpath('scribing_table') then
	replacer.image_replacements['group:planks' ] = 'trees:pine_planks'
	replacer.image_replacements['group:plank'  ] = 'trees:pine_plank'
	replacer.image_replacements['group:wood'   ] = 'trees:pine_planks'
	replacer.image_replacements['group:tree'   ] = 'trees:pine_log'
	replacer.image_replacements['group:sapling'] = 'trees:pine_sapling'
	replacer.image_replacements['group:leaves' ] = 'trees:pine_leaves'
	replacer.image_replacements['default:furnace'] = 'oven:oven'
	replacer.image_replacements['default:furnace_active'] = 'oven:oven_active'
end

minetest.register_tool('replacer:inspect', {
	description = 'Node inspection tool',
	groups = {},
	inventory_image = 'replacer_inspect.png',
	wield_image = '',
	wield_scale = {x=1,y=1,z=1},
	liquids_pointable = true, -- it is ok to request information about liquids
	node_placement_prediction = nil,

	on_use = function(itemstack, user, pointed_thing)
		return replacer.inspect(itemstack, user, pointed_thing, nil, true)
	end,

	on_place = function(itemstack, placer, pointed_thing)
		return replacer.inspect(itemstack, placer, pointed_thing, nil, true)
	end,
})

replacer.inspect = function(itemstack, user, pointed_thing, mode, show_recipe)
	if user == nil or pointed_thing == nil then
		return nil
	end

	local name = user:get_player_name()
	local keys = user:get_player_control()
	if keys['sneak'] then
		show_recipe = true
	end

	local pos  = minetest.get_pointed_thing_position(pointed_thing, mode)

	if pointed_thing.type == 'object' then
		local text = 'This is '
		local ref = pointed_thing.ref
		if not ref then
			text = text..'a broken object. It is located'
		elseif ref:is_player() then
			text = text..'your fellow player "'..tostring(ref:get_player_name())..'"'
		else
			local luaob = ref:get_luaentity()
			if luaob then
				text = text..'entity "'..tostring(luaob.name)..'"'
				local sdata = luaob:get_staticdata()
				if sdata then
					sdata = minetest.deserialize(sdata)
					if sdata.itemstring then
						text = text..' ['..tostring(sdata.itemstring)..']'
						if show_recipe  then
							-- the fields part is used here to provide additional information about the entity
							replacer.inspect_show_crafting(name, sdata.itemstring, {pos=pos, luaob=luaob})
						end
					end
					if sdata.age then
						text = text..', dropped '..tostring(math.floor(sdata.age/60))..' minutes ago'
					end
				end
			else
				text = text..'object "'..tostring(ref:get_entity_name())..'"'
			end
		end
		text = text..' at '..minetest.pos_to_string(ref:getpos())
		minetest.chat_send_player(name, text)
		return nil
	elseif pointed_thing.type ~= 'node' then
		minetest.chat_send_player(name,
			'Sorry. This is an unkown something of type "'..
			tostring(pointed_thing.type)..'". No information available.'
		)
		return nil
	end

	local node = minetest.env:get_node_or_nil(pos)

	if node == nil then
		minetest.chat_send_player(name, 'Error: Target node not yet loaded.'..
			' Please wait a moment for the server to catch up.'
		)
		return nil
	end

	local text = ' ['..tostring(node.name)..'] with param2='..
		tostring(node.param2)..' at '..minetest.pos_to_string(pos)..'.'
	if not minetest.registered_nodes[node.name] then
		text = 'This node is an UNKOWN block'..text
	else
		text = 'This is a "'..
		tostring(minetest.registered_nodes[node.name].description
			or ' - no description provided -')..'" block'..text
	end
	local protected_info = ''
	if minetest.is_protected(pos, name) then
		protected_info = 'WARNING: You can\'t dig this node. It is protected.'
	elseif minetest.is_protected(pos, '_THIS_NAME_DOES_NOT_EXIST_') then
		protected_info = 'INFO: You can dig this node, but others can\'t.'
	end
	text = text..' '..protected_info

	if show_recipe then
		-- get light of the node at the current time
		local light = minetest.get_node_light(pos, nil)
		if light==0 then
			light = minetest.get_node_light({x=pos.x,y=pos.y+1,z=pos.z})
		end
		-- the fields part is used here to provide additional information about the node
		replacer.inspect_show_crafting(name, node.name,
			{pos=pos, param2=node.param2, light=light, protected_info=protected_info
		})
	end
	return nil
end

-- some common groups
replacer.group_placeholder = {}
replacer.group_placeholder['group:wood'     ] = 'default:wood'
replacer.group_placeholder['group:tree'     ] = 'default:tree'
replacer.group_placeholder['group:sapling'  ] = 'default:sapling'
replacer.group_placeholder['group:stick'    ] = 'default:stick'
replacer.group_placeholder['group:stone'    ] = 'default:cobble'
-- 'default:stone'  point people to the cheaper cobble
replacer.group_placeholder['group:sand'     ] = 'default:sand'
replacer.group_placeholder['group:leaves'   ] = 'default:leaves'
replacer.group_placeholder['group:wood_slab'] = 'stairs:slab_wood'
replacer.group_placeholder['group:wool'     ] = 'wool:white'


-- handle the standard dye color groups
if minetest.get_modpath('dye') and dye and dye.basecolors then
	for i,color in ipairs(dye.basecolors) do
		local def = minetest.registered_items['dye:'..color]
		if def and def.groups then
			for k,v in pairs(def.groups) do
				if k ~= 'dye' then
					replacer.group_placeholder['group:dye,'..k] = 'dye:'..color
				end
			end
			replacer.group_placeholder['group:flower,color_'..color] = 'dye:'..color
		end
	end
end

replacer.image_button_link = function(stack_string)
	local group = ''
	if replacer.image_replacements[ stack_string ] then
		stack_string = replacer.image_replacements[stack_string]
	end
	if replacer.group_placeholder[ stack_string ] then
		stack_string = replacer.group_placeholder[stack_string]
		group = 'G'
	end
-- TODO: show information about other groups not handled above
	local stack = ItemStack(stack_string)
	local new_node_name = stack_string
	if stack and stack:get_name() then
		new_node_name = stack:get_name()
	end
	return tostring(stack_string)..';'..tostring(new_node_name)..';'..group
end

replacer.add_circular_saw_recipe = function(node_name, recipes)
	if   not node_name
	  or not minetest.get_modpath('moreblocks')
	  or not circular_saw
	  or not circular_saw.names
	  or     node_name == 'moreblocks:circular_saw' then
		return
	end

	local help = node_name:split(':')
	if not help or #help ~= 2 or help[1] == 'stairs' then
		return
	end

	local help2 = help[2]:split('_')
	if not help2 or #help2 < 2 or (help2[1] ~= 'micro'
	                          and  help2[1] ~= 'panel'
	                          and  help2[1] ~= 'stair'
	                          and  help2[1] ~= 'slab') then
		return
	end
--	for i,v in ipairs(circular_saw.names) do
--		modname..':'..v[1]..'_'..material..v[2]

-- TODO: write better and more correct method of getting the names of the materials
-- TODO: make sure only nodes produced by the saw are listed here
	help[1]='default'
	local basic_node_name = help[1]..':'..help2[2]
	-- node found that fits into the saw
	recipes[#recipes+1] = {
		method = 'saw',
		type = 'saw',
		items = {basic_node_name},
		output = node_name
	}
	return recipes
end

replacer.add_colormachine_recipe = function(node_name, recipes)
	if not minetest.get_modpath('colormachine') or not colormachine then
		return
	end
	local res = colormachine.get_node_name_painted(node_name, '')

	if not res or not res.possible or #res.possible < 1 then
		return
	end

	-- paintable node found
	recipes[#recipes+1] = {
		method = 'colormachine',
		type = 'colormachine',
		items = {res.possible[1]},
		output = node_name
	}
	return recipes
end

replacer.inspect_show_crafting = function(name, node_name, fields)
	if not name then
		return
	end

	local recipe_nr = 1
	if not node_name then
		node_name  = fields.node_name
		recipe_nr = tonumber(fields.recipe_nr)
	end
	-- turn it into an item stack so that we can handle dropped stacks etc
	local stack = ItemStack(node_name)
	node_name = stack:get_name()

	-- the player may ask for recipes of ingredients to the current recipe
	if fields then
		for k,v in pairs(fields) do
			if v and v == '' and (minetest.registered_items[k]
			                  or  minetest.registered_nodes[k]
			                  or  minetest.registered_craftitems[k]
			                  or  minetest.registered_tools[k]) then
				node_name = k
				recipe_nr = 1
			end
		end
	end

	local res = minetest.get_all_craft_recipes(node_name)
	if not res then
		res = {}
	end
	-- add special recipes for nodes created by machines
	replacer.add_circular_saw_recipe(node_name, res)
	replacer.add_colormachine_recipe(node_name, res)

	-- offer all alternate crafting recipes through prev/next buttons
	if     fields and fields.prev_recipe and recipe_nr > 1 then
		recipe_nr = recipe_nr - 1
	elseif fields and fields.next_recipe and recipe_nr < #res then
		recipe_nr = recipe_nr + 1
	end

	local desc = nil
	if       minetest.registered_nodes[node_name] then
		if     minetest.registered_nodes[node_name].description
		   and minetest.registered_nodes[node_name].description ~= '' then
			desc = '"'..minetest.registered_nodes[node_name].description..'" block'
		elseif minetest.registered_nodes[node_name].name then
			desc = '"'..minetest.registered_nodes[node_name].name..'" block'
		else
			desc = ' - no description provided - block'
		end
	elseif   minetest.registered_items[node_name] then
		if     minetest.registered_items[node_name].description
		   and minetest.registered_items[node_name].description ~= '' then
			desc = '"'..minetest.registered_items[node_name].description..'" item'
		elseif minetest.registered_items[node_name].name then
			desc = '"'..minetest.registered_items[node_name].name..'" item'
		else
			desc = ' - no description provided - item'
		end
	end
	if not desc or desc == '' then
		desc = ' - no description provided - '
	end

	local formspec = 'size[6,6]'..
		'label[0,5.5;This is a '..minetest.formspec_escape(desc)..'.]'..
		'button_exit[5.0,4.3;1,0.5;quit;Exit]'..
		'label[0,0;Name:]'..
		-- two invisible fields for passing on information
		'field[20,20;0.1,0.1;node_name;node_name;'..node_name..']'..
		'field[21,21;0.1,0.1;recipe_nr;recipe_nr;'..tostring(recipe_nr)..']'..
		'label[1,0;'..tostring(node_name)..']'..
		'item_image_button[5,2;1.0,1.0;'..tostring(node_name)..';normal;]'

	-- provide additional information regarding the node that has been inspected
	if fields.pos then
		formspec = formspec..'label[0.0,0.3;Located at '..
			minetest.formspec_escape(minetest.pos_to_string(fields.pos))
		if fields.param2 then
			formspec = formspec..' with param2='..tostring(fields.param2)
		end
		if fields.light then
			formspec = formspec..' and receiving '..tostring(fields.light)..' light'
		end
		formspec = formspec..'.]'
	end

	-- show information about protection
	if fields.protected_info and fields.protected_info ~= '' then
		formspec = formspec..'label[0.0,4.5;'..
			minetest.formspec_escape(fields.protected_info)..']'
	end

	if not res or recipe_nr > #res or recipe_nr < 1 then
		recipe_nr = 1
	end
	if res and recipe_nr > 1 then
		formspec = formspec..'button[3.8,5;1,0.5;prev_recipe;prev]'
	end
	if res and recipe_nr < #res then
		formspec = formspec..'button[5.0,5.0;1,0.5;next_recipe;next]'
	end
	if not res or #res < 1 then
		formspec = formspec..'label[3,1;No recipes.]'
		if    minetest.registered_nodes[node_name]
		  and minetest.registered_nodes[node_name].drop then
			local drop = minetest.registered_nodes[node_name].drop
			if drop then
				if      type(drop) == 'string' and drop ~= node_name then
					formspec = formspec..'label[2,1.6;Drops on dig:]'..
						'item_image_button[2,2;1.0,1.0;'..replacer.image_button_link(drop)..']'
				elseif type(drop) == 'table' and drop.items then
					local droplist = {}
					for _,drops in ipairs(drop.items) do
						for _,item in ipairs(drops.items) do
							-- avoid duplicates; but include the item itshelf
							droplist[item] = 1
						end
					end
					local i = 1
					formspec = formspec..'label[2,1.6;May drop on dig:]'
					for k,v in pairs(droplist) do
						formspec = formspec..
							'item_image_button['..(((i-1)%3)+1)..','..math.floor(((i-1)/3)+2)..
								';1.0,1.0;'..replacer.image_button_link(k)..']'
						i = i+1
					end
				end
			end
		end
	else
		formspec = formspec..'label[1,5;Alternate '..tostring(recipe_nr)..
			'/'..tostring(#res)..']'
		-- reverse order; default recipes (and thus the most intresting ones)
		-- are usually the oldest
		local recipe = res[#res+1-recipe_nr]
		if      recipe.type == 'normal' and recipe.items then
			local width = recipe.width
			if not width or width == 0 then
				width = 3
			end
			for i=1,9 do
				if recipe.items[i] then
					formspec = formspec..'item_image_button['..(((i-1)%width)+1)..
						','..(math.floor((i-1)/width)+1)..';1.0,1.0;'..
						replacer.image_button_link(recipe.items[i])..']'
				end
			end
		elseif  recipe.type == 'cooking'
		   and  recipe.items
		   and #recipe.items == 1
		   and  recipe.output == '' then
			formspec = formspec..'item_image_button[1,1;3.4,3.4;'..
				replacer.image_button_link('default:furnace_active')..']'..
				'item_image_button[2.9,2.7;1.0,1.0;'..
				replacer.image_button_link(recipe.items[1])..']'..
				'label[1.0,0;'..tostring(recipe.items[1])..']'..
				'label[0,0.5;This can be used as a fuel.]'
		elseif  recipe.type == 'cooking'
		   and  recipe.items
		   and #recipe.items == 1 then
			formspec = formspec..'item_image_button[1,1;3.4,3.4;'..
				replacer.image_button_link('default:furnace')..']'..
				'item_image_button[2.9,2.7;1.0,1.0;'..
				replacer.image_button_link(recipe.items[1])..']'
		elseif  recipe.type == 'colormachine'
		   and  recipe.items
		   and #recipe.items == 1 then
			formspec = formspec..'item_image_button[1,1;3.4,3.4;'..
				replacer.image_button_link('colormachine:colormachine')..']'..
				'item_image_button[2,2;1.0,1.0;'..
				replacer.image_button_link(recipe.items[1])..']'
		elseif  recipe.type == 'saw'
		   and  recipe.items
		   and #recipe.items == 1 then
			formspec = formspec..'item_image_button[1,1;3.4,3.4;'..
				replacer.image_button_link('moreblocks:circular_saw')..']'..
				'item_image_button[2,0.6;1.0,1.0;'..
				replacer.image_button_link(recipe.items[1])..']'
		else
			formspec = formspec..'label[3,1;Error: Unkown recipe.]'
		end
		-- show how many of the items the recipe will yield
		local outstack = ItemStack(recipe.output)
		if outstack and outstack:get_count() and outstack:get_count() > 1 then
			formspec = formspec..'label[5.5,2.5;'..tostring(outstack:get_count())..']'
		end
	end
	minetest.show_formspec(name, 'replacer:crafting', formspec)
end

-- translate general formspec calls back to specific calls
replacer.form_input_handler = function(player, formname, fields)
	if formname and formname == 'replacer:crafting' and player and not fields.quit then
		replacer.inspect_show_crafting(player:get_player_name(), nil, fields)
		return
	end
end

-- establish a callback so that input from the player-specific formspec gets handled
minetest.register_on_player_receive_fields(replacer.form_input_handler)

minetest.register_craft({
	output = 'replacer:inspect',
	recipe = {
		{'default:torch'},
		{'default:stick'},
	}
})
