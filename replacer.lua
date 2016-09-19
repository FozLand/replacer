local default_item = { -- default replacement: common dirt
	name = 'default:dirt',
	param1 = 0,
	param2 = 0,
	drop = 'default:dirt',
}

local is_valid_placement = function(itemstack, placer, pointed_thing)
	if placer == nil or pointed_thing == nil then
		return false
	end
	if pointed_thing.type ~= 'node' then
		minetest.chat_send_player(placer:get_player_name(),
			'Error: No node selected.')
		return false
	end
	return true
end

local get_def_boxes = function(bdef)
	local boxes = {}
	if bdef.type == 'wallmounted' then
		if bdef.wall_top or bdef.wall_bottom or bdef.wall_side then
			boxes = {bdef.wall_top, bdef.wall_bottom, bdef.wall_side}
		else
			boxes = {{0, 0, 0, 0, 0, 0}}
		end
	elseif bdef.type == 'fixed'
	    or bdef.type == 'leveled'
	    or bdef.type == 'connected' then
		-- I don't know if this handles leveled properly in all cases.
		-- For connected nodes, the replacer only cares about the fixed portion.
		if type(bdef.fixed[1]) == 'table' then
			boxes = bdef.fixed
		else
			boxes = {bdef.fixed}
		end
	else -- assume regular type
		boxes = {{-0.5, -0.5, -0.5, 0.5, 0.5, 0.5}}
	end

	return boxes
end

local get_boxes = function(name)
	-- Try to find the node's box definitions. Generally we want the larger of
	-- either the node_box or the selection_box, so here we take the union.
	local ndef = minetest.registered_nodes[name]
	local boxes = {}
	if ndef.node_box then
		for _,box in pairs(get_def_boxes(ndef.node_box)) do
			table.insert(boxes,box)
		end
	end
	if ndef.selection_box then
		for _,box in ipairs(get_def_boxes(ndef.selection_box)) do
			table.insert(boxes,box)
		end
	end

	return boxes
end

local round = function(number)
	-- Squishy rounding:
	-- Slightly favor rounding toward zero.
	local squish = 0.1
	if number >= 0.5 + squish then
		return math.ceil(number - 0.5 - squish)
	elseif number <= -0.5 - squish then
		return math.floor(number + 0.5 + squish)
	else
		return 0
	end

	-- Normal rounding:
	-- Round numbers to the nearest integer. Numbers exactly between
	-- two integers (ending in .5) are rounded toward zero.

	--if number >= 0.5 then
		--return math.ceil(number - 0.5)
	--else
		--return math.floor(number + 0.5)
	--end
end

local transform = {
	-- return coordinates indexed by param2, e.g. transform[3](x,y,z)
	[0]  = function(x, y, z) return  x, y, z end,
	[1]  = function(x, y, z) return  z, y,-x end,
	[2]  = function(x, y, z) return -x, y,-z end,
	[3]  = function(x, y, z) return -z, y, x end,

	[4]  = function(x, y, z) return  x,-z, y end,
	[5]  = function(x, y, z) return  z, x, y end,
	[6]  = function(x, y, z) return -x, z, y end,
	[7]  = function(x, y, z) return -z,-x, y end,

	[8]  = function(x, y, z) return  x, z,-y end,
	[9]  = function(x, y, z) return  z,-x,-y end,
	[10] = function(x, y, z) return -x,-z,-y end,
	[11] = function(x, y, z) return -z, x,-y end,

	[12] = function(x, y, z) return  y,-x, z end,
	[13] = function(x, y, z) return  y,-z,-x end,
	[14] = function(x, y, z) return  y, x,-z end,
	[15] = function(x, y, z) return  y, z, x end,

	[16] = function(x, y, z) return -y, x, z end,
	[17] = function(x, y, z) return -y, z,-x end,
	[18] = function(x, y, z) return -y,-x,-z end,
	[19] = function(x, y, z) return -y,-z, x end,

	[20] = function(x, y, z) return -x,-y, z end,
	[21] = function(x, y, z) return -z,-y,-x end,
	[22] = function(x, y, z) return  x,-y,-z end,
	[23] = function(x, y, z) return  z,-y, x end,
}

local p_string = function(p)
	-- return a point triple as a string
	return tostring(p[1]..','..tostring(p[2])..','..tostring(p[3]))
end

local get_occupied_nodes = function(pos, name, param2)
	local node_matrix = {}
	local boxes = get_boxes(name)
	if param2 < 0 or param2 > 23 then param2 = 0 end
	for _,box in ipairs(boxes) do
		local x1, y1, z1 = transform[param2](box[1], box[2], box[3])
		local x2, y2, z2 = transform[param2](box[4], box[5], box[6])
		x1, y1, z1 = round(x1), round(y1), round(z1)
		x2, y2, z2 = round(x2), round(y2), round(z2)
		for i = math.min(x1,x2),math.max(x1,x2) do
			for j = math.min(y1,y2),math.max(y1,y2) do
				for k = math.min(z1,z2),math.max(z1,z2) do
					local p = vector.new(i, j, k)
					node_matrix[p_string({i,j,k})] = vector.add(pos,p)
				end
			end
		end
	end

	return node_matrix
end

-- nodes that should be replaced without digging first
local skip_dig = {
	['air'] = true,
	['ignore'] = true,
	['default:lava_source'] = true,
	['default:lava_flowing'] = true,
	['default:water_source'] = true,
	['default:water_flowing'] = true,
	['default:river_water_source'] = true,
	['default:river_water_flowing'] = true,
}

local dig = function(pos, user)
	local node = minetest.get_node_or_nil(pos)

	if not node then
		minetest.chat_send_player(name, 'Error: Target node not yet loaded.'..
			' Please wait a moment for the server to catch up.')
		return false
	end

	--print('digging '..node.name..' at '..minetest.pos_to_string(pos))

	-- Return true if digging was successful, false otherwise.
	if not skip_dig[node.name] then
		minetest.node_dig(pos, node, user)

		-- Here we intentionally use the deprecated `minetest.env` instead of
		-- just calling `minetest` because it reliably avoids what appears to
		-- be a race condition between node_dig and get_node_or_nil, that
		-- causes nil to be returned in some cases.
		local dug_node = minetest.env:get_node_or_nil(pos)
		if not dug_node or dug_node.name == node.name then
			return false
		end
	end
	--print('dug '..minetest.pos_to_string(pos)..' successfully')
	return true
end

local record = function(itemstack, placer, pointed_thing)
	local pos  = minetest.get_pointed_thing_position(pointed_thing, false)
	local node = minetest.get_node_or_nil(pos)
	local item_meta = minetest.get_meta(pos)

	-- ensure tool metadata is always set and node is registered
	local item = default_item
	if node and node.name and minetest.registered_nodes[node.name] then
		-- xpanes need special handling to copy only the base pane and not one of
		-- its permutations.
		if string.match(node.name, '^xpanes:.+_[0-9]+') then
			--print('Found an xpane: '..node.name)
			node.name = string.match(node.name, '^(xpanes:.+)_[0-9]+')
			--print('Setting node to: '..node.name)
		end
		item = {
			name = node.name,
			param1 = node.param1 or 0,
			param2 = node.param2 or 0,
			meta_fields = item_meta:to_table().fields or nil,
		}
	end

	itemstack:set_metadata(minetest.serialize(item))

	minetest.chat_send_player(placer:get_player_name(),
		'Node replacement tool set to: "'..item.name..
		' '..item.param1..' '..item.param2..'".')

	--print('item = '..item.name, item.param1, item.param2, item.meta_fields)
	--if type(item.meta_fields) == 'table' then
		--for k,v in pairs(item.meta_fields) do
			--print(k,v)
		--end
	--end

	return itemstack -- nothing consumed but data changed
end

minetest.register_tool('replacer:replacer', {
	description = 'Node replacement tool',
	groups = {},
	inventory_image = 'replacer_replacer.png',
	wield_image = '',
	wield_scale = {x=1,y=1,z=1},
	stack_max = 1, -- it has to store information - thus only one can be stacked
	liquids_pointable = true, -- it is ok to paint in/with water
	node_placement_prediction = nil,
	metadata = minetest.serialize(default_item),
	-- right click
	on_place = function(itemstack, placer, pointed_thing)
		if is_valid_placement(itemstack, placer, pointed_thing) then
			if placer:get_player_control()['sneak'] then
				return record(itemstack, placer, pointed_thing)
			else
				return replacer.place(itemstack, placer, pointed_thing)
			end
		else
			return nil -- no change
		end
	end,
	-- left click
	on_use = function(itemstack, user, pointed_thing)
		if is_valid_placement(itemstack, user, pointed_thing) then
			if user:get_player_control()['sneak'] then
				return record(itemstack, user, pointed_thing)
			else
				return replacer.replace(itemstack, user, pointed_thing)
			end
		else
			return nil -- no change
		end
	end,
})

replacer.place = function(itemstack, user, pointed_thing)
	return replacer.replace(itemstack, user, pointed_thing, true)
end

replacer.replace = function(itemstack, user, pointed_thing, mode)

	local name = user:get_player_name()
	local pos  = minetest.get_pointed_thing_position(pointed_thing, mode)

	local item = minetest.deserialize(itemstack:get_metadata())
	if not item or not item.name or not item.param1 or not item.param2 then
		item = default_item
	end

	-- Check if the player has the item or creative.
	local use_item = false
	if user:get_inventory():contains_item('main', item.name) then
		use_item = true
	elseif not minetest.check_player_privs(name, {creative=true}) and
	       not minetest.setting_getbool('creative_mode') then
		minetest.chat_send_player(name, 'You have no further "'..
			(item.name or '?')..'". Replacement failed.')
		return nil
	end

	--
	-- Determine if placement here should be allowed.
	--

	-- Find the set of positions this node would occupy if placed here.
	local occupied_nodes = get_occupied_nodes(pos, item.name, item.param2)

	-- Check if the new node will fit.
	for string_p,p in pairs(occupied_nodes) do
		-- If any occupied node is protected abort.
		--print(string_p)
		if minetest.is_protected(p, name) then
			if string_p == '0,0,0' then
				minetest.record_protection_violation(p, name)
			else
				minetest.chat_send_player(name, item.name..' doesn\'t fit here.')
			end
			return nil
		end

		-- If any adjacent occupied nodes are already filled abort.
		if string_p ~= '0,0,0' then
			local node = minetest.get_node(p)
			local ndef = minetest.registered_nodes[node.name]
			if not skip_dig[node.name] then
				minetest.chat_send_player(name,
					item.name..' doesn\'t fit here. A '..node.name..' is in the way.')
				return nil
			end
		end
	end

	--
	-- Looks like the placement is ok so try to remove any node in the way.
	--

	-- Try to dig the node pointed at node. We need to simulate digging to make
	-- sure we add the correct node to the players inventory. For example digging
	-- stone give cobble.
	if not dig(pos, user) then
		local node = minetest.get_node(pos)
		minetest.chat_send_player(name, 'Unable to remove '..(node.name or 'air'))
		return nil
	end

	-- Remove the remaining occupied nodes. These must be skip_nodes or
	-- or we should have already aborted.
	occupied_nodes['0,0,0'] = nil
	for string_p,p in pairs(occupied_nodes) do
		minetest.remove_node(p)
	end

	--
	-- So far so good, lets try to place the item.
	--

	-- Many nodes are irregular in that they have companion nodes or they require
	-- metadata be set in order to function. Lets try to handle them properly.
	-- We have three functions to choose from for setting the node.
	--
	--   item_place_node(placeitemstack, user, pointed_thing, item.param2)
	--		 This function calls after_place_node() when its finished. For most
	--     nodes this is a good thing but for a few it changes something about the
	--		 node that we don't want to change, like its orientation.
	--   place_node()
	--     This function ignores param2 which makes setting the nodes orientation
	--     impossible. It also calls after_place_node() when its finished, but it
	--     sends a nil placer, so setting ownership becomes impossible.
	--   set_node(pos, {name = item.name, param2 = item.param2})
	--     This function doesn't trigger any callbacks, so we will have to manage
	--     those on are own. Its harder, but gives maximum flexibilty.
	--
	-- For nodes with desirable custom on_place() behavior, we will have to decide
	-- whether to call their on_place() directly or to call set_node() and try to
	-- replicate their custom behaviors. A call to on_place() will trigger the
	-- after_place_node() callback as well so we can only use this approach when
	-- both are acceptable. For nodes without custom on_place(), but with an
	-- after_place_node() callback, we will call, skip, or replicate parts of that
	-- callback as needed after the call to set_node().

	local	placeitemstack = ItemStack({
			name = item.name,
	})

	local item_def = minetest.registered_items[item.name]
	if item_def.groups.seed and item_def.on_place then
		-- seeds need their special on_place() to be called.
		local pt = {
			type = 'node',
			above = pos,
			under = {x = pos.x, y = pos.y-1, z = pos.z},
		}
		item_def.on_place(placeitemstack, user, pt)
	elseif item_def.groups.bed then
		-- replicate some of beds on_place behaviors
		local top_name = string.match(item.name,'^(.+)_bottom$') .. '_top'
		local top_pos = vector.add(pos,vector.new(transform[item.param2](0, 0, 1)))
		minetest.set_node(pos,    {name = item.name, param2 = item.param2})
		minetest.set_node(top_pos, {name = top_name, param2 = item.param2})
	elseif string.match(item.name, '^lrfurn:coffeetable_back$') then
		-- replicate some of coffeetables after_place_node behaviors
		local front_name = string.match(item.name,'^(.+)_back$') .. '_front'
		local front_pos = vector.add(pos,vector.new(transform[item.param2](0, 0, 1)))
		minetest.set_node(pos,       {name = item.name,  param2 = item.param2})
		minetest.set_node(front_pos, {name = front_name, param2 = item.param2})
	elseif string.match(item.name, '^xpanes:') then
		-- xpanes need their local update_nearby to be called which can only be
		-- accessed externally by placing an xpane.
		minetest.item_place_node(placeitemstack, user, pointed_thing, item.param2)
	else
		minetest.set_node(pos, {name = item.name, param2 = item.param2})
	end

	-- Consume the item.
	if use_item then
		user:get_inventory():remove_item('main', item.name..' 1')
	end

	--
	-- The node is now placed but may need some after place behavior to function
	-- properly.
	--

	-- DOORS --
	-- Regular doors need a hidden upper hinge node to protect them from having
	-- some other node placed there and they need the integer metadata variable
	-- 'state' for the opening and closing sounds to match the copied door.
	-- Homedecor mod doors use a string metadata variable 'closed' for the same
	-- purpose, where '1' is closed and '0' is open. Locked regular doors also
	-- require metadata to be set for ownership to work.

	if item_def.groups.door then
		local above = {x = pos.x, y = pos.y+1, z = pos.z}
		if string.match(item.name, '_a$') then
			minetest.set_node(above, {name = 'doors:hidden', param2 = item.param2})
			minetest.get_meta(pos):set_int('state', item.meta_fields.state)
		elseif string.match(item.name, '_b$') then
			minetest.set_node(above, {name = 'doors:hidden', param2 = (item.param2 + 3 ) % 4})
			minetest.get_meta(pos):set_int('state', item.meta_fields.state)
		end

		-- Add ownership for regular locked doors
		if item_def.protected and not item_def.after_place_node then
			local meta = minetest.get_meta(pos)
			meta:set_string('doors_owner', name)
			meta:set_string('infotext', 'Owned by ' .. name)
		end
	end

	if string.match(item.name, '^homedecor:door_') then
		minetest.get_meta(pos):set_string('closed', item.meta_fields.closed)
	end

	-- SIGNS --
	-- Locked signs set owner meta during on_place
	if string.match(item.name, '^locked_sign:') then
		minetest.get_meta(pos):set_string('owner', name)
	end


	-- OTHERS --
	-- Usually the after_place_node callback is used to set meta data like
	-- ownership, but there are special cases where it is not desired.

	local skip_apn_callback = {
		-- lrfurn tries to set orientation based on the player's facing direction.
		-- lrfurn coffee_tables are bugged either way so have custom handling
		['lrfurn'] = true,
		-- homedecor beds after_place_node is redundant with its on_construct
		-- homedecor cobwebs try to set orientation
		-- homedecor lighting after_place_node does nothing
		-- homedecor spiral_staircase tries to set orientation
		['homedecor'] = true, -- exceptions are made for locked items
		-- mesecons pistons try to set orientation
		['mesecons_pistons'] = true,
		-- mesecons noteblock sets its note
		['mesecons_noteblock'] = true,
		-- mesecons node_detector tries to set orientation
		-- mesecons player_detector tries to set orientation
		['mesecons_detector'] = true,
	}

	local mod_name = string.match(item.name, '^[^:]+')

	if item_def.after_place_node then
		if string.match(item.name, '^lrfurn:coffeetable_back$') then
			-- replicate some of coffeetables after_place_node behaviors
			local front_name = string.match(item.name,'^(.+)_back$') .. '_front'
			local front_pos = vector.add(pos,vector.new(transform[item.param2](0, 0, 1)))
			minetest.set_node(pos,       {name = item.name,  param2 = item.param2})
			minetest.set_node(front_pos, {name = front_name, param2 = item.param2})
		elseif string.match(item.name, '^homedecor:.+_locked$') or
		       not skip_apn_callback[mod_name] then
			item_def.after_place_node(pos, user, placeitemstack, pointed_thing)
		end
	end

	-- BUSHES CLASSIC --
	-- The after_place_node callback in bushes classic replaces a fruit bearing
	-- bush with its fruitless counterpart, but if the fruitless variety was
	-- placed with the replacer, its bush_type meta data field is set to
	-- fruitless. This causes the bush to never grow fruit and sometimes it causes
	-- the server to crash. The metadata must be fixed after the callback returns.
	if string.match(item.name, '^bushes:fruitless_bush$') then
		minetest.get_meta(pos):set_string('bush_type', item.meta_fields.bush_type)
	end

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
