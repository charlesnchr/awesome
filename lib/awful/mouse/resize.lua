---------------------------------------------------------------------------
--- An extensible mouse resizing handler.
--
-- This module offers a resizing and moving mechanism for drawables such as
-- clients and wiboxes.
--
-- @author Emmanuel Lepage Vallee &lt;elv1313@gmail.com&gt;
-- @copyright 2016 Emmanuel Lepage Vallee
-- @submodule mouse
---------------------------------------------------------------------------

local aplace = require("awful.placement")
local capi = {mousegrabber = mousegrabber, client = client}
local beautiful = require("beautiful")
local floating = require("awful.layout.suit.floating")

local module = {}

local mode      = "live"
local req       = "request::geometry"
local callbacks = {enter={}, move={}, leave={}}
local math = math

local cursors = {
    ["mouse.move"               ] = "fleur",
    ["mouse.resize"             ] = "cross",
    ["mouse.resize_left"        ] = "sb_h_double_arrow",
    ["mouse.resize_right"       ] = "sb_h_double_arrow",
    ["mouse.resize_top"         ] = "sb_v_double_arrow",
    ["mouse.resize_bottom"      ] = "sb_v_double_arrow",
    ["mouse.resize_top_left"    ] = "top_left_corner",
    ["mouse.resize_top_right"   ] = "top_right_corner",
    ["mouse.resize_bottom_left" ] = "bottom_left_corner",
    ["mouse.resize_bottom_right"] = "bottom_right_corner",
}

--- The resize cursor name.
-- @beautiful beautiful.cursor_mouse_resize
-- @tparam[opt=cross] string cursor

--- The move cursor name.
-- @beautiful beautiful.cursor_mouse_move
-- @tparam[opt=fleur] string cursor

--- Set the resize mode.
-- The available modes are:
--
-- * **live**: Resize the layout everytime the mouse moves.
-- * **after**: Resize the layout only when the mouse is released.
--
-- Some clients, such as XTerm, may lose information if resized too often.
--
-- @function awful.mouse.resize.set_mode
-- @tparam string m The mode
function module.set_mode(m)
    assert(m == "live" or m == "after")
    mode = m
end

--- Add an initialization callback.
-- This callback will be executed before the mouse grabbing starts.
-- @function awful.mouse.resize.add_enter_callback
-- @tparam function cb The callback (or nil)
-- @tparam[default=other] string context The callback context
function module.add_enter_callback(cb, context)
    context = context or "other"
    callbacks.enter[context] = callbacks.enter[context] or {}
    table.insert(callbacks.enter[context], cb)
end

--- Add a "move" callback.
-- This callback is executed in "after" mode (see `set_mode`) instead of
-- applying the operation.
-- @function awful.mouse.resize.add_move_callback
-- @tparam function cb The callback (or nil)
-- @tparam[default=other] string context The callback context
function module.add_move_callback(cb, context)
    context = context or  "other"
    callbacks.move[context] = callbacks.move[context]  or {}
    table.insert(callbacks.move[context], cb)
end

--- Add a "leave" callback
-- This callback is executed just before the `mousegrabber` stop
-- @function awful.mouse.resize.add_leave_callback
-- @tparam function cb The callback (or nil)
-- @tparam[default=other] string context The callback context
function module.add_leave_callback(cb, context)
    context = context or  "other"
    callbacks.leave[context] = callbacks.leave[context]  or {}
    table.insert(callbacks.leave[context], cb)
end

-- convenience printing for debug
function dump(o)
   if type(o) == 'table' then
      local s = '{ '
      for k,v in pairs(o) do
         if type(k) ~= 'number' then k = '"'..k..'"' end
         s = s .. '['..k..'] = ' .. dump(v) .. ','
      end
      return s .. '} '
   else
      return tostring(o)
   end
end

-- get coordinates
local resize_coordinates = {
    -- Corners
    top_left     = {0,0},
    top_right    = {1,0},
    bottom_left  = {0,1},
    bottom_right = {1,1},

    -- Sides
    left         = {0,0.5},
    right        = {1,0.5},
    top          = {0.5,0},
    bottom       = {0.5,1},
}

-- Convert a rectangle and matrix info into a point
local function rect_to_point(rect, corner_i, corner_j)
    return {
        x = rect.x + corner_i * math.floor(rect.width ),
        y = rect.y + corner_j * math.floor(rect.height),
    }
end

--- Resize the drawable.
--
-- Valid `args` are:
--
-- * *enter_callback*: A function called before the `mousegrabber` starts.
-- * *move_callback*: A function called when the mouse moves.
-- * *leave_callback*: A function called before the `mousegrabber` is released.
-- * *mode*: The resize mode.
--
-- @function awful.mouse.resize
-- @tparam client client A client.
-- @tparam[default=mouse.resize] string context The resizing context.
-- @tparam[opt={}] table args A set of `awful.placement` arguments.
-- @request wibox geometry mouse.resize granted Requests to resize the wibox.
local function handler(_, client, context, args) --luacheck: no unused_args
    args = args or {}
    context = context or "mouse.resize"

    local placement = args.placement

    if type(placement) == "string" and aplace[placement] then
        placement = aplace[placement]
    end

    -- Extend the table with the default arguments
    args = setmetatable(
        {
            placement = placement or aplace.resize_to_mouse,
            mode      = args.mode or mode,
            pretend   = true,
        },
        {__index = args or {}}
    )

    local geo

    for _, cb in ipairs(callbacks.enter[context] or {}) do
        geo = cb(client, args)

        if geo == false then
            return false
        end
    end



    if args.enter_callback then
        geo = args.enter_callback(client, args)

        if geo == false then
            return false
        end
    end

    geo = nil

    -- Select the cursor
    local tcontext = context:gsub('[.]', '_')
    local corner = args.corner and ("_".. args.corner) or ""

    local cursor = beautiful["cursor_"..tcontext]
        or cursors[context..corner]
        or cursors[context]
        or "fleur"

    if context == "mouse.resize" then
        local pts = resize_coordinates[args.corner]
        local g = client:geometry()
        local p  = rect_to_point(g, pts[1], pts[2])

        local corner_x, corner_y = p.x, p.y
        local mouse_coords = args.mousecoords
        x = mouse_coords.x
        y = mouse_coords.y
        coordinates_delta = {x=corner_x-x,y=corner_y-y}
    end


    -- Execute the placement function and use request::geometry
    capi.mousegrabber.run(function (_mouse)
        if not client.valid then return end

        if context == "mouse.resize" then
            _mouse.x = _mouse.x + coordinates_delta.x
            _mouse.y = _mouse.y + coordinates_delta.y
        end

        -- Resize everytime the mouse moves (default behavior) in live mode,
        -- otherwise keep the current geometry
        geo = setmetatable(
            args.mode == "live" and args.placement(client, args) or client:geometry(),
            {__index=args}
        )

        -- Execute the move callbacks. This can be used to add features such as
        -- snap or adding fancy graphical effects.
        for _, cb in ipairs(callbacks.move[context] or {}) do
            -- If something is returned, assume it is a modified geometry
            geo = cb(client, geo, args) or geo

            if geo == false then
                return false
            end
        end

        if args.move_callback then
            geo = args.move_callback(client, geo, args)

            if geo == false then
                return false
            end
        end


        -- In case it was modified
        if geo then
            setmetatable(geo, {__index=args})
        end

        if args.mode == "live" then
            -- Ask the resizing handler to resize the client
            if context == "mouse.resize" then
                local corner = args.corner
                local g = client:geometry()

                if corner == "bottom_right" then
                    geo = { width = _mouse.x - g.x,
                    height = _mouse.y - g.y }
                elseif corner == "bottom_left" then
                    geo = { x = _mouse.x,
                    width = (g.x + g.width) - _mouse.x,
                    height = _mouse.y - g.y }
                elseif corner == "top_left" then
                    geo = { x = _mouse.x,
                    width = (g.x + g.width) - _mouse.x,
                    y = _mouse.y,
                    height = (g.y + g.height) - _mouse.y }
                else
                    geo = { width = _mouse.x - g.x,
                    y = _mouse.y,
                    height = (g.y + g.height) - _mouse.y }
                end
                if geo.width <= 10 then geo.width = 10 end
                if geo.height <= 10 then geo.height = 10 end
                -- if fixed_x then ng.width = g.width ng.x = g.x end
                -- if fixed_y then ng.height = g.height ng.y = g.y end
                -- c:geometry(ng)
            end

            client:emit_signal(req, context, geo)
        end

        -- Quit when the button is released
        for _,v in pairs(_mouse.buttons) do
            if v then return true end
        end

        -- Only resize after the mouse is released, this avoids losing content
        -- in resize sensitive apps such as XTerm or allows external modules
        -- to implement custom resizing.
        if args.mode == "after" then
            -- Get the new geometry
            geo = args.placement(client, args)

            -- Ask the resizing handler to resize the client
            client:emit_signal(req, context, geo)
        end

        geo = nil

        for _, cb in ipairs(callbacks.leave[context] or {}) do
            geo = cb(client, geo, args)
        end

        if args.leave_callback then
            geo = args.leave_callback(client, geo, args)
        end

        if not geo then return false end

        -- In case it was modified
        setmetatable(geo,{__index=args})

        client:emit_signal(req, context, geo)

        return false
    end, cursor)
end

function module._resize_handler(c, context, hints)
    if hints and context and context:find("mouse.*") then
        -- This handler only handle the floating clients. If the client is tiled,
        -- then it let the layouts handle it.
        local t = c.screen.selected_tag
        local lay = t and t.layout or nil

        if (lay and lay == floating) or c.floating then
            c:geometry {
                x      = hints.x,
                y      = hints.y,
                width  = hints.width,
                height = hints.height,
            }
        elseif lay and lay.resize_handler then
            lay.resize_handler(c, context, hints)
        end
    end
end

capi.client.connect_signal("request::geometry", module._resize_handler)

return setmetatable(module, {__call=handler})

-- vim: filetype=lua:expandtab:shiftwidth=4:tabstop=8:softtabstop=4:textwidth=80
