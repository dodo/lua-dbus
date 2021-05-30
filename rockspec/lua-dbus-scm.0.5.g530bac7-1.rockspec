package = "lua-dbus"
version = "scm.0.5.g530bac7-1"
source = {
   url = "git://github.com/logiceditor-com/lua-dbus.git",
   branch = "scm.0.5.g530bac7",
}
description = {
   summary = "convenient dbus api",
   detailed = "Convenient dbus api in lua.",
   homepage = "https://github.com/dodo/lua-dbus",
   license = "MIT",
}
dependencies = { "lua >= 5.1", "ldbus >= 0.0.0.134" }
build = {
   type = "builtin",
   modules = {
      ['lua-dbus.awesome'] = "awesome/init.lua",
      ['lua-dbus.awesome.dbus'] = "awesome/dbus.lua",
      ['lua-dbus.init'] = "init.lua",
      ['lua-dbus.interface'] = "interface.lua",
   }
}