local function Identifier(i)
  i.id = i[1] or error("missing id!")
  i.name = i[2] or error("missing name!")
  i.realName = i[3] or i[2]
  return i
end

local function Widget(w)
    w.id = w[1] or error("missing id")
    w.enum = w[2] or error("missing enumeration")
    w.name = w[3] or error("missing name")
    w.properties = w[4] or error("properties not found for "..w.name)
    w.description = w[5]

    for _,i in ipairs({1,2,3,4,6,7,32,20,21,16,22,8,25,29,26,27}) do
        table.insert(w.properties, i)
    end

    return w
end

local function Property(p)

    p.id = p[1] or error("missing id")
    p.identifier = p[2] or error("missing identifier")
    p.name = p[3] or error("missing name")
    p.type = p[4] or error("missing type")
    p.description = p[5]

    return p
end

return {

    widget = function(self, id)
        for i,v in ipairs(self.widgets) do
            if v.id == id then
                return v
            end
        end
    end,

    property = function(self, id)
        for i,v in ipairs(self.properties) do
            if v.id == id then
                return v
            end
        end
    end,

    -- Lists all possible distinct enumeration values
    -- Enums are not continuous, but unique and don't allow
    -- aliasing between names.
    identifiers = {
        -- ID, C++Name,      (Real Name)
        Identifier {   0, "none",       nil    },
        Identifier {   1, "left",       nil    },
        Identifier {   2, "center",     nil    },
        Identifier {   3, "right",      nil    },
        Identifier {   4, "top",        nil    },
        Identifier {   5, "middle",     nil    },
        Identifier {   6, "bottom",     nil    },
        Identifier {   7, "stretch",    nil    },
        Identifier {   8, "expand",     nil    },
        Identifier {   9, "_auto",      "auto" },
        Identifier {  10, "yesno",      nil    },
        Identifier {  11, "truefalse",  nil    },
        Identifier {  12, "onoff",      nil    },
        Identifier {  13, "visible",    nil    },
        Identifier {  14, "hidden",     nil    },
        Identifier {  15, "collapsed",  nil    },
        Identifier {  16, "vertical",   nil    },
        Identifier {  17, "horizontal", nil    },
        Identifier {  18, "sans",       nil    },
        Identifier {  19, "serif",      nil    },
        Identifier {  20, "monospace",  nil    },
        Identifier {  21, "percent",    nil    },
        Identifier {  22, "absolute",   nil    },
        Identifier {  23, "zoom",       nil    },
        Identifier {  24, "contain",    nil    },
        Identifier {  25, "cover",      nil    },
    },

    -- Table of all widget types and their C++ class names.
    -- Also contains the unique identifier for each widget.
    widgets = {
        --       ID,  Enumeration,     ClassName
        Widget {   1, "button",        "Button"      , { 30, },             "A simple button the user can click." },
        Widget {   2, "label",         "Label"       , { 10, 9, },          "A widget that displays a piece of text." },
        Widget {   3, "combobox",      "ComboBox"    , { },                 "An input field where the user can select one of several options." },
     -- Widget {   4, "treeviewitem",  "TreeViewItem", { } },       
        Widget {   5, "treeview",      "TreeView"    , { } },       
     -- Widget {   6, "listboxitem",   "ListBoxItem" , { } },       
        Widget {   7, "listbox",       "ListBox"     , { },                 "A list of items where the user can select one." },
    --  Widget 8       
        Widget {   9, "picture",       "Picture"     , { 23, 24, },         "Displays an image."},
        Widget {  10, "textbox",       "TextBox"     , { },                 "An input field where the user can enter freeform text." },
        Widget {  11, "checkbox",      "CheckBox"    , { 15, },             "A button that can either be checked or unchecked. It toggles its checked state when the user clicks it." },
        Widget {  12, "radiobutton",   "RadioButton" , { 15, },             "Similar to the checkbox, a radio button can be checked or unchecked. But for each radio group, only one radio button can be checked at once. If the user clicks on a radio button, all other radio buttons in the same group will uncheck." },
        Widget {  13, "scrollview",    "ScrollView"  , { },                 "A container with two scroll bars on the right and the bottom. Will allow the user to view all of the contained widgets by using the scroll bars to pan the view. If the contained widgets fit inside the widget body, the scroll bars get disabled." },
        Widget {  14, "scrollbar",     "ScrollBar"   , { 31, 11, 12, 13 },  "A widget that allows the user to scroll or pan certain elements. It has a button on the start and the end of the bar to scroll by a little bit and a knob that can be grabbed by the user to scroll to an absolute value." },
        Widget {  15, "slider",        "Slider"      , { },                 "A knob the user can grab and drag to dial a certain value." },
        Widget {  16, "progressbar",   "ProgressBar" , { 11, 12, 13, 14, }, "A widget that can display a progress of an action. Allows an optional numeric display of the current progress in percent or with absolute values." },
        Widget {  17, "spinedit",      "SpinEdit"    , { 11, 12, 13, 31 } },
        Widget {  18, "separator",     "Separator"   , { },                 "A simple vertical or horizontal line that separates two widgets. The orientation of the line is choosen automatically by the width and height of the separator." },
        Widget {  19, "spacer",        "Spacer"      , { },                 "An invisible and non-interactible widget that can be used to fill areas." },
        Widget {  20, "panel",         "Panel"       , { },                 "A container that has a simple border and can put widgets into a visual group." },
        Widget {  21, "container",     "Container"   , { },                 "An invisible widget that can be used to group other widgets or insert invisible margins." },

        -- widgets go here ↑
        -- layouts go here ↓

        Widget { 250, "tab_layout",    "TabLayout"   , { 17,  },            "A special layout that groups widgets into separate pages. Only a single child can be visible, but all childs are presented to the user in a list of tabs. The name displayed on a tab is defined by the [`tab-title`](#property:tab-title) property." },
        Widget { 251, "canvas_layout", "CanvasLayout", { },                 "The canvas layout allows to put widgets in certain spots and does not enforce an automatic layout. The position for each widget is defined by its [`top`](#property:top) and [`left`](#property:left) property." },
        Widget { 252, "flow_layout",   "FlowLayout"  , { },                 "The flow layout will try to fit as many widgets as possible in a single row/column and will reflow overlapping widgets into the next column/row. This allows creating dynamic layouts that behave similar to flowing text." },
        Widget { 253, "grid_layout",   "GridLayout"  , { 18, 19, },         "A layout that aligns widgets into a tabular style. The rows and columns are sizeable by the user and can either be sized automatically or in absolute/percentage values." },
        Widget { 254, "dock_layout",   "DockLayout"  , { },                 "A layout that uses a docking mechanism to position widgets. Docking means that the widget is put at the top, left, bottom or right side of the layout, then the obstructed space is removed from the layouting area. This process is repeated until the last widget, which will then take up the available space."},
        Widget { 255, "stack_layout",  "StackLayout" , { 31, },             "A simple layout that will stack widgets either horizontally or vertically." },
    },

    -- This is a set of types and their names in both dunstblick and C++.
    -- Each type has a unique ID that can be used to identify a property.
    types =
    {--   ID,  Name,         C++ Type
        {   0, "invalid",     "std::monostate"        },
        {   1, "integer",     "int32_t"               },
        {   2, "number",      "float"                 },
        {   3, "string",      "std::string"           },
        {   4, "enumeration", "uint8_t"               },
        {   5, "margins",     "UIMargin"              },
        {   6, "color",       "UIColor"               },
        {   7, "size",        "UISize"                },
        {   8, "point",       "UIPoint"               },
        {   9, "resource",    "UIResourceID"          },
        {  10, "boolean",     "bool"                  },
        {  11, "sizelist",    "UISizeList"            },
        {  12, "object",      "ObjectRef"             },
        {  13, "objectlist",  "ObjectList"            },
        {  14, "event",       "EventID"               },
        {  15, "name",        "WidgetName"            },
    },

    -- This table contains the definitions for each possible widget property.
    -- The property IDs are shared amongst all widgets and cannot be reused.
    properties =
    {--   ID,  Code Name,              Style Name,             Type,
        Property {   1, "horizontalAlignment",  "horizontal-alignment",   "enumeration" },
        Property {   2, "verticalAlignment",    "vertical-alignment",     "enumeration" },
        Property {   3, "margins",              "margins",                "margins"     },
        Property {   4, "paddings",             "paddings",               "margins"     },
     -- Property {   5, "stackDirection",       "stack-direction",        "enumeration" },
        Property {   6, "dockSite",             "dock-site",              "enumeration" },
        Property {   7, "visibility",           "visibility",             "enumeration" },
        Property {   8, "sizeHint",             "size-hint",              "size"        },
        Property {   9, "fontFamily",           "font-family",            "enumeration" },
        Property {  10, "text",                 "text",                   "string"      },
        Property {  11, "minimum",              "minimum",                "number"      },
        Property {  12, "maximum",              "maximum",                "number"      },
        Property {  13, "value",                "value",                  "number"      },
        Property {  14, "displayProgressStyle", "display-progress-style", "enumeration" },
        Property {  15, "isChecked",            "is-checked",             "boolean"     },
        Property {  16, "tabTitle",             "tab-title",              "string"      },
        Property {  17, "selectedIndex",        "selected-index",         "integer"     },
        Property {  18, "columns",              "columns",                "sizelist"    },
        Property {  19, "rows",                 "rows",                   "sizelist"    },
        Property {  20, "left",                 "left",                   "integer"     },
        Property {  21, "top",                  "top",                    "integer"     },
        Property {  22, "enabled",              "enabled",                "boolean"     },
        Property {  23, "imageScaling",         "image-scaling",          "enumeration" },
        Property {  24, "image",                "image",                  "resource"    },
        Property {  25, "bindingContext",       "binding-context",        "object"      },
        Property {  26, "childSource",          "child-source",           "objectlist"  },
        Property {  27, "childTemplate",        "child-template",         "resource"    },
     -- Property {  28, "toolTip",              "tool-tip",               "string"      },
        Property {  29, "hitTestVisible",       "hit-test-visible",       "boolean"     },
        Property {  30, "onClick",              "on-click",               "event"       },
        Property {  31, "orientation",          "orientation",            "enumeration" },
        Property {  32, "name",                 "widget-name",            "name",       },
    },

    -- This defines the enumeration groups used in the UI system.
    -- Each group is a set of enumeration values.
    groups =
    {
        ["UIFont"]               = { "sans", "serif", "monospace" },
        ["HAlignment"]           = { "stretch", "left", "center", "right" },
        ["VAlignment"]           = { "stretch", "top", "middle", "bottom" },
        ["Visibility"]           = { "visible", "collapsed", "hidden" },
        ["StackDirection"]       = { "vertical", "horizontal" },
        ["DockSite"]             = { "top", "bottom", "left", "right" },
        ["DisplayProgressStyle"] = { "none", "percent", "absolute" },
        ["ImageScaling"]         = { "none", "center", "stretch", "zoom", "contain", "cover" },
        ["BooleanFormat"]        = { "truefalse", "yesno", "onoff" },
        ["Orientation"]          = { "horizontal", "vertical" },
    },
};
