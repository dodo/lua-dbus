local dbus = require("lua-dbus.init")


local function createinstance(meta, ...)
    local instance = setmetatable({}, meta)
    if instance.init then instance:init(...) end
    return instance
end


local Interface = { new = createinstance }
Interface.__index = Interface

function Interface:init(opts)
    opts = opts or {}
    self.bus = opts.bus or 'session'
    self.paths = {}
    self.name = opts.name
    if self.name then
        dbus.raw.request_name(self.bus, self.name)
    end
end

-- opts: interface, path='/', methods={}, signals={}, properties={}
function Interface:add(opts)
    opts = opts or {}
    if not opts.interface then return end
    opts.path = opts.path or '/'
    local path = self.paths[opts.path] or {}
    self.paths[opts.path] = path
    if not path.introspection then
        path.introspection = true
        self:_introspection(opts)
    end
    local iface = path[opts.interface] or {}
    path[opts.interface] = iface
    iface.methods = iface.methods or {}
    for method, args in pairs(opts.methods or {}) do
        iface.methods[method] = args
    end
    iface.signals = iface.signals or {}
    for name, args in pairs(opts.signals or {}) do
        iface.signals[name] = args
    end
    local hasproperties = false
    iface.properties = iface.properties or {}
    for name, property in pairs(opts.properties or {}) do
        iface.properties[name] = property
        hasproperties = true
    end
    if not path.properties then
        path.properties = true
        self:_properties(opts)
    end
    local iface = self
    dbus.on({ bus = self.bus, interface = opts.interface,
        handler = function (sig, ...)
            if sig.type ~= 'method_call' then return end
            local interface = iface.paths[opts.path][sig.interface]
            if not interface then return end
            local method = (interface.methods or {})[sig.member]
            if method and method.callback then
                local i, result, ret = 1, {}, {method.callback(sig, ...)}
                if not method.result then
                    result = ret
                else
                    -- prepare callback results with actual interface result types
                    for j=1,#method.result,2 do
                        table.insert(result, method.result[j]) -- type
                        table.insert(result, ret[i]) -- value
                        i = i + 1
                    end
                end
                return unpack(result)
            end
        end,
    })
end

local function introspect(iface, path, header)
local xml = header ~= false and
[[<!DOCTYPE node PUBLIC "-//freedesktop//DTD D-BUS Object Introspection 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/introspect.dtd">]] or ""

    if path == "/" then
        xml = xml .. "<node>"
        xml = xml .. introspect(iface, nil, false)
        for facepath, interfaces in pairs(iface.paths or {}) do
            xml = xml .. string.format([[<node name="%s"/>]], string.sub(facepath, 2))
        end
        xml = xml .. "</node>"
        return xml
    end

    local interfaces = iface.paths and iface.paths[path or "/"]
    if interfaces then
        if path then
            xml = xml .. string.format([[<node name="%s">]], path)
        end
        for name, interface in pairs(interfaces) do
            if name ~= 'introspection' and name ~= 'properties' then
                xml = xml .. string.format([[<interface name="%s">]], name)
                for method, args in pairs(interface.methods) do
                    xml = xml .. string.format([[<method name="%s">]], method)
                    for i = 1, #args, 2 do
                        xml = xml .. string.format(
                            [[<arg name="%s" type="%s" direction="%s"/>]],
                            args[i+1], args[i], 'in')
                    end
                    if args.result then
                        for i = 1, #args.result, 2 do
                            xml = xml .. string.format(
                                [[<arg name="%s" type="%s" direction="%s"/>]],
                                args.result[i+1], args.result[i], 'out')
                        end
                    end
                    xml = xml .. "</method>"
                end
                for name, args in pairs(interface.signals) do
                    xml = xml .. string.format([[<signal name="%s">]], name)
                    for i = 1, #args, 2 do
                        xml = xml .. string.format(
                            [[<arg name="%s" type="%s"/>]],
                            args[i+1], args[i])
                    end
                    xml = xml .. "</signal>"
                end
                for name, property in pairs(interface.properties) do
                    local access = 'read'
                    if property.read and property.write then
                        access = 'readwrite'
                    elseif property.write then
                        access = 'write'
                    end
                    xml = xml .. string.format(
                        [[<property name="%s" type="%s" access="%s"/>]],
                        name, property.type, access)
                end
                xml = xml .. "</interface>"
            end
        end
        if path then
            xml = xml .. "</node>"
        end
    end
    return xml
end
Interface.introspect = introspect

function Interface:_introspection(opts)
    local iface = self
    self:add({
        interface = 'org.freedesktop.DBus.Introspectable',
        path = opts.path,
        methods = {
            Introspect = {
                result = {'s', "data"},
                callback = function (sig) return introspect(iface, sig.path) end,
            },
        },
    })
end

function Interface:_properties(opts)
    local iface = self
    self:add({
        interface = 'org.freedesktop.DBus.Properties',
        path = opts.path,
        methods = {
            Get = { 's', "interface", 's', "name",
                result = {'v', "value"},
                callback = function (sig, interface, name)
                    local interfaces = iface.paths and iface.paths[sig.path or "/"]
                    local face = interfaces and interfaces[interface]
                    if face and face.properties then
                        local property = face.properties[name]
                        if property and property.read then
                            return property.read()
                        end
                    end
                end,
            },
            GetAll = { 's', "interface",
                result = {'a{sv}', "values"},
                callback = function (sig, interface)
                    local interfaces = iface.paths and iface.paths[sig.path or "/"]
                    local face = interfaces and interfaces[interface]
                    local values = {}
                    if face and face.properties then
                        for name, property in pairs(face.properties) do
                            if property.read then
                                values[name] = property.read()
                            end
                        end
                    end
                    return values
                end,
            },
            Set = { 's', "interface", 's', "name", 'v', "value",
                callback = function (sig, interface, name, value)
                    local interfaces = iface.paths and iface.paths[sig.path or "/"]
                    local face = interfaces and interfaces[interface]
                    if face and face.properties then
                        local property = face.properties[name]
                        if property and property.write then
                            return property.write(value)
                        end
                    end
                end,
            },
        },
        signals = {
            PropertiesChanged = {
                's', "interface", 'a{sv}', "values", 'as', "keys"
            },
        },
    })
end

function Interface:properties(keys, values, opts)
    opts = opts or {}
    dbus.raw.emit_signal(self.bus, opts.path,
        'org.freedesktop.DBus.Properties', 'PropertiesChanged',
        's', opts.interface, 'a{sv}', values, 'as', keys)
end

function Interface:property(name, value, opts)
    local values = {}
    values[name] = value
    self:properties({name}, values, opts)
end


return Interface
