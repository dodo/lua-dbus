local dbus = require('lua-dbus')
local sleep = require('socket').sleep
print "init"
dbus.init()

print "listen"
-- dbus.on('StatusChanged', function (status, data)
--     if _it then
--         print('StatusChanged', status, require('util').dump(data))
--     else
--         print('StatusChanged', status, data)
--     end
-- end, { bus = 'system', interface = 'org.wicd.daemon' })

dbus.on('NameOwnerChanged', function (...)
    print("NameOwnerChanged", ...)
end, { bus = 'session', interface = 'org.freedesktop.DBus' })

print "loop"

local loop = function ()
--         print 'poll'
    dbus.poll()
--         print 'sleep'
    sleep(0.3)
end

if process then
    print "use it"
    process.loop = loop
    process.setup = function ()
        print "call method"
        dbus.call('GetCategories', function (cats)
            if _it then
                print("categories =", require('util').dump(cats))
            else
                print("categories =", cats)
            end
        end, {
            destination = 'org.gnome.Hamster',
            interface = 'org.gnome.Hamster',
            path = '/org/gnome/Hamster',
            bus = 'session',
        })

        print "call method2"
        dbus.call('forceOnNetworkChange', function (...)
            print("forceOnNetworkChange", ...)
        end, {
            destination = 'org.kde.kdeconnectd',
            interface = 'org.kde.kdeconnect.daemon',
            path = '/modules/kdeconnect',
            bus = 'session',
        })

        print "list property changes"
        dbus.property.on('PlaybackStatus', function (status)
            print("PlaybackStatus changed", status)
        end, {
            interface = 'org.mpris.MediaPlayer2.Player',
            sender = 'org.mpris.MediaPlayer2.clementine',
        })

        foobar = require('lua-dbus.interface').test()
    end
    process:on('exit', dbus.exit)
else
    while true do
        loop()
    end
    dbus.exit()
end
