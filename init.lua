replacer = {}

dofile(minetest.get_modpath('replacer')..'/check_owner.lua')
dofile(minetest.get_modpath('replacer')..'/inspect.lua')

minetest.register_tool('replacer:replacer', {
	description = 'Node replacement tool',
	groups = {},
	inventory_image = 'replacer_replacer.png',
	wield_image = '',
	wield_scale = {x=1,y=1,z=1},
	stack_max = 1, -- it has to store information - thus only one can be stacked
	liquids_pointable = true, -- it is ok to paint in/with water
	node_placement_prediction = nil,
	metadata = 'default:dirt', -- default replacement: common dirt

	on_place = function(itemstack, placer, pointed_thing)
		if placer == nil or pointed_thing == nil then
			return itemstack -- nothing consumed
		end

		local name = placer:get_player_name()
		local keys = placer:get_player_control()

		-- just place the stored node if no new one is to be selected
		if not keys['sneak'] then
			return replacer.replace(itemstack, placer, pointed_thing, true)
		end

		if pointed_thing.type ~= 'node' then
			minetest.chat_send_player(name, 'Error: No node selected.')
			return nil
		end

		local pos  = minetest.get_pointed_thing_position(pointed_thing, false)
		local node = minetest.env:get_node_or_nil(pos)

		local item = itemstack:to_table()
		-- make sure metadata is always set
		if node ~= nil and node.name then
			item['metadata'] = node.name..' '..node.param1..' '..node.param2
		else
			item['metadata'] = 'default:dirt 0 0'
		end
		itemstack:replace(item)

		minetest.chat_send_player(name,
			'Node replacement tool set to: "'..item[ 'metadata' ]..'".'
		)

		return itemstack -- nothing consumed but data changed
	end,

	on_use = function(itemstack, user, pointed_thing)
		return replacer.replace(itemstack, user, pointed_thing, false)
	end,
})

replacer.replace = function(itemstack, user, pointed_thing, mode)
	if user == nil or pointed_thing == nil then
		return nil
	end

	local name = user:get_player_name()

	if pointed_thing.type ~= 'node' then
		minetest.chat_send_player(name, '  Error: No node.')
		return nil
	end

	local pos  = minetest.get_pointed_thing_position(pointed_thing, mode)
	local node = minetest.env:get_node_or_nil(pos)

	if node == nil then
		minetest.chat_send_player(name, 'Error: Target node not yet loaded.'..
			' Please wait a moment for the server to catch up.')
		return nil
	end

	local item = itemstack:to_table()
	if not item['metadata'] or item['metadata'] == '' then
		item['metadata'] = 'default:dirt 0 0'
	end

	-- regain information about nodename, param1 and param2
	local data = item['metadata']:split(' ')
	-- the old format stored only the node name
	if #data < 3 then
		data[2] = 0
		data[3] = 0
	end

	-- if someone else owns that node then we can not change it
	if replacer_homedecor_node_is_owned(pos, user) then
		return nil
	end

	if node.name == data[1] then
		if node.param1 ~= data[2] or node.param2 ~= data[3] then
			-- the node itself remains the same, but the orientation was changed
			minetest.env:add_node(pos, {
				name   = node.name,
				param1 = data[2],
				param2 = data[3]
			})
		end
		return nil
	end

	-- in survival mode, the player has to provide the node he wants to be placed
	if not minetest.setting_getbool('creative_mode') and
	   not minetest.check_player_privs(name, {creative=true}) then

		-- Players usually don't carry around dirt_with_grass, but it's safe
		-- to assume normal dirt here. Fortunately, dirt and dirt_with_grass
		-- do not make use of rotation.
		if data[1] == 'default:dirt_with_grass' then
		   data[1] = 'default:dirt'
		   item['metadata'] = 'default:dirt 0 0'
		end

		-- does the player have at least one of the desired nodes?
		if not user:get_inventory():contains_item('main', data[1]) then
			minetest.chat_send_player(name, 'You have no further "'..
				(data[1] or '?')..'". Replacement failed.')
			return nil
		end

		-- consume the item
		user:get_inventory():remove_item('main', data[1]..' 1')
	end

	-- give the player the item by simulating digging if possible
	if    node.name ~= 'air'
	  and node.name ~= 'ignore'
	  and node.name ~= 'default:lava_source'
	  and node.name ~= 'default:lava_flowing'
	  and node.name ~= 'default:water_source'
	  and node.name ~= 'default:water_flowing' then

		minetest.node_dig(pos, node, user)

		local dug_node = minetest.env:get_node_or_nil(pos)
		if not dug_node or dug_node.name == node.name then
			minetest.chat_send_player(name, 'Replacing "'..
				(node.name or 'air')..'" with "'..(item['metadata'] or '?')..
				'" failed. Unable to remove old node.')
			return nil
		end
	end

	local placeitemstack = ItemStack({
		name   = data[1],
		param1 = data[2],
		param2 = data[3]
	})
	minetest.item_place_node(placeitemstack, user, pointed_thing, data[3])
	return nil
end

minetest.register_craft({
	output = 'replacer:replacer',
	recipe = {
		{ 'default:chest', '',              '' },
		{ '',              'default:stick', '' },
		{ '',              '',              'default:chest' },
	}
})
