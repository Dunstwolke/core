-- load UI definitions
local UI = dofile "../dunstblick-common/definitions.lua"

local function genLookupTables(f)
	
	f:write [[pub const widget_types = .{
]]
	for i,v in ipairs(UI.widgets) do
    	f:write('    .{ .widget = "', v.name, '", .type = .', v.enum, ' },\n')
	end

f:write [[};

pub const properties = .{
]]
	for i,v in ipairs(UI.properties) do
    	f:write('    .{ .property = "', v.name, '", .value = .', v.identifier, ' },\n')
	end

f:write [[};

pub const enumerations = .{
]]
	for i,v in ipairs(UI.identifiers) do
    	f:write('    .{ .enumeration = "', v.realName, '", .value = .', v.name, ' },\n')
	end
f:write [[};
]]

end

local function genEnums(f)

	f:write("pub const WidgetType = enum(u8) {\n");
	for i,v in ipairs(UI.widgets) do
		f:write('    ', v.enum, ' = ', v.id, ',\n')
	end
	f:write("};\n\n");

	f:write("pub const Property = enum(u8) {\n");
	for i,v in ipairs(UI.properties) do
		f:write('    ', v.identifier, ' = ', v.id, ',\n')
	end
	f:write("};\n\n");

	f:write("pub const Enum = enum(u8) {\n");
	for i,v in ipairs(UI.identifiers) do
		f:write('    ', v.name, ' = ', v.id, ',\n')
	end
	f:write("};\n\n");

	f:write("pub const Type = enum(u8) {\n");
	for i,v in ipairs(UI.types) do
		f:write('    ', v.name, ' = ', v.id, ',\n')
	end
	f:write("};\n\n");

end

-------------------------------------------------------------------------------

local f

f = assert(io.open("strings.zig", "w"))
genLookupTables(f)
f:close()

f = assert(io.open("enums.zig", "w"))
genEnums(f)
f:close()