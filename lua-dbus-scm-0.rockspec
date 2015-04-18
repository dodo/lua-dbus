package = "lua-dbus"
version = "scm-0"
source = { url = "git://github.com/dodo/lua-dbus.git" }
description = {
   summary = "convenient dbus api",
   detailed = "Convenient dbus api in lua.",
   homepage = "https://github.com/dodo/lua-dbus",
   license = "MIT",
}
dependencies = { "lua >= 5.1", "ldbus > scm-0" }
build = {
   type = "builtin",
   modules = {
      awesome = "awesome/init.lua",
      ['awesome.dbus'] = "awesome/dbus.lua",
      init = "init.lua",
      interface = "interface.lua",
   }
}
