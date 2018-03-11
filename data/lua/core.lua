-- Note: This file is loaded automatically by the engine.

function wesnoth.alert(title, msg)
	if not msg then
		msg = title;
		title = "";
	end
	wesnoth.show_message_box(title, msg, "ok", true)
end

function wesnoth.confirm(title, msg)
	if not msg then
		msg = title;
		title = "";
	end
	return wesnoth.show_message_box(title, msg, "yes_no", true)
end


--[========[Config Manipulation Functions]========]

wml = {}
wml.tovconfig = wesnoth.tovconfig
wml.tostring = wesnoth.debug

local function ensure_config(cfg)
	if type(cfg) == 'table' then
		return true
	end
	if type(cfg) == 'userdata' then
		if getmetatable(cfg) == 'wml object' then return true end
		error("Expected a table or wml object but got " .. getmetatable(cfg), 3)
	else
		error("Expected a table or wml object but got " .. type(cfg), 3)
	end
	return false
end

--! Returns the first subtag of @a cfg with the given @a name.
--! If @a id is not nil, the "id" attribute of the subtag has to match too.
--! The function also returns the index of the subtag in the array.
function wml.get_child(cfg, name, id)
	ensure_config(cfg)
	for i,v in ipairs(cfg) do
		if v[1] == name then
			local w = v[2]
			if not id or w.id == id then return w, i end
		end
	end
end

--! Returns the nth subtag of @a cfg with the given @a name.
--! (Indices start at 1, as always with Lua.)
--! The function also returns the index of the subtag in the array.
function wml.get_nth_child(cfg, name, n)
	ensure_config(cfg)
	for i,v in ipairs(cfg) do
		if v[1] == name then
			n = n - 1
			if n == 0 then return v[2], i end
		end
	end
end

--! Returns the number of subtags of @a with the given @a name.
function wml.child_count(cfg, name)
	ensure_config(cfg)
	local n = 0
	for i,v in ipairs(cfg) do
		if v[1] == name then
			n = n + 1
		end
	end
	return n
end

--! Returns an iterator over all the subtags of @a cfg with the given @a name.
function wml.child_range(cfg, tag)
	ensure_config(cfg)
	local iter, state, i = ipairs(cfg)
	local function f(s)
		local c
		repeat
			i,c = iter(s,i)
			if not c then return end
		until c[1] == tag
		return c[2]
	end
	return f, state
end

--! Returns an array from the subtags of @a cfg with the given @a name
function wml.child_array(cfg, tag)
	ensure_config(cfg)
	local result = {}
	for val in wml.child_range(cfg, tag) do
		table.insert(result, val)
	end
	return result
end

--[========[WML Tag Creation Table]========]

local create_tag_mt = {
	__metatable = "WML tag builder",
	__index = function(self, n)
		return function(cfg) return { n, cfg } end
	end
}

wml.tag = setmetatable({}, create_tag_mt)

--[========[Config / Vconfig Unified Handling]========]

function wml.literal(cfg)
	if type(cfg) == "userdata" then
		return cfg.__literal
	else
		return cfg or {}
	end
end

function wml.parsed(cfg)
	if type(cfg) == "userdata" then
		return cfg.__parsed
	else
		return cfg or {}
	end
end

function wml.shallow_literal(cfg)
	if type(cfg) == "userdata" then
		return cfg.__shallow_literal
	else
		return cfg or {}
	end
end

function wml.shallow_parsed(cfg)
	if type(cfg) == "userdata" then
		return cfg.__shallow_parsed
	else
		return cfg or {}
	end
end

--[========[Deprecation Helpers]========]

-- Need a textdomain for translatable deprecation strings.
local _ = wesnoth.textdomain "wesnoth"

-- Marks a function or subtable as deprecated.
-- Parameters:
---- elem_name: the full name of the element being deprecated (including the module)
---- replacement: the name of the element that will replace it (including the module)
---- level: deprecation level (1-4)
---- version: the version at which the element may be removed (level 2 or 3 only)
---- Set to nil if deprecation level is 1 or 4
---- elem: The actual element being deprecated
---- detail_msg: An optional message to add to the deprecation message
function wesnoth.deprecate_api(elem_name, replacement, level, version, elem, detail_msg)
	local message = detail_msg or ''
	if replacement then
		message = message .. " " .. wesnoth.format(
			_"(Note: You should use $replacement instead in new code)",
			{replacement = replacement})
	end
	if type(level) ~= "number" or level < 1 or level > 4 then
		local err_params = {level = level}
		-- Note: This message is duplicated in src/deprecation.cpp
		-- Any changes should be mirrorred there.
		error(wesnoth.format(_"Invalid deprecation level $level (should be 1-4)", err_params))
	end
	local msg_shown = false
	if type(elem) == "function" then
		return function(...)
			if not msg_shown then
				msg_shown = true
				wesnoth.deprecated_message(elem_name, level, version, message)
			end
			return elem(...)
		end
	elseif type(elem) == "table" then
		local mt = {
			__index = function(self, key)
				if not msg_shown then
					msg_shown = true
					wesnoth.deprecated_message(elem_name, level, version, message)
				end
				return elem[key]
			end,
			__newindex = function(self, key, val)
				if not msg_shown then
					msg_shown = true
					wesnoth.deprecated_message(elem_name, level, version, message)
				end
				elem[key] = val
			end,
		}
		-- Don't clobber the old metatable.
		local old_mt = getmetatable(elem)
		if type(old_mt) == "table" then
			setmetatable(mt, old_mt)
		end
		return setmetatable({}, mt)
	else
		wesnoth.log('warn', "Attempted to deprecate something that is not a table or function: " ..
			elem_name .. " -> " .. replacement .. ", where " .. elem_name .. " = " .. tostring(elem))
	end
	return elem
end

if wesnoth.kernel_type() == "Game Lua Kernel" then
	--[========[Basic variable access]========]

	wml.variable = {}
	wml.variable.get = wesnoth.get_variable
	wml.variable.set = wesnoth.set_variable
	wml.variable.get_all = wesnoth.get_all_vars

	wml.variables = setmetatable({}, {
		__metatable = "WML variables",
		__index = function(_, key)
			return wesnoth.get_variable(key)
		end,
		__newindex = function(_, key, value)
			wesnoth.set_variable(key, value)
		end
	})

	--[========[Variable Proxy Table]========]

	local variable_mt = {
		__metatable = "WML variable proxy"
	}

	local function get_variable_proxy(k)
		local v = wesnoth.get_variable(k)
		if type(v) == "table" then
			v = setmetatable({ __varname = k }, variable_mt)
		end
		return v
	end

	local function set_variable_proxy(k, v)
		if getmetatable(v) == "WML variable proxy" then
			v = wesnoth.get_variable(v.__varname)
		end
		wesnoth.set_variable(k, v)
	end

	function variable_mt.__index(t, k)
		local i = tonumber(k)
		if i then
			k = t.__varname .. '[' .. i .. ']'
		else
			k = t.__varname .. '.' .. k
		end
		return get_variable_proxy(k)
	end

	function variable_mt.__newindex(t, k, v)
		local i = tonumber(k)
		if i then
			k = t.__varname .. '[' .. i .. ']'
		else
			k = t.__varname .. '.' .. k
		end
		set_variable_proxy(k, v)
	end

	local root_variable_mt = {
		__metatable = "WML variables proxy",
		__index    = function(t, k)    return get_variable_proxy(k)    end,
		__newindex = function(t, k, v)
			if type(v) == "function" then
				-- User-friendliness when _G is overloaded early.
				-- FIXME: It should be disabled outside the "preload" event.
				rawset(t, k, v)
			else
				set_variable_proxy(k, v)
			end
		end
	}

	wml.variable.proxy = setmetatable({}, root_variable_mt)

	--[========[Variable Array Access]========]

	local function resolve_variable_context(ctx, err_hint)
		if ctx == nil then
			return {get = wesnoth.get_variable, set = wesnoth.set_variable}
		elseif type(ctx) == 'number' and ctx > 0 and ctx <= #wesnoth.sides then
			return resolve_variable_context(wesnoth.sides[ctx])
		elseif type(ctx) == 'string' then
			-- TODO: Treat it as a namespace for a global (persistent) variable
			-- (Need Lua API for accessing them first, though.)
		elseif getmetatable(ctx) == "unit" then
			return {
				get = function(path) return ctx.variables[path] end,
				set = function(path, val) ctx.variables[path] = val end,
			}
		elseif getmetatable(ctx) == "side" then
			return {
				get = function(path) return wesnoth.get_side_variable(ctx.side, path) end,
				set = function(path, val) wesnoth.set_side_variable(ctx.side, path, val) end,
			}
		elseif getmetatable(ctx) == "unit variables" or getmetatable(ctx) == "side variables" then
			return {
				get = function(path) return ctx[path] end,
				set = function(path, val) ctx[path] = val end,
			}
		end
		error(string.format("Invalid context for %s: expected nil, side, or unit", err_hint), 3)
	end

	--! Fetches all the WML container variables with name @a var.
	--! @returns a table containing all the variables (starting at index 1).
	function wml.variable.get_array(var, context)
		context = resolve_variable_context(context, "get_variable_array")
		local result = {}
		for i = 1, context.get(var .. ".length") do
			result[i] = context.get(string.format("%s[%d]", var, i - 1))
		end
		return result
	end

	--! Puts all the elements of table @a t inside a WML container with name @a var.
	function wml.variable.set_array(var, t, context)
		context = resolve_variable_context(context, "set_variable_array")
		context.set(var)
		for i, v in ipairs(t) do
			context.set(string.format("%s[%d]", var, i - 1), v)
		end
	end

	--! Creates proxies for all the WML container variables with name @a var.
	--! This is similar to helper.get_variable_array, except that the elements
	--! can be used for writing too.
	--! @returns a table containing all the variable proxies (starting at index 1).
	function wml.variable.get_proxy_array(var)
		local result = {}
		for i = 1, wesnoth.get_variable(var .. ".length") do
			result[i] = get_variable_proxy(string.format("%s[%d]", var, i - 1))
		end
		return result
	end

	--[========[Game Interface Control]========]

	wesnoth.intf = {
		delay = wesnoth.delay,
		float_label = wesnoth.float_label,
		select_unit = wesnoth.select_unit,
		highlight_hex = wesnoth.highlight_hex,
		deselect_hex = wesnoth.deselect_hex,
		get_selected_hex = wesnoth.get_selected_tile,
		scroll_to_hex = wesnoth.scroll_to_tile,
		lock = wesnoth.lock_view,
		is_locked = wesnoth.view_locked,
		is_skipping_messages = wesnoth.is_skipping_messages,
		skip_messages = wesnoth.skip_messages,
		add_hex_overlay = wesnoth.add_tile_overlay,
		remove_hex_overlay = wesnoth.remove_tile_overlay,
		game_display = wesnoth.theme_items,
		get_displayed_unit = wesnoth.get_displayed_unit,
	}

	--! Fakes the move of a unit satisfying the given @a filter to position @a x, @a y.
	--! @note Usable only during WML actions.
	function wesnoth.intf.move_unit_fake(filter, to_x, to_y)
		local moving_unit = wesnoth.get_units(filter)[1]
		local from_x, from_y = moving_unit.x, moving_unit.y

		wesnoth.intf.scroll_to_hex(from_x, from_y)
		to_x, to_y = wesnoth.find_vacant_tile(x, y, moving_unit)

		if to_x < from_x then
			moving_unit.facing = "sw"
		elseif to_x > from_x then
			moving_unit.facing = "se"
		end
		moving_unit:extract()

		wml_actions.move_unit_fake{
			type      = moving_unit.type,
			gender    = moving_unit.gender,
			variation = moving.variation,
			side      = moving_unit.side,
			x         = from_x .. ',' .. to_x,
			y         = from_y .. ',' .. to_y
		}

		moving_unit:to_map(to_x, to_y)
		wml_actions.redraw{}
	end

	--[========[Units module]========]
	-- TODO: Eventually this could actually be the units metatable, allowing people to add new methods to it.
	wesnoth.units = {}
	wesnoth.units.matches = wesnoth.match_unit
	wesnoth.units.to_recall = wesnoth.put_recall_unit
	wesnoth.units.to_map = wesnoth.put_unit
	wesnoth.units.erase = wesnoth.erase_unit
	wesnoth.units.clone = wesnoth.copy_unit
	wesnoth.units.extract = wesnoth.extract_unit
	wesnoth.units.advance = wesnoth.advance_unit
	wesnoth.units.add_modification = wesnoth.add_modification
	wesnoth.units.remove_modifications = wesnoth.remove_modifications
	wesnoth.units.resistance = wesnoth.unit_resistance
	wesnoth.units.defense = wesnoth.unit_defense
	wesnoth.units.movement = wesnoth.unit_movement_cost
	wesnoth.units.vision = wesnoth.unit_vision_cost
	wesnoth.units.jamming = wesnoth.unit_jamming_cost
	wesnoth.units.ability = wesnoth.unit_ability
	wesnoth.units.transform = wesnoth.transform_unit
	wesnoth.units.select = wesnoth.select_unit

	--! Modifies all the units satisfying the given @a filter.
	--! @param vars key/value pairs that need changing.
	--! @note Usable only during WML actions.
	function wesnoth.units.modify(filter, vars)
		local units = wesnoth.get_units(filter)
		for u in pairs(units) do
			for k, v in pairs(vars) do
				-- Minor TODO: What if you want to change values of subtags?
				-- Previously would've been possible with eg {['variables.some_var'] = 'some_value'}
				-- With this implementation, it's not possible.
				u[k] = v
			end
		end
	end
end

--[========[GUI2 Dialog Manipulations]========]

gui = {dialog = {}}

gui.show_menu = wesnoth.show_menu
gui.show_speech = wesnoth.show_message_dialog
gui.show_popup = wesnoth.show_popup_dialog
gui.show_story = wesnoth.show_story
gui.show_message = wesnoth.show_message
gui.alert = wesnoth.alert
gui.confirm = wesnoth.confirm
gui.show_lua_console = wesnoth.show_lua_console
if wesnoth.kernel_type() == "Game Lua Kernel" then
	gui.show_inspector = wesnoth.gamestate_inspector
end
gui.dialog.show = wesnoth.show_dialog
gui.dialog.get_value = wesnoth.get_dialog_value
gui.dialog.set_value = wesnoth.set_dialog_value
gui.dialog.set_visible = wesnoth.set_dialog_visible
gui.dialog.set_callback = wesnoth.set_dialog_callback
gui.dialog.set_active = wesnoth.set_dialog_active
gui.dialog.set_canvas = wesnoth.set_dialog_canvas
gui.dialog.set_focus = wensoth.set_dialog_focus
gui.dialog.set_markup = wesnoth.set_dialog_markup
gui.dialog.remove_item = wesnoth.remove_dialog_item
gui.dialog.add_tree_node = wesnoth.add_dialog_tree_node
gui.dialog.add_widget_definition = wesnoth.add_widget_definition

--! Displays a WML message box with attributes from table @attr and options
--! from table @options.
--! @return the index of the selected option.
--! @code
--! local result = helper.get_user_choice({ speaker = "narrator" },
--!     { "Choice 1", "Choice 2" })
--! @endcode
function helper.get_user_choice(attr, options)
	local result = 0
	function wesnoth.__user_choice_helper(i)
		result = i
	end
	local msg = {}
	for k,v in pairs(attr) do
		msg[k] = attr[k]
	end
	for k,v in ipairs(options) do
		table.insert(msg, wml.tag.option, { message = v,
			wml.tag.command, { wml.tag.lua, {
				code = string.format("wesnoth.__user_choice_helper(%d)", k)
			}}})
	end
	wml_actions.message(msg)
	wesnoth.__user_choice_helper = nil
	return result
end

-- Some C++ functions are deprecated; apply the messages here.
-- Note: It must happen AFTER the C++ functions are reassigned above to their new location.
-- These deprecated functions will probably never be removed.
if wesnoth.kernel_type() == "Game Lua Kernel" then
	wesnoth.get_variable = wesnoth.deprecate_api('wesnoth.get_variable', 'wml.variable.get', 1, nil, wesnoth.get_variable)
	wesnoth.set_variable = wesnoth.deprecate_api('wesnoth.set_variable', 'wml.variable.set', 1, nil, wesnoth.set_variable)
	wesnoth.get_all_vars = wesnoth.deprecate_api('wesnoth.get_all_vars', 'wml.variable.get_all', 1, nil, wesnoth.get_all_vars)
	-- Interface module
	wesnoth.delay = wesnoth.deprecate_api('wesnoth.delay', 'wesnoth.intf.delay', 1, nil, wesnoth.intf.delay)
	wesnoth.float_label = wesnoth.deprecate_api('wesnoth.float_label', 'wesnoth.intf.float_label', 1, nil, wesnoth.intf.float_label)
	wesnoth.select_unit = wesnoth.deprecate_api('wesnoth.select_unit', 'wesnoth.intf.select_unit', 1, nil, wesnoth.intf.select_unit)
	wesnoth.highlight_hex = wesnoth.deprecate_api('wesnoth.highlight_hex', 'wesnoth.intf.highlight_hex', 1, nil, wesnoth.intf.highlight_hex)
	wesnoth.deselect_hex = wesnoth.deprecate_api('wesnoth.deselect_hex', 'wesnoth.intf.deselect_hex', 1, nil, wesnoth.intf.deselect_hex)
	wesnoth.get_selected_tile = wesnoth.deprecate_api('wesnoth.get_selected_tile', 'wesnoth.intf.get_selected_hex', 1, nil, wesnoth.intf.get_selected_)
	wesnoth.scroll_to_tile = wesnoth.deprecate_api('wesnoth.scroll_to_tile', 'wesnot.intf.scroll_to_hex', 1, nil, wesnoth.intf.scroll_to_hex)
	wesnoth.lock_view = wesnoth.deprecate_api('wesnoth.lock_view', 'wesnoth.intf.lock', 1, nil, wesnoth.intf.lock)
	wesnoth.view_locked = wesnoth.deprecate_api('wesnoth.view_locked', 'wesnoth.intf.is_locked', 1, nil, wesnoth.intf.is_locked)
	wesnoth.is_skipping_messages = wesnoth.deprecate_api('wesnoth.is_skipping_messages', 'wesnoth.intf.is_skipping_messages', 1, nil, wesnoth.intf.is_skipping_messages)
	wesnoth.skip_messages = wesnoth.deprecate_api('wesnoth.skip_messages', 'wesnoth.intf.skip_messages', 1, nil, wesnoth.intf.skip_messages)
	wesnoth.add_tile_overlay = wesnoth.deprecate_api('wesnoth.add_tile_overlay', 'wesnoth.intf.add_hex_overlay', 1, nil, wesnoth.intf.add_hex_overlay)
	wesnoth.remove_tile_overlay = wesnoth.deprecate_api('wesnoth.remove_tile_overlay', 'wesnoth.intf.remove_hex_overlay', 1, nil, wesnoth.intf.remove_hex_overlay)
	wesnoth.theme_items = wesnoth.deprecate_api('wesnoth.theme_items', 'wesnoth.intf.game_display', 1, nil, wesnoth.intf.game_display)
	wesnoth.get_displayed_unit = wesnoth.deprecate_api('wesnoth.get_displayed_unit', 'wesnoth.intf.get_displayed_unit', 1, nil, wesnoth.intf.get_displayed_unit)
	wesnoth.gamestate_inspector = wesnoth.deprecate_api('wesnoth.gamestate_inspector', 'wesnoth.intf.show_inspector', 1, nil, wesnoth.intf.show_inspector)
	-- Units module
	wesnoth.match_unit = wesnoth.deprecate_api('wesnoth.match_unit', 'wesnoth.units.matches', 1, nil, wesnoth.units.matches)
	wesnoth.put_recall_unit = wesnoth.deprecate_api('wesnoth.put_recall_unit', 'wesnoth.units.to_recall', 1, nil, wesnoth.units.to_recall)
	wesnoth.put_unit = wesnoth.deprecate_api('wesnoth.put_unit', 'wesnoth.units.to_map', 1, nil, wesnoth.units.to_map)
	wesnoth.erase_unit = wesnoth.deprecate_api('wesnoth.erase_unit', 'wesnoth.units.erase', 1, nil, wesnoth.units.erase)
	wesnoth.copy_unit = wesnoth.deprecate_api('wesnoth.copy_unit', 'wesnoth.units.clone', 1, nil, wesnoth.units.clone)
	wesnoth.extract_unit = wesnoth.deprecate_api('wesnoth.extract_unit', 'wesnoth.units.extract', 1, nil, wesnoth.units.extract)
	wesnoth.advance_unit = wesnoth.deprecate_api('wesnoth.advance_unit', 'wesnoth.units.advance', 1, nil, wesnoth.units.advance)
	wesnoth.add_modification = wesnoth.deprecate_api('wesnoth.add_modification', 'wesnoth.units.add_modification', 1, nil, wesnoth.units.add_modification)
	wesnoth.remove_modifications = wesnoth.deprecate_api('wesnoth.remove_modifications', 'wesnoth.units.remove_modifications', 1, nil, wesnoth.units.remove_modifications)
	wesnoth.unit_resistance = wesnoth.deprecate_api('wesnoth.unit_resistance', 'wesnoth.units.resistance', 1, nil, wesnoth.units.resistance)
	wesnoth.unit_defense = wesnoth.deprecate_api('wesnoth.unit_defense', 'wesnoth.units.defense', 1, nil, wesnoth.units.defense)
	wesnoth.unit_movement_cost = wesnoth.deprecate_api('wesnoth.unit_movement_cost', 'wesnoth.units.movement', 1, nil, wesnoth.units.movement)
	wesnoth.unit_vision_cost = wesnoth.deprecate_api('wesnoth.unit_vision_cost', 'wesnoth.units.vision', 1, nil, wesnoth.units.vision)
	wesnoth.unit_jamming_cost = wesnoth.deprecate_api('wesnoth.unit_jamming_cost', 'wesnoth.units.jamming', 1, nil, wesnoth.units.jamming)
	wesnoth.unit_ability = wesnoth.deprecate_api('wesnoth.unit_ability', 'wesnoth.units.ability', 1, nil, wesnoth.units.ability)
	wesnoth.transform_unit = wesnoth.deprecate_api('wesnoth.transform_unit', 'wesnoth.units.transform', 1, nil, wesnoth.units.transform)
	wesnoth.select_unit = wesnoth.deprecate_api('wesnoth.select_unit', 'wesnoth.units.select', 1, nil, wesnoth.units.select)
end
wesnoth.tovconfig = wesnoth.deprecate_api('wesnoth.tovconfig', 'wml.tovconfig', 1, nil, wesnoth.tovconfig)
wesnoth.debug = wesnoth.deprecate_api('wesnoth.debug', 'wml.tostring', 1, nil, wesnoth.debug)
-- GUI module
wesnoth.show_menu = wesnoth.deprecate_api('wesnoth.show_menu', 'gui.show_menu', 1, nil, gui.show_menu)
wesnoth.show_message_dialog = wesnoth.deprecate_api('wesnoth.show_message_dialog', 'gui.show_speech', 1, nil, gui.show_speech)
wesnoth.show_popup_dialog = wesnoth.deprecate_api('wesnoth.show_popup_dialog', 'gui.show_popup', 1, nil, gui.show_popup)
wesnoth.show_story = wesnoth.deprecate_api('wesnoth.show_story', 'gui.show_story', 1, nil, gui.show_story)
wesnoth.show_message = wesnoth.deprecate_api('wesnoth.show_message', 'gui.show_message', 1, nil, gui.show_message)
wesnoth.alert = wesnoth.deprecate_api('wesnoth.alert', 'gui.alert', 1, nil, gui.alert)
wesnoth.confirm = wesnoth.deprecate_api('wesnoth.confirm', 'gui.confirm', 1, nil, gui.confirm)
wesnoth.show_lua_console = wesnoth.deprecate_api('wesnoth.show_lua_console', 'gui.show_lua_console', 1, nil, gui.show_lua_console)
wesnoth.show_dialog = wesnoth.deprecate_api('wesnoth.show_dialog', 'gui.dialog.show', 1, nil, gui.dialog.show)
wesnoth.get_dialog_value = wesnoth.deprecate_api('wesnoth.get_dialog_value', 'gui.dialog.get_value', 1, nil, gui.dialog.get_value)
wesnoth.set_dialog_value = wesnoth.deprecate_api('wesnoth.set_dialog_value', 'gui.dialog.set_value', 1, nil, gui.dialog.set_value)
wesnoth.set_dialog_visible = wesnoth.deprecate_api('wesnoth.set_dialog_visible', 'gui.dialog.set_visible', 1, nil, gui.dialog.set_visible)
wesnoth.set_dialog_callback = wesnoth.deprecate_api('wesnoth.set_dialog_callback', 'gui.dialog.set_callback', 1, nil, gui.dialog.set_callback)
wesnoth.set_dialog_active = wesnoth.deprecate_api('wesnoth.set_dialog_active', 'gui.dialog.set_active', 1, nil, gui.dialog.set_active)
wesnoth.set_dialog_canvas = wesnoth.deprecate_api('wesnoth.set_dialog_canvas', 'gui.dialog.set_canvas', 1, nil, gui.dialog.set_canvas)
wensoth.set_dialog_focus = wesnoth.deprecate_api('wensoth.set_dialog_focus', 'gui.dialog.set_focus', 1, nil, gui.dialog.set_focus)
wesnoth.set_dialog_markup = wesnoth.deprecate_api('wesnoth.set_dialog_markup', 'gui.dialog.set_markup', 1, nil, gui.dialog.set_markup)
wesnoth.remove_dialog_item = wesnoth.deprecate_api('wesnoth.remove_dialog_item', 'gui.dialog.remove_item', 1, nil, gui.dialog.remove_item)
wesnoth.add_dialog_tree_node = wesnoth.deprecate_api('wesnoth.add_dialog_tree_node', 'gui.dialog.add_tree_node', 1, nil, gui.dialog.add_tree_node)
wesnoth.add_widget_definition = wesnoth.deprecate_api('wesnoth.add_widget_definition', 'gui.dialog.add_widget_definition', 1, nil, gui.dialog.add_widget_definition)
