
local dbus = {
    property = {},
    raw = require("lua-dbus.awesome.init"),
--     interface = require("lua-dbus.interface"),
    signals = { system = {}, session = {} },
}

if awesome then
    local function noop() end
    dbus.init = noop
    dbus.poll = noop
    dbus.exit = noop
else
    dbus.init = dbus.raw.init
    dbus.poll = dbus.raw.poll
    dbus.exit = dbus.raw.exit
end

function dbus.signal_handler(signal, ...)
    signal.events = ((dbus.signals[signal.bus] or {})[signal.interface] or {}).events
    if not signal.events then return end
    for _, callback in ipairs(signal.events[signal.member] or {}) do
        if type(callback) == 'table' then
            callback = callback.handler
        end
        callback(...)
    end
    if signal.type == 'signal' then
        for _, event in pairs(signal.events) do
            if event.name == signal.member and event.owner == signal.sender then
                for _, callback in ipairs(event) do
                    if type(callback) == 'table' then
                        callback = callback.handler
                    end
                    callback(...)
                end
                break
            end
        end
    end
end

function dbus.owner(iface, callback, opts)
    opts = opts or {}
    return dbus.call('GetNameOwner', callback, { args = {'s', iface},
        path = '/',
        bus  = opts.bus, type = opts.type,
        destination = 'org.freedesktop.DBus',
        interface   = 'org.freedesktop.DBus',
    })
end


function dbus.on(name, callback, opts)
    if type(name) == 'table' then
        name, callback, opts = '', nil, name
    elseif callback and type(callback) ~= 'function' then
        callback, opts = nil, callback
    end
    opts = opts or {}
    opts.type = opts.type or "signal"
    opts.bus = opts.bus or "session"
    callback = callback or opts.callback
    if not opts.interface then error("opts.interface is missing!") end
    local  signal = dbus.signals[opts.bus][opts.interface]
    if not signal then
        signal = {
            len = 0,
            type = opts.type,
            interface = opts.interface,
            handler = opts.handler or dbus.signal_handler,
        }
        if not opts.handler then signal.events = {} end
        dbus.raw.connect_signal(signal.interface, signal.handler)
        dbus.signals[opts.bus][signal.interface] = signal
    end
    if signal.events then
        local evname = name
        if opts.sender then
            evname = evname .. opts.sender
        end
        local  event = signal.events[evname]
        if not event then
            event = { name = name, match = string.format(
                "type='%s',interface='%s',member='%s'",
                opts.type, signal.interface, name)}
            if opts.destination then
                event.match = string.format(
                    "%s,destination='%s'",
                    event.match, opts.destination)
            end
            if opts.sender then
                event.owner = opts.sender
                event.match = string.format(
                    "sender='%s',%s",
                    opts.sender, event.match)
            end
            signal.events[evname] = event
            signal.len = signal.len + 1
            dbus.raw.add_match(opts.bus, event.match)
        end
        if callback then
            if opts.origin then
                table.insert(event, {
                    handler = callback,
                    origin = opts.origin,
                })
            else
                table.insert(event, callback)
            end
        end
    end
end


function dbus.off(name, callback, opts)
    opts = opts or {}
    opts.type = opts.type or "signal"
    opts.bus = opts.bus or "session"
    local signal = (dbus.signals[opts.bus] or {})[opts.interface]
    if not signal or signal.type ~= opts.type then return false end
    if not signal.events then
        if signal.handler == callback then
            dbus.raw.disconnect_signal(signal.interface, signal.handler)
            dbus.signals[opts.bus][signal.interface] = nil
            return true
        end
        return false
    end
    local event = signal.events[name]
    if not event then return false end
    for i, cb in ipairs(event) do
        if type(cb) == 'table' then cb = cb.origin end
        if cb == callback then
            table.remove(event, i)
            if #event == 0 then
                dbus.raw.remove_match(opts.bus, event.match)
                signal.events[name] = nil
                signal.len = signal.len - 1
                if signal.len == 0 then
                    dbus.raw.disconnect_signal(signal.interface,signal.handler)
                    dbus.signals[opts.bus][signal.interface] = nil

                end
            end
            return true
        end
    end
    return false
end


function dbus.call(name, callback, opts)
    if not dbus.raw.call_method then return end
    if callback and type(callback) ~= 'function' then
        callback, opts = nil, callback
    end
    opts = opts or {}
    opts.type = opts.type or "method_call"
    opts.bus = opts.bus or "session"
    callback = callback or opts.callback
    local serial = dbus.raw.call_method(opts.bus,
        opts.destination, opts.path, opts.interface, name,
        unpack(opts.args or {}))
    if callback and type(serial) == 'number' then
        local key = string.format("reply %d", serial)
        local params = {
            interface = key,
            type = opts.type,
            bus = opts.bus,
        }
        params.handler = function (_, ...)
            dbus.off(key, params.handler, params)
            callback(...)
        end
        dbus.on(key, params.handler, params)
    end
    return serial
end


function dbus.property.get(name, callback, opts)
    opts = opts or {}
    opts.args = {'s', opts.interface, 's', name} -- actual arguments to Get
    opts.interface = 'org.freedesktop.DBus.Properties'
    callback = callback or opts.callback
    return dbus.call('Get', callback, opts)
end


function dbus.property.set(name, value, opts)
    opts = opts or {}
    opts.args = {'s', opts.interface, 's', name, 'v', value} -- actual arguments to Get
    opts.interface = 'org.freedesktop.DBus.Properties'
    return dbus.call('Set', opts)
end


function dbus.property.on(name, callback, opts)
    opts = opts or {}
    return dbus.on('PropertiesChanged', function (iface, values)
        if iface == opts.interface then
            local value = values[name]
            if value ~= nil then
                callback(value)
            end
        end
    end, {
        origin = callback,
        bus = opts.bus, type = opts.type,
        sender = opts.sender, destination = opts.destination,
        interface = 'org.freedesktop.DBus.Properties',
    })
end


function dbus.property.off(name, callback, opts)
    return dbus.off('PropertiesChanged', callback, {
        bus = opts.bus, type = opts.type,
        interface = 'org.freedesktop.DBus.Properties',
    })
end


return dbus
