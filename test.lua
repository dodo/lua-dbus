local dbus = require('lua-dbus')
local sleep = require('socket').sleep
print "init"
dbus.init()

print "listen"
dbus.on('StatusChanged', function (status, data)
    if _it then
        print('StatusChanged', status, require('util').dump(data))
    else
        print('StatusChanged', status, data)
    end
end, { bus = 'system', interface = 'org.wicd.daemon' })

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

        dbus.call('forceOnNetworkChange', function (...)
            print("forceOnNetworkChange", ...)
        end, {
            destination = 'org.kde.kdeconnectd',
            interface = 'org.kde.kdeconnect.daemon',
            path = '/modules/kdeconnect',
            bus = 'session',
        })
    end
else
    while true do
        loop()
    end
end
dbus.exit()
