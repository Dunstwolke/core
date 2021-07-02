local f = assert(io.open("dox/dunstblick-widgets.md", "w"))

f:write [[
@page dunstblick-widgets Dunstblick Widgets
@brief Description of the Widgets available in @ref dunstblick

## Overview

The following widgets are available in @ref dunstblick:
]]

for _,widget in ipairs(UI.widgets) do

  f:write("- [", widget.name, "](#widget:", widget.enum, ")\n")

end

f:write [[

## Widgets

]]


for _,widget in ipairs(UI.widgets) do

  f:write('<h3 id="widget:', widget.enum, '">', widget.name, '</h3>\n')

  f:write(widget.description or ("No description for " .. widget.name .. " available."), "\n")

  f:write("\n")

  if #widget.properties >  0then

    f:write("**Properties:**\n")
    f:write("\n")

    for idx, id in ipairs(widget.properties) do
      local prop = UI:property(id)
      if idx > 1 then
        f:write(", ")
      end
      f:write("[`", prop.name, "`](#property:", prop.name, ")")
    end
    f:write("\n")
  end


end

f:write [[

## Properties

]]

for _, prop in ipairs(UI.properties) do

  f:write('<h3 id="property:', prop.name, '">', prop.name, '</h3>\n')

  f:write(prop.description or ("No description for " .. prop.name .. " available."), "\n")

end

f:close()