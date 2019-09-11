-- load UI definitions
local UI = require "definitions"

local function genEnumHeader(f)
	f:write [[#ifndef ENUMS_HPP
#define ENUMS_HPP

#include <cstdint>
#include <string>

/// combined enum containing all possible enumeration values
/// used in the UI system.
namespace UIEnum
{
]]

	for i,v in ipairs(UI.identifiers) do
		f:write("\tconstexpr uint8_t ", v[2], " = ", v[1], ";\n");
	end

	f:write [[}

enum class UIWidget : uint8_t
{
	invalid = 0, // marks "end of children" in the binary format
]]

	for i,v in ipairs(UI.widgets) do
		f:write("\t", v[2], " = ", v[1], ",\n")
	end
	f:write [[};

enum class UIProperty : uint8_t
{
	invalid = 0, // marks "end of properties" in the binary format
]]

	for i,v in ipairs(UI.properties) do
		if v[1] <= 0 or v[1] >= 128 then
			error("property value out of range!");
		end
		f:write("\t", v[2], " = ", v[1], ",\n")
	end

	f:write [[};

enum class UIType : uint8_t
{
]]
	for i,v in ipairs(UI.types) do
		f:write("\t", v[2], " = ", v[1], ",\n")
	end

	f:write [[};

]]

	for name, contents in pairs(UI.groups) do
		f:write("enum class ", name, " : uint8_t\n{\n")
		for i,v in ipairs(contents) do
			f:write("\t", v, " = UIEnum::", v, ",\n")
		end
		f:write("};\n\n")
	end

	f:write [[
UIType getPropertyType(UIProperty property);

std::string to_string(UIProperty property);
std::string to_string(UIWidget property);
std::string to_enum_string(uint8_t enumValue);
std::string to_string(UIType property);

#endif // ENUMS_HPP
]]

end

local function genEnumSource(f)
	f:write [[#include "enums.hpp"
#include <cassert>

UIType getPropertyType(UIProperty property)
{
	switch(property)
	{
]]
	
	for i,v in ipairs(UI.properties) do
		f:write("\t\tcase UIProperty::", v[2], ": return UIType::", v[4], ";\n")
	end

	f:write [[	}
	assert(false and "invalid property was passed to getPropertyType!");
}

std::string to_string(UIProperty property)
{
	switch(property)
	{
]]
	for i,v in ipairs(UI.properties) do
		f:write("\t\tcase UIProperty::", v[2], ': return "', v[3], '";\n')
	end

	f:write [[	}
	return "property(" + std::to_string(int(property)) + ")";
}
std::string to_string(UIWidget widget)
{
	switch(widget)
	{
]]
	for i,v in ipairs(UI.widgets) do
		f:write("\t\tcase UIWidget::", v[2], ': return "', v[3], '";\n')
	end

	f:write [[	}
	return "widget(" + std::to_string(int(widget)) + ")";
}

std::string to_enum_string(uint8_t enumValue)
{
	switch(enumValue)
	{
]]
	for i,v in ipairs(UI.identifiers) do
		f:write("\t\tcase ", v[1], ': return "', v[2], '";\n')
	end

	f:write [[	}
	return "enum(" + std::to_string(int(enumValue)) + ")";
}

std::string to_string(UIType type)
{
	switch(type)
	{
]]
	for i,v in ipairs(UI.types) do
		f:write("\t\tcase UIType::", v[2], ': return "', v[2], '";\n')
	end

	f:write [[	}
	return "type(" + std::to_string(int(type)) + ")";
}

]]
	
end

local function genParserInfoHeader(f)
	
	f:write [[#ifndef INCLUDE_PARSER_FIELDS
#error "requires INCLUDE_PARSER_FIELDS to be defined!"
#endif

static const std::map<std::string, UIWidget> widgetTypes =
{
]]
	for i,v in ipairs(UI.widgets) do
    	f:write('\t { "', v[3], '", UIWidget::', v[2], ' },\n')
	end

f:write [[};

static const std::map<std::string, UIProperty> properties =
{
]]
	for i,v in ipairs(UI.properties) do
    	f:write('\t { "', v[3], '", UIProperty::', v[2], ' },\n')
	end

f:write [[};

static const std::map<std::string, uint8_t> enumerations =
{
]]
	for i,v in ipairs(UI.identifiers) do
    	f:write('\t { "', v[3] or v[2], '", UIEnum::', v[2], ' },\n')
	end

    -- { "auto", UIEnum::_auto },
f:write [[};
]]

end

local function genCreateWidgetSource(f)

	f:write [[#include "widgets.hpp"
#include "layouts.hpp"

std::unique_ptr<Widget> Widget::create(UIWidget id)
{
	switch(id)
	{
]]
	for i,v in ipairs(UI.widgets) do
		f:write("\tcase UIWidget::", v[2], ": return std::make_unique<", v[3], ">();\n") 
	end

	f:write [[	}
	assert(false and "invalid widget type was passed to Widget::create()!");
}
]]
end

local function genVariantHeader(f)
	
	f:write 'using UIValue = std::variant<\n'
	
	for i,v in ipairs(UI.types) do
		f:write("\t", v[3])
		if i ~= #UI.types then
			f:write(",")
		end
		f:write("\n")
	end

	f:write '>;\n\n'

	for i,v in ipairs(UI.types) do
		f:write("static_assert(std::is_same_v<std::variant_alternative_t<size_t(UIType::", v[2], "),     UIValue>, ", v[3], ">);\n")
	end
end

local f

f = assert(io.open("enums.hpp", "w"))
genEnumHeader(f)
f:close()

f = assert(io.open("enums.cpp", "w"))
genEnumSource(f)
f:close()

f = assert(io.open("parser-info.hpp", "w"))
genParserInfoHeader(f)
f:close()

f = assert(io.open("widget.create.cpp", "w"))
genCreateWidgetSource(f)
f:close()

f = assert(io.open("types.variant.hpp", "w"))
genVariantHeader(f)
f:close()
