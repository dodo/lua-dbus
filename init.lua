
local dbus = {
    raw = require("lua-dbus.awesome"),
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
        callback(...)
    end
end

function dbus.on(name, callback, opts)
    opts = opts or {}
    opts.type = opts.type or "signal"
    opts.bus = opts.bus or "session"
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
        local  event = signal.events[name]
        if not event then
            event = { match = string.format(
                "type='%s',interface='%s',member='%s'",
                opts.type, signal.interface, name)}
            signal.events[name] = event
            signal.len = signal.len + 1
            dbus.raw.add_match(opts.bus, event.match)
        end
        table.insert(event, callback)
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
    if type(callback) ~= 'function' then
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


return dbus
