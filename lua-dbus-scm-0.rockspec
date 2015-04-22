package = "lua-dbus"
version = "scm-0"
source = { url = "git://github.com/dodo/lua-dbus.git" }
description = {
   summary = "convenient dbus api",
   detailed = "Convenient dbus api in lua.",
   homepage = "https://github.com/dodo/lua-dbus",
   license = "MIT",
}
dependencies = { "lua >= 5.1", "ldbus >= scm-0" }
build = {
   type = "builtin",
   modules = {
      ['lua-dbus.awesome'] = "awesome/init.lua",
      ['lua-dbus.awesome.dbus'] = "awesome/dbus.lua",
      ['lua-dbus.init'] = "init.lua",
      ['lua-dbus.interface'] = "interface.lua",
   }
}
