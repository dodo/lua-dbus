# [lua-dbus](https://github.com/dodo/lua-dbus)

Convenient dbus api in lua.

Works in [awesome](https://awesome.naquadah.org/) or with [ldbus](https://github.com/dodo/ldbus/).

## usage

```lua
local dbus = require 'lua-dbus'

if not awesome then dbus.init() end


local function on_signal (...)
    -- react on signal here
end

local signal_opts = {
    bus = 'session' or 'system',
    interface = 'org.freedesktop.DBus', -- or something appropriate ;)
}
-- add signal handler
dbus.on('Signal', on_signal, signal_opts)

-- remove signal handler
dbus.off('Signal', on_signal, signal_opts)

-- call a method
dbus.call('Method', function (...)
    -- react on method return results here
end, {
    bus = 'session' or 'system',
    path = '/some/dbus/path', -- change this!
    interface = signal_opts.interface,
    -- just luckily matches here for demonstration purpose
    destination = signal_opts.interface,
})


-- when running
if not awesome then
    while true do
        dbus.poll()
    end
end

-- when you're done
if not awesome then dbus.exit() end
```
