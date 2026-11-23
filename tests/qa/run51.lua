-- Runs a script under the Lua 5.1 shim: texlua qa/run51.lua <script> [args]
local here = arg[0]:match("^(.*)/") or "."
dofile(here .. "/lua51.lua")
local script = table.remove(arg, 1)
arg[0] = script
local f = assert(loadfile(script))
f(table.unpack(arg))
