-- implementing awesome dbus api with ldbus

local ldbus = require "ldbus"
ldbus.basic_types.double = 'd'
ldbus.types.double = 'd'

local dbus = {}

-- dbus loop

function dbus.init()
    dbus.signals = {}
    dbus.callbacks = {}
    dbus.session = ldbus.bus.get('session')
    dbus.system  = ldbus.bus.get('system')
end

function dbus.exit()
    dbus.signals = nil
    dbus.session = nil
    dbus.system  = nil
end

function dbus.poll()
    local ok = false
    for _, name in ipairs({'system', 'session'}) do
        local had_messages = false
        while dbus.process_request(dbus.poll_bus(name, dbus[name])) do
            had_messages = true
            ok = true
        end
        if had_messages then dbus[name]:flush() end
    end
    return ok
end

function dbus.poll_bus(bus_name, bus)
    if not bus then return end
    if bus:read_write(0) then
        local msg = bus:pop_message()
        if msg then
            local ret = { bus = bus, message = msg }
            ret.signal = {
                bus = bus_name,
                type = msg:get_type(),
                path = msg:get_path(),
                member = msg:get_member(),
                sender = msg:get_sender(),
                serial = msg:get_serial(),
                reply = msg:get_reply_serial(),
                signature = msg:get_signature(),
                interface = msg:get_interface(),
                destination = msg:get_destination(),
            }
            ret.iter = msg:iter_init()
            ret.args = dbus.iter_args(ret.iter)
            return ret
        end
    end
end

function dbus.process_request(req)
    if not req then return end
    if req.signal.reply > 0 then
        local callback = dbus.callbacks[req.signal.reply]
        local key = string.format("reply %d", req.signal.reply)
        for _, signal in ipairs(dbus.signals) do
            if signal.name == key then
                signal.callback(req.signal, unpack(req.args))
            end
        end
    end
    if req.message:get_no_reply() then
        for _, signal in ipairs(dbus.signals) do
            if signal.name == req.signal.interface then
                signal.callback(req.signal, unpack(req.args))
            end
        end
    else
        for _, signal in ipairs(dbus.signals) do
            if signal.name == req.signal.interface then
                local ret = {signal.callback(req.signal, unpack(req.args))}
                local reply = req.message:new_method_return()
                local iter
                if req.iter then
                    iter = reply:iter_init_append(req.iter)
                else
                    iter = reply:iter_init_append()
                end

                for i=1,#ret,2 do
                    local typ, val = ret[i], ret[i+1]
                    if typ and val ~= nil then
                        dbus.append_arg(iter, val, typ)
                    end
                end
                req.bus:send(reply)
                return true -- there can be only ONE handler to send reply
            end
        end
    end
    return true
end

function dbus.iter_args(iter, args_dst)
    local args = args_dst or {}
    if not iter then return args end
    local typ = iter:get_arg_type()

    while typ do
        local nextval = {}
        if typ == ldbus.types.array then
            local arr_typ = iter:get_element_type()
            if arr_typ == ldbus.types.dict_entry then
                local arr_it = iter:recurse()
                while arr_it:get_arg_type() do
                    local de_it = arr_it:recurse()
                    --assert (dbus.raw.set_of_basic_types[de_it:get_arg_type()])
                    local key = de_it:get_basic()
                    --assert (de_it:has_next()) --value is mandatory
                    de_it:next()
                    local val = dbus.iter_args(de_it)
                    --assert(#val <= 1) --recursing on one dbus type
                    nextval[key] = val[1]
                    --assert (not de_it:has_next())
                    arr_it:next()
                end
            elseif arr_typ then
                local arr_it = iter:recurse()
                while arr_it:get_arg_type() do
                    -- more than one type can be returned, direct "nextval" write
                    dbus.iter_args(arr_it, nextval)
                    arr_it:next()
                end
            end
        elseif typ == ldbus.types.variant then
            local val = dbus.iter_args(iter:recurse())
            --assert(#val <= 1) --recursing on only one dbus type
            nextval = val[1]
        elseif typ == ldbus.types.struct then
            --struct representation is an array of "n" values
            nextval = dbus.iter_args(iter:recurse())
        else
            nextval = iter:get_basic()
        end
        table.insert(args, nextval)
        iter:next()
        typ = iter:get_arg_type()
    end
    return args
end

function dbus.type(value)
    local luatyp, typ = type(value)
    if luatyp == 'boolean' then
        typ = ldbus.types.boolean
    elseif luatyp == 'string' then
        typ = ldbus.types.string
    elseif luatyp == 'number' then
        typ = ldbus.types.double
    elseif luatyp == 'table' then
        if #value > 0 then
            local subtyp = dbus.type(value[1])
            for i = 2, #value do
                if subtyp ~= dbus.type(value[i]) then
                    subtyp = ldbus.types.variant
                    break
                end
            end
            typ = 'a' .. subtyp
        else
            typ = 'a{sv}'
        end
    end
    return typ
end

dbus.set_of_basic_types = {}
for _, v in pairs (ldbus.basic_types) do
    dbus.set_of_basic_types[v] = true
end

dbus.variant_mt = {}
function dbus.new_variant(vtype, value)
    assert(value)
    vtype = vtype or dbus.type(value)
    return setmetatable ({ t = vtype, v = value }, dbus.variant_mt)
end

function dbus.consume_type(dtype)
    if not dtype then
        return nil
    end
    local fchar = dtype:sub(1, 1)
    if fchar == "{" then
        assert(dtype:sub(-1) == "}")
        return ldbus.types.dict_entry, dtype:sub(2, -2)
    elseif dbus.set_of_basic_types[fchar] or fchar == ldbus.types.array then
        return fchar, dtype:sub(2)
    elseif fchar == ldbus.types.variant then
        return fchar, nil -- The type of a variant can't be detected
    end
    error("structs unimplemented for now, type: "..dtype, 2)
end

local function error_on(condition, text, lvl)
    if condition then
        error(text, lvl and lvl + 1 or 2)
    end
end

function dbus.append_arg(iter, value, dbus_type)
    local dt, dt_next = dbus.consume_type(dbus_type)
    if dbus.set_of_basic_types[dt] then
        error_on(type(value) == "table", "expected a basic type, got a table")
        iter:append_basic(value, dt)
    elseif dt == ldbus.types.array then
        error_on(type(value) ~= "table", "expected a table")
        local arr_iter            = iter:open_container(dt, dt_next)
        local arr_dt, arr_dt_next = dbus.consume_type(dt_next)
        if arr_dt == ldbus.types.dict_entry then
             local key_dt, value_dt = dbus.consume_type(arr_dt_next)
             error_on(
                dbus.set_of_basic_types[key_dt] == nil,
                "the key of a dict entry has to be a basic type"
                )
            for k, v in pairs(value) do
                 local dict_iter = arr_iter:open_container(arr_dt)
                 dict_iter:append_basic(k, key_dt)
                 dbus.append_arg(dict_iter, v, value_dt)
                 arr_iter:close_container(dict_iter)
            end
        else
            for _, v in ipairs(value) do
                 dbus.append_arg(arr_iter, v, dt_next)
            end
        end
        iter:close_container(arr_iter)
    elseif dt == ldbus.types.variant then
        local val, var_dt
        if type(value) == "table" and
                getmetatable(value) == dbus.variant_mt then
            val    = value.v
            var_dt = value.t
        else
            val    = value
            var_dt = dbus.type(value)
        end
        local var_iter = iter:open_container(dt, var_dt)
        dbus.append_arg(var_iter, val, var_dt)
        iter:close_container(var_iter)
    else
        error_on(dt == ldbus.types.dict_entry, "dict_entry outside of array")
        error_on(dt == ldbus.types.struct, "structs are unsupported")
    end
end

function dbus.get_bus(name)
    if name == 'session' then
        return dbus.session
    elseif name == 'system' then
        return dbus.system
    end
end

-- awesome dbus api

function dbus.request_name(bus_name, name)
    local bus = dbus.get_bus(bus_name)
    if not bus then return end
    return ({
        primary_owner = true,
        already_owner = true,
    })[ldbus.bus.request_name(bus, name)] or false
end

function dbus.release_name(bus_name, name)
    local bus = dbus.get_bus(bus_name)
    if not bus then return end
    return ldbus.bus.release_name(bus, name) == 'released'
end

function dbus.add_match(bus_name, name)
    local bus = dbus.get_bus(bus_name)
    if not bus then return end
    ldbus.bus.add_match(bus, name)
    bus:flush()
end

function dbus.remove_match(bus_name, name)
    local bus = dbus.get_bus(bus_name)
    if not bus then return end
    ldbus.bus.remove_match(bus, name)
    bus:flush()
end

function dbus.connect_signal(name, callback)
    table.insert(dbus.signals, {name = name, callback = callback})
end

function dbus.disconnect_signal(name, callback)
    for i, signal in ipairs(dbus.signals) do
        if signal.name == name and signal.callback == callback then
            table.remove(dbus.signals, i)
            return
        end
    end
end

function dbus.emit_signal(bus_name, path, iface, name, ...)
    local args = {...}
    local bus = dbus.get_bus(bus_name)
    if not bus then return false end
    local msg = ldbus.message.new_signal(path, iface, name)
    if not msg then return false end
    local iter = msg:iter_init_append()
    if not iter then return false end
    for i=1,#args,2 do
        local typ, val = args[i], args[i+1]
        if typ and val then
            dbus.append_arg(iter, val, typ)
        end
    end
    local ok = bus:send(msg)
    bus:flush()
    return ok
end

function dbus.call_method(bus_name, dest, path, iface, method, ...)
    local args = {...}
    local bus = dbus.get_bus(bus_name)
    if not bus then return false end
    local msg = ldbus.message.new_method_call(dest, path, iface, method)
    if not msg then return false end
    local iter = msg:iter_init_append()
    if not iter then return false end
    for i=1,#args,2 do
        local typ, val = args[i], args[i+1]
        if typ and val then
            dbus.append_arg(iter, val, typ)
        end
    end
    local ok, serial = bus:send(msg)
    bus:flush()
    return ok and serial or 0
end


return dbus
