local pixel = require "pixel"
local sprotoparser = require "sprotoparser"
local sprotoloader = require "sprotoloader"
local proto = require "example.proto"


sprotoloader.save(proto.c2s, 1)
sprotoloader.save(proto.s2c, 2)