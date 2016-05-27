local load_time_start = os.clock()

replacer = {}

local modpath = minetest.get_modpath('replacer')

dofile(modpath..'/inspect.lua')
dofile(modpath..'/replacer.lua')

minetest.log(
	'action',
	string.format(
		'['..minetest.get_current_modname()..'] loaded in %.3fs',
		os.clock() - load_time_start
	)
)
