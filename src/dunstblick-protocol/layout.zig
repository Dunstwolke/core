const std = @import("std");
const types = @import("data-types.zig");
const enums = @import("enums.zig");

pub const WidgetDescriptor = struct {
    widget: []const u8,
    type: types.WidgetType,
    properties: []const types.Property,
    description: []const u8 = "",
};

const common_properties = [_]types.Property{
    .horizontal_alignment,
    .vertical_alignment,

    .margins,
    .paddings,
    .dock_site,
    .visibility,
    .enabled,
    .hit_test_visible,
    .binding_context,
    .child_source,
    .child_template,

    .widget_name,
    .tab_title,
    .size_hint,

    .left,
    .top,
};

fn addProperties(comptime list: anytype) []const types.Property {
    const full_set: [common_properties.len + list.len]types.Property = common_properties ++ list;
    return &full_set;
}

pub const widget_types = [_]WidgetDescriptor{
    .{ .widget = "Button", .type = .button, .properties = addProperties([_]types.Property{.on_click}), .description = "The button provides the user the ability to trigger a single-shot action like *Save* or *Load*. It provides a event callback when the user clicks it." },
    .{ .widget = "Label", .type = .label, .properties = addProperties([_]types.Property{ .text, .font_family }), .description = "This widget is used for text rendering. It will display its `text`, which can also be a multiline string." },
    .{ .widget = "Picture", .type = .picture, .properties = addProperties([_]types.Property{ .image, .image_scaling }), .description = 
    \\This widget renders a bitmap or drawing. The image will be set using a certain size mode:
    \\
    \\- `none`: The image will be displayed unscaled on the top-left of the Picture and will be cut off the edges of the Picture.
    \\- `center`: The image will be centered inside the Picture without scaling. All excess will be cut off.
    \\- `stretch`: The image will be stretched so it will fill the full Picture. This is a very nice option for background images.
    \\- `zoom`: The image will be scaled in such a way that it will always touch at least two sides of the Picture. It will always be fully visible and no part of the image will be cut off. This mode is respecting the aspect of the image.
    \\- `cover`: The image will be scaled in such a way that it will fully cover the Picture. This mode is respecting the aspect of the image, thus excess is cut off.
    \\- `contain`: This is a combined mode which will behave like `zoom` if the image is larger than the Picture, otherwise it will behave like `center`.
    },
    .{ .widget = "TextBox", .type = .textbox, .properties = addProperties([_]types.Property{.text}), .description = "The text box is a single line text input field. The user can enter any text that has a single line." },
    .{ .widget = "CheckBox", .type = .checkbox, .properties = addProperties([_]types.Property{.is_checked}), .description = "The combobox provides the user with a yes/no option that can be toggled when clicked. Each combobox is separate from each other, and the property `is-checked` will be toggled." },
    .{ .widget = "RadioButton", .type = .radiobutton, .properties = addProperties([_]types.Property{ .group, .selected_index }), .description = "Radio buttons are grouped together by an integer value and will show active when that value matches their `index`. If the user clicks the radio button, the `group` value is set to the `selected-index`." },
    .{ .widget = "ScrollView", .type = .scrollview, .properties = addProperties([_]types.Property{}) },
    .{ .widget = "ScrollBar", .type = .scrollbar, .properties = addProperties([_]types.Property{ .orientation, .minimum, .value, .maximum }) },
    .{ .widget = "Slider", .type = .slider, .properties = addProperties([_]types.Property{ .orientation, .minimum, .value, .maximum }) },
    .{ .widget = "ProgressBar", .type = .progressbar, .properties = addProperties([_]types.Property{ .orientation, .minimum, .value, .maximum, .display_progress_style }) },
    .{ .widget = "SpinEdit", .type = .spinedit, .properties = addProperties([_]types.Property{ .orientation, .minimum, .value, .maximum }) },
    .{ .widget = "Separator", .type = .separator, .properties = addProperties([_]types.Property{}) },
    .{ .widget = "Spacer", .type = .spacer, .properties = addProperties([_]types.Property{}) },
    .{ .widget = "Panel", .type = .panel, .properties = addProperties([_]types.Property{}) },
    .{ .widget = "Container", .type = .container, .properties = addProperties([_]types.Property{}) },
    .{ .widget = "TabLayout", .type = .tab_layout, .properties = addProperties([_]types.Property{.selected_index}) },
    .{ .widget = "CanvasLayout", .type = .canvas_layout, .properties = addProperties([_]types.Property{}) },
    .{ .widget = "FlowLayout", .type = .flow_layout, .properties = addProperties([_]types.Property{}) },
    .{ .widget = "GridLayout", .type = .grid_layout, .properties = addProperties([_]types.Property{ .columns, .rows }) },
    .{ .widget = "DockLayout", .type = .dock_layout, .properties = addProperties([_]types.Property{}) },
    .{ .widget = "StackLayout", .type = .stack_layout, .properties = addProperties([_]types.Property{.orientation}) },

    .{ .widget = "ComboBox", .type = .combobox, .properties = addProperties([_]types.Property{}) },
    .{ .widget = "TreeView", .type = .treeview, .properties = addProperties([_]types.Property{}) },
    .{ .widget = "ListBox", .type = .listbox, .properties = addProperties([_]types.Property{}) },
};

pub const PropertyDescriptor = struct {
    property: []const u8,
    value: types.Property,
    type: types.Type,
    allowed_enums: []const types.Enum = &.{},
    description: []const u8 = "",
};

fn extractEnumVals(comptime E: type) []const types.Enum {
    const enum_values = std.enums.values(E);
    comptime var items: [enum_values.len]types.Enum = undefined;
    comptime {
        for (items) |*dst, i| {
            dst.* = @intToEnum(types.Enum, @enumToInt(enum_values[i]));
        }
    }
    return &items;
}

pub const properties = [_]PropertyDescriptor{
    .{ .property = "horizontal-alignment", .value = .horizontal_alignment, .type = .enumeration, .allowed_enums = extractEnumVals(enums.HorizontalAlignment) },
    .{ .property = "vertical-alignment", .value = .vertical_alignment, .type = .enumeration, .allowed_enums = extractEnumVals(enums.VerticalAlignment) },
    .{ .property = "margins", .value = .margins, .type = .margins },
    .{ .property = "paddings", .value = .paddings, .type = .margins },
    .{ .property = "dock-site", .value = .dock_site, .type = .enumeration, .allowed_enums = extractEnumVals(enums.DockSite) },
    .{ .property = "visibility", .value = .visibility, .type = .enumeration, .allowed_enums = extractEnumVals(enums.Visibility) },
    .{ .property = "size-hint", .value = .size_hint, .type = .size },
    .{ .property = "font-family", .value = .font_family, .type = .enumeration, .allowed_enums = extractEnumVals(enums.Font) },
    .{ .property = "text", .value = .text, .type = .string },
    .{ .property = "minimum", .value = .minimum, .type = .number },
    .{ .property = "maximum", .value = .maximum, .type = .number },
    .{ .property = "value", .value = .value, .type = .number },
    .{ .property = "display-progress-style", .value = .display_progress_style, .type = .enumeration, .allowed_enums = extractEnumVals(enums.DisplayProgressStyle) },
    .{ .property = "is-checked", .value = .is_checked, .type = .boolean },
    .{ .property = "tab-title", .value = .tab_title, .type = .string },
    .{ .property = "selected-index", .value = .selected_index, .type = .integer },
    .{ .property = "group", .value = .group, .type = .integer },
    .{ .property = "columns", .value = .columns, .type = .sizelist },
    .{ .property = "rows", .value = .rows, .type = .sizelist },
    .{ .property = "left", .value = .left, .type = .integer },
    .{ .property = "top", .value = .top, .type = .integer },
    .{ .property = "enabled", .value = .enabled, .type = .boolean },
    .{ .property = "image-scaling", .value = .image_scaling, .type = .enumeration, .allowed_enums = extractEnumVals(enums.ImageScaling) },
    .{ .property = "image", .value = .image, .type = .resource },
    .{ .property = "binding-context", .value = .binding_context, .type = .object },
    .{ .property = "child-source", .value = .child_source, .type = .objectlist },
    .{ .property = "child-template", .value = .child_template, .type = .resource },
    .{ .property = "hit-test-visible", .value = .hit_test_visible, .type = .boolean },
    .{ .property = "on-click", .value = .on_click, .type = .event },
    .{ .property = "orientation", .value = .orientation, .type = .enumeration, .allowed_enums = extractEnumVals(enums.Orientation) },
    .{ .property = "widget-name", .value = .widget_name, .type = .widget },
};

pub const EnumDescriptor = struct {
    enumeration: []const u8,
    value: types.Enum,
};

pub const enumerations = [_]EnumDescriptor{
    .{ .enumeration = "none", .value = .none },
    .{ .enumeration = "left", .value = .left },
    .{ .enumeration = "center", .value = .center },
    .{ .enumeration = "right", .value = .right },
    .{ .enumeration = "top", .value = .top },
    .{ .enumeration = "middle", .value = .middle },
    .{ .enumeration = "bottom", .value = .bottom },
    .{ .enumeration = "stretch", .value = .stretch },
    .{ .enumeration = "expand", .value = .expand },
    .{ .enumeration = "auto", .value = .auto },
    .{ .enumeration = "yesno", .value = .yesno },
    .{ .enumeration = "truefalse", .value = .truefalse },
    .{ .enumeration = "onoff", .value = .onoff },
    .{ .enumeration = "visible", .value = .visible },
    .{ .enumeration = "hidden", .value = .hidden },
    .{ .enumeration = "collapsed", .value = .collapsed },
    .{ .enumeration = "vertical", .value = .vertical },
    .{ .enumeration = "horizontal", .value = .horizontal },
    .{ .enumeration = "sans", .value = .sans },
    .{ .enumeration = "serif", .value = .serif },
    .{ .enumeration = "monospace", .value = .monospace },
    .{ .enumeration = "percent", .value = .percent },
    .{ .enumeration = "absolute", .value = .absolute },
    .{ .enumeration = "zoom", .value = .zoom },
    .{ .enumeration = "contain", .value = .contain },
    .{ .enumeration = "cover", .value = .cover },
};
