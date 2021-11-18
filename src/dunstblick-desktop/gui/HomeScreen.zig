const std = @import("std");
const painterz = @import("painterz");
const tvg = @import("tvg");

const zerog = @import("zero-graphics");

const icons = @import("icons/data.zig");

const logger = std.log.scoped(.home_screen);

const Self = @This();

const UserInterface = zerog.UserInterface;
const Renderer2D = zerog.Renderer2D;
const ResourceManager = zerog.ResourceManager;
const Point = zerog.Point;
const Size = zerog.Size;
const Rectangle = zerog.Rectangle;
const Color = zerog.Color;

const ApplicationInstance = @import("ApplicationInstance.zig");
const ApplicationDescription = @import("ApplicationDescription.zig");

const ButtonTheme = struct {
    const Style = struct {
        outline: Color,
        background: Color,
    };

    default: Style,
    hovered: Style,
    clicked: Style,
    disabled: Style,

    text_color: Color,
    icon_size: u15,
};

fn rgb(comptime str: *const [6]u8) Color {
    return Color{
        .r = std.fmt.parseInt(u8, str[0..2], 16) catch unreachable,
        .g = std.fmt.parseInt(u8, str[2..4], 16) catch unreachable,
        .b = std.fmt.parseInt(u8, str[4..6], 16) catch unreachable,
    };
}

fn rgba(comptime str: *const [6]u8, alpha: f32) Color {
    var color = rgb(str);
    color.a = @floatToInt(u8, 255.0 * alpha);
    return color;
}

const default_colors = struct {
    pub const bright_green = rgb("1abc9c");
    pub const dark_green = rgb("0e443f");

    pub const bright_gray = rgb("363c42");
    pub const dark_gray = rgb("292f35");
    pub const tinted_gray = rgb("263238");
};

pub const Config = struct {
    const WorkspaceBarConfig = struct {
        // background: Color,
        // border: Color,
        // button_theme: ButtonTheme,
        button_size: u15,
        margins: u15,
        location: RectangleSide,

        fn getWidth(self: @This()) u15 {
            return 2 * self.margins + self.button_size;
        }
    };

    const AppMenuConfig = struct {
        button_theme: ButtonTheme,

        // dimmer: Color,
        // outline: Color,
        // background: Color,
        button_size: u15,
        scrollbar_width: u15,
        margins: u15,
    };

    const WorkspaceConfig = struct {
        app_icon_size: u15,
        // active_app_border: Color,
        // background_color: Color,
        // insert_highlight_color: Color,
        // insert_highlight_fill_color: Color,
    };

    const LongClickIndicator = struct {
        outline: Color,
        fill_color: Color,
    };

    app_menu: AppMenuConfig = AppMenuConfig{
        // .dimmer = rgba("292f35", 0.5),
        // .outline = default_colors.bright_green,
        // .background = rgb("255953"),
        .scrollbar_width = 8,
        .margins = 8,

        .button_size = 100,
        .button_theme = ButtonTheme{
            .text_color = rgb("ffffff"),
            .icon_size = 64,
            .default = .{
                .outline = default_colors.bright_green,
                .background = rgb("255953"),
            },
            .hovered = .{
                .outline = default_colors.bright_green,
                .background = default_colors.dark_green,
            },
            .clicked = .{
                .outline = default_colors.bright_green,
                .background = default_colors.dark_green,
            },
            .disabled = .{
                .outline = rgb("a6a6a6"),
                .background = rgb("505050"),
            },
        },
    },

    workspace_bar: WorkspaceBarConfig = WorkspaceBarConfig{
        .location = .bottom,
        .button_size = 50,
        .margins = 8,
    },

    workspace: WorkspaceConfig = WorkspaceConfig{
        .app_icon_size = 96,
        // .background_color = default_colors.tinted_gray,
        // .active_app_border = rgb("255853"),
        // .insert_highlight_color = rgb("FF00FF"),
        // .insert_highlight_fill_color = rgba("FF00FF", 0.3),
    },

    longclick_indicator: LongClickIndicator = LongClickIndicator{
        .fill_color = rgb("255953"),
        .outline = default_colors.bright_green,
    },
};

const ui_workspace_bar_button_theme = UserInterface.ButtonTheme{
    .icon_size = 48,
    .default = .{
        .border = default_colors.bright_gray,
        .background = default_colors.dark_gray,
        .text_color = Color.white,
    },
    .hovered = .{
        .border = default_colors.bright_green,
        .background = default_colors.dark_green,
        .text_color = Color.white,
    },
    .clicked = .{
        .border = default_colors.bright_green,
        .background = rgb("003934"),
        .text_color = Color.white,
    },
    .disabled = .{
        .border = default_colors.bright_gray,
        .background = default_colors.dark_gray,
        .text_color = rgb("cccccc"),
    },
};

const ui_contextmenu_panel_theme = UserInterface.BoxStyle{
    .border = rgb("212529"),
    .background = rgb("255953"),
};

const ui_window_panel_theme = UserInterface.BoxStyle{
    .border = rgb("212529"),
    .background = default_colors.tinted_gray,
};

const ui_active_window_panel_theme = UserInterface.BoxStyle{
    .border = default_colors.dark_green,
    .background = default_colors.tinted_gray,
};

const ui_app_menu_panel_theme = UserInterface.BoxStyle{
    .border = default_colors.bright_green,
    .background = default_colors.dark_green,
};

const ui_split_panel = UserInterface.BoxStyle{
    .border = default_colors.bright_green,
    .background = default_colors.dark_green,
};

const ui_workspace_bar_current_button_theme = UserInterface.ButtonTheme{
    .icon_size = 48,
    .default = .{
        .border = default_colors.bright_green,
        .background = default_colors.dark_green,
        .text_color = Color.white,
    },
    .hovered = .{
        .border = default_colors.bright_green,
        .background = default_colors.dark_green,
        .text_color = Color.white,
    },
    .clicked = .{
        .border = default_colors.bright_green,
        .background = rgb("003934"),
        .text_color = Color.white,
    },
    .disabled = .{
        .border = default_colors.bright_gray,
        .background = default_colors.dark_gray,
        .text_color = rgb("cccccc"),
    },
};

const ui_appmenu_button_theme = UserInterface.ButtonTheme{
    .icon_size = 64,
    .default = .{
        .border = default_colors.bright_green,
        .background = rgb("255953"),
        .text_color = Color.white,
    },
    .hovered = .{
        .border = default_colors.bright_green,
        .background = default_colors.dark_green,
        .text_color = Color.white,
    },
    .clicked = .{
        .border = default_colors.bright_green,
        .background = rgb("003934"),
        .text_color = Color.white,
    },
    .disabled = .{
        .border = rgb("a6a6a6"),
        .background = rgb("505050"),
        .text_color = rgb("cccccc"),
    },
};

const ui_theme = UserInterface.Theme{
    .button = .{
        .icon_size = 24,
        .default = .{
            .border = default_colors.bright_green,
            .background = rgb("255953"),
            .text_color = Color.white,
        },
        .hovered = .{
            .border = default_colors.bright_green,
            .background = default_colors.dark_green,
            .text_color = Color.white,
        },
        .clicked = .{
            .border = default_colors.bright_green,
            .background = rgb("003934"),
            .text_color = Color.white,
        },
        .disabled = .{
            .border = rgb("a6a6a6"),
            .background = rgb("505050"),
            .text_color = rgb("cccccc"),
        },
    },

    .panel = .{
        .border = rgb("212529"),
        .background = default_colors.dark_gray,
    },

    .text_box = .{
        .border = rgb("cccccc"),
        .background = rgb("303030"),
    },

    .label = .{
        .text_color = rgb("ffffff"),
    },

    .modal_layer = .{
        .fill_color = rgba("292f35", 0.5),
    },
};

const MouseMode = union(enum) {
    /// Nothing special is happening, the user is moving the mouse and can click buttons
    /// by clicking them with pressing and releasing the mouse button in them.
    /// Widget interaction on the workspaces behave normal.
    default,

    /// The mouse was pressed on a button and is now held.
    /// The value is the index of the button that was pressed.
    button_press: usize,

    /// The app menu was opened and is now being displayed. The user can only click
    /// app icons to start dragging or the background.
    app_menu,

    /// An app icon was pressed and is now held.
    app_press: AppPress,

    /// The app is now being dragged over the app menu, the menu is still open
    app_drag_menu: usize,

    /// The app is now being dragged outside of the app menu and will move over the desktop.
    app_drag_desktop: usize,

    // /// An app was long-clicked and the user can now see some info about it
    // app_context_menu: AppContextMenu,

    // /// A window was long-clicked and the use can now chose some interactions
    // window_context_menu: WindowContextMenu,

    fn isContextMenuVisible(self: @This()) bool {
        return switch (self) {
            .default, .button_press, .app_drag_desktop, .app_menu, .app_press, .app_drag_menu => false,
        };
    }

    fn isAppMenuVisible(self: @This()) bool {
        return switch (self) {
            .default, .button_press, .app_drag_desktop => false,
            .app_menu, .app_press, .app_drag_menu => true,
        };
    }

    const AppPress = struct {
        /// The app that was clicked
        index: usize,
        /// The position where the app was clicked
        position: Point,
    };

    const AppContextMenu = struct {
        /// The app that was clicked
        index: usize,

        menu_items: [1]ContextMenuItem = .{
            .{ .title = "Remove" },
        },
    };

    const WindowContextMenu = struct {
        /// The app that was clicked
        window: *AppInstance,

        menu_items: [2]ContextMenuItem = .{
            .{ .title = "Move to workspace..." },
            .{ .title = "Close application" },
        },
    };

    const ContextMenuItem = struct {
        title: []const u8,
        enabled: bool = true,
    };
};

const RectangleSide = enum {
    top,
    bottom,
    left,
    right,

    pub fn jsonStringify(value: RectangleSide, options: std.json.StringifyOptions, writer: anytype) !void {
        _ = options;
        try writer.writeAll("\"");
        try writer.writeAll(std.meta.tagName(value));
        try writer.writeAll("\"");
    }
};

const IconCache = struct {
    const SizedIcons = std.AutoHashMapUnmanaged(u30, *ResourceManager.Texture);
    const Map = std.StringHashMapUnmanaged(SizedIcons);

    allocator: *std.mem.Allocator,
    resource_manager: ?*ResourceManager,
    icon_map: Map,
    arena: std.heap.ArenaAllocator,

    pub fn get(self: *IconCache, icon: []const u8, size: Size) !*ResourceManager.Texture {
        const resource_manager = self.resource_manager orelse @panic("usage error");

        const gop1 = try self.icon_map.getOrPut(self.allocator, icon);
        if (!gop1.found_existing) {
            gop1.value_ptr.* = SizedIcons{};
        }

        const size_key = (@as(u30, size.width) << 15) | size.width;

        const gop2 = try gop1.value_ptr.getOrPut(self.allocator, size_key);
        if (!gop2.found_existing) {
            var arena = std.heap.ArenaAllocator.init(self.allocator);
            defer arena.deinit();

            const swidth = @as(usize, size.width);
            const sheight = @as(usize, size.height);

            const pixels = try self.arena.allocator.alloc(Color, swidth * sheight);
            errdefer self.arena.allocator.free(pixels);

            std.mem.set(Color, pixels, Color.transparent);

            const TvgCanvas = struct {
                buffer: [*]Color,

                width: usize,
                height: usize,

                pub fn setPixel(section: @This(), x: isize, y: isize, color: [4]u8) void {
                    const px = std.math.cast(usize, x) catch return;
                    const py = std.math.cast(usize, y) catch return;

                    if (px >= section.width or py >= section.height)
                        return;
                    const buf = &section.buffer[section.width * py + px];
                    const dst = buf.*;
                    const src = Color{
                        .r = color[0],
                        .g = color[1],
                        .b = color[2],
                        .a = color[3],
                    };

                    buf.* = Color.alphaBlend(dst, src, src.a);
                }
            };

            tvg.render(
                &arena.allocator,
                TvgCanvas{
                    .buffer = pixels.ptr,
                    .width = swidth,
                    .height = sheight,
                },
                icon,
            ) catch {};

            gop2.value_ptr.* = resource_manager.createTexture(.ui, ResourceManager.RawRgbaTexture{
                .width = size.width,
                .height = size.height,
                .pixels = std.mem.sliceAsBytes(pixels),
            }) catch return error.OutOfMemory;
        }
        return gop2.value_ptr.*;
    }

    pub fn deinit(self: *IconCache) void {
        var outer_it = self.icon_map.iterator();
        while (outer_it.next()) |list| {
            var inner_it = list.value_ptr.iterator();
            while (inner_it.next()) |item| {
                self.resource_manager.destroyTexture(item.value_ptr.*);
            }
            list.value_ptr.deinit(self.allocator);
        }
        self.icon_map.clearRetainingCapacity();
        self.icon_map.deinit(self.allocator);
        self.arena.deinit();
        self.* = undefined;
    }
};

/// Time period after which a normal click is recognized as a long-click.
const long_click_period = 1000 * std.time.ns_per_ms;

/// Time period after which a long-click progress marker is shown
const long_click_indicator_period = long_click_period / 10;

/// Number of horizontal or vertical pixels one must drag the mouse
/// before a drag operation will be recognized
const minimal_drag_distance = 16;

allocator: *std.mem.Allocator,
size: Size,
config: *const Config,
mouse_pos: Point,

/// Index of the currently selected .workspace menu item
current_workspace: usize,

/// A list of elements in the workspace bar
menu_items: std.ArrayList(MenuItem),

/// A list of available applications, shown in the app menu
available_apps: std.ArrayList(AppReference),

mode: MouseMode,
mouse_down_timestamp: ?i128 = null,
mouse_down_pos: ?Point = null,

resource_manager: *ResourceManager,
renderer: *Renderer2D,

ui: UserInterface,
input_processor: ?UserInterface.InputProcessor = null,

app_title_font: *const Renderer2D.Font,
app_status_font: *const Renderer2D.Font,
app_button_font: *const Renderer2D.Font,

icon_cache: IconCache,

context_menu: ?ContextMenu = null,

pub fn init(allocator: *std.mem.Allocator, resource_manager: *ResourceManager, renderer: *Renderer2D, config: *const Config) !Self {
    var self = Self{
        .allocator = allocator,
        .size = Size{ .width = 0, .height = 0 },
        .menu_items = std.ArrayList(MenuItem).init(allocator),
        .config = config,
        .mouse_pos = Point{ .x = 0, .y = 0 },
        .current_workspace = 2, // first workspace after app_menu, separator
        .mode = .default,
        .available_apps = std.ArrayList(AppReference).init(allocator),
        .app_title_font = undefined,
        .app_status_font = undefined,
        .app_button_font = undefined,
        .ui = undefined,
        .resource_manager = resource_manager,
        .renderer = renderer,
        .icon_cache = .{
            .resource_manager = resource_manager,
            .allocator = allocator,
            .icon_map = .{},
            .arena = std.heap.ArenaAllocator.init(allocator),
        },
    };

    const ttf_font_data = @embedFile("fonts/firasans-regular.ttf");

    self.app_title_font = try renderer.createFont(ttf_font_data, 30);
    errdefer renderer.destroyFont(self.app_title_font);

    self.app_status_font = try renderer.createFont(ttf_font_data, 20);
    errdefer renderer.destroyFont(self.app_status_font);

    self.app_button_font = try renderer.createFont(ttf_font_data, 12);
    errdefer renderer.destroyFont(self.app_button_font);

    self.ui = try UserInterface.init(self.allocator, renderer);
    errdefer self.ui.deinit();

    self.ui.theme = &ui_theme;

    // std.json.stringify(self.config, .{
    //     .whitespace = .{
    //         .indent = .Tab,
    //         .separator = true,
    //     },
    // }, std.io.getStdOut().writer()) catch {};

    try self.menu_items.append(MenuItem{ .button = Button{ .data = .app_menu } });
    try self.menu_items.append(.separator);
    try self.menu_items.append(MenuItem{ .button = Button{ .data = .{ .workspace = Workspace.init(allocator) } } });
    try self.menu_items.append(MenuItem{ .button = Button{ .data = .{ .workspace = Workspace.init(allocator) } } });

    return self;
}

pub fn deinit(self: *Self) void {
    for (self.menu_items.items) |*item| {
        switch (item.*) {
            .button => |*b| b.deinit(self),
            else => {},
        }
    }
    self.menu_items.deinit();
    self.available_apps.deinit();
    self.* = undefined;
}

pub fn setAvailableApps(self: *Self, apps: []const *ApplicationDescription) !void {
    // TODO: Do a proper button matching here:
    const old_len = self.available_apps.items.len;
    try self.available_apps.resize(apps.len);
    for (self.available_apps.items) |*app, i| {
        const need_init = if (i < old_len)
            app.application != apps[i] // only change when the app description is different
        else
            true;

        if (need_init) {
            // always initialize fresh
            app.* = AppReference.init(apps[i]);
        }
    }
}

fn openAppMenu(self: *Self) void {
    self.mode = .app_menu;
    logger.debug("open app menu", .{});
}

pub fn resize(self: *Self, size: Size) !void {
    self.size = size;
}

pub fn beginInput(self: *Self) !void {
    std.debug.assert(self.input_processor == null);
    self.input_processor = self.ui.processInput();
}
pub fn endInput(self: *Self) !void {
    std.debug.assert(self.input_processor != null);
    self.input_processor.?.finish();
    self.input_processor = null;
}

pub fn setMousePos(self: *Self, pos: Point) void {
    std.debug.assert(self.input_processor != null);

    self.input_processor.?.setPointer(pos);

    self.mouse_pos = pos;
}

var rng = std.rand.DefaultPrng.init(0);

pub fn mouseDown(self: *Self, mouse_button: zerog.Input.MouseButton) !void {
    _ = mouse_button;

    std.debug.assert(self.input_processor != null);

    self.mouse_down_timestamp = std.time.nanoTimestamp();
    self.mouse_down_pos = self.mouse_pos;

    self.input_processor.?.pointerDown();

    // switch (self.mode) {
    //     .default => {
    //         // Check if the user pressed the mouse on a button
    //         for (self.menu_items.items) |btn, i| {
    //             const rect = self.getMenuButtonRectangle(i);
    //             if (rect.contains(self.mouse_pos)) {
    //                 if (btn == .button and btn.button.state.enabled) {
    //                     self.mode = .{ .button_press = i };
    //                 }
    //                 return;
    //             }
    //         }
    //     },
    //     .button_press => unreachable,
    //     .app_menu => {
    //         const app_menu = self.getAppMenuRectangle();

    //         if (app_menu.contains(self.mouse_pos)) {

    //             // Check if the user pressed the mouse on a button
    //             for (self.available_apps.items) |app, i| {
    //                 const rect = self.getAppButtonRectangle(i);
    //                 if (rect.contains(self.mouse_pos)) {
    //                     if (app.application.state == .ready) {
    //                         self.mode = .{ .app_press = .{
    //                             .index = i,
    //                             .position = self.mouse_pos,
    //                         } };
    //                     }
    //                     return;
    //                 }
    //             }
    //         } else {
    //             self.mode = .default;
    //         }
    //     },
    //     .app_press, .app_drag_menu, .app_drag_desktop => unreachable,
    // }
}

pub fn mouseUp(self: *Self, mouse_button: zerog.Input.MouseButton) !void {
    std.debug.assert(self.input_processor != null);

    if (mouse_button != .primary)
        return;

    const long_click = if (self.mouse_down_timestamp) |ts|
        (std.time.nanoTimestamp() - ts) > long_click_period
    else
        false;
    self.mouse_down_timestamp = null;
    self.mouse_down_pos = null;

    self.input_processor.?.pointerUp(if (long_click or mouse_button == .secondary)
        UserInterface.Pointer.secondary
    else
        UserInterface.Pointer.primary);

    switch (self.mode) {
        .default, .button_press, .app_menu, .app_press => {
            // do nothing on a mouse-up, we process clicks via .button_press
        },
        .app_drag_menu => {
            // we are dragging an app over the app menu, just cancel and go back to app_menu
            self.mode = .app_menu;
        },
        .app_drag_desktop => |app_index| {
            // We dragged the application over the desktop, so we will for sure
            // return to normal mode
            self.mode = .default;

            const app = &self.available_apps.items[app_index];

            const new_workspace_rect = self.getMenuButtonRectangle(self.menu_items.items.len);
            const workspace_rect = self.getWorkspaceRectangle();

            const InsertLocation = enum { replace_center, cursor };

            var target_workspace: ?*Workspace = null;
            var insert_location: InsertLocation = .replace_center;

            if (new_workspace_rect.contains(self.mouse_pos)) {
                // create app in new workspace

                const menu_item = try self.menu_items.addOne();
                menu_item.* = MenuItem{
                    .button = Button{
                        .data = Button.Data{
                            .workspace = Workspace.init(self.allocator),
                        },
                    },
                };
                target_workspace = &menu_item.button.data.workspace;

                self.current_workspace = (self.menu_items.items.len - 1);
                insert_location = .replace_center;
            } else if (workspace_rect.contains(self.mouse_pos)) {
                // create new subdiv
                target_workspace = &self.menu_items.items[self.current_workspace].button.data.workspace;
                insert_location = .cursor;
            }

            if (target_workspace) |workspace| {
                logger.info("spawning on the app[{d}] '{s}'", .{ app_index, app.application.display_name });

                const target_location_opt = switch (insert_location) {
                    .cursor => workspace.window_tree.findInsertLocation(
                        workspace_rect,
                        self.mouse_pos.x,
                        self.mouse_pos.y,
                    ),
                    .replace_center => WindowTree.NodeInsertLocation{
                        .path = undefined,
                        .path_len = 0,
                        .position = .replace,
                    },
                };

                if (target_location_opt) |target_location| {
                    const app_instance = try app.application.spawn(self.allocator);

                    var node = WindowTree.Node{
                        .starting = AppInstance{
                            .application = app_instance,
                        },
                    };

                    try workspace.window_tree.insertLeaf(target_location, node, self);
                }
            } else {
                logger.info("cancel spawn of app[{d}] '{s}'", .{ app_index, app.application.display_name });
            }
        },
    }
}

fn isDragDistanceReached(self: Self, start: Point) bool {
    const dx = std.math.absCast(self.mouse_pos.x - start.x);
    const dy = std.math.absCast(self.mouse_pos.y - start.y);
    return (dx >= minimal_drag_distance or dy >= minimal_drag_distance);
}

const ContextMenu = struct {
    const Data = union(enum) {
        app_instance: *AppInstance,
        app_info: *AppReference,
    };
    data: Data,
    position: Point,
};

fn openContextMenu(self: *Self, data: ContextMenu.Data) void {
    self.context_menu = ContextMenu{
        .position = self.mouse_down_pos orelse self.mouse_pos,
        .data = data,
    };
}
fn closeContextMenu(self: *Self) void {
    self.context_menu = null;
}

const ContextMenuResult = union(enum) {
    none,
    clicked: usize,
    closed,
};

fn doContextMenu(self: Self, builder: UserInterface.Builder, focus_point: Point, title: []const u8, menu_items: []const MouseMode.ContextMenuItem) !ContextMenuResult {
    const width = 210;
    const height = @intCast(u15, 40 * (menu_items.len + 1)) + 1;

    const menu_rectangle = Rectangle{
        .x = std.math.clamp(focus_point.x - width / 2, 0, self.size.width),
        .y = std.math.clamp(focus_point.y - (height - 40) / 2 - 40, 0, self.size.height),
        .width = width,
        .height = height,
    };

    if (try builder.modalLayer(.{})) {
        return .closed;
    }

    try builder.panel(menu_rectangle, .{});

    const header_rectangle = Rectangle{
        .x = menu_rectangle.x,
        .y = menu_rectangle.y,
        .width = menu_rectangle.width,
        .height = 32,
    };

    try builder.panel(header_rectangle, .{
        .style = ui_contextmenu_panel_theme,
    });
    try builder.label(header_rectangle, title, .{
        .horizontal_alignment = .center,
    });

    var button_rectangle = header_rectangle;
    button_rectangle.x += 9;
    button_rectangle.width -= 18;

    var clicked_item: ?usize = null;

    for (menu_items) |item, i| {
        button_rectangle.y += 40;
        const clicked = try builder.button(button_rectangle, item.title, null, .{
            .id = i,
            .enabled = item.enabled,
        });
        if (clicked) {
            clicked_item = i;
        }
    }
    if (clicked_item) |item|
        return ContextMenuResult{ .clicked = item };
    return .none;
}

pub fn update(self: *Self, dt: f32) !void {

    // Update all running applications
    {
        for (self.menu_items.items) |*menu_item| {
            if (menu_item.* != .button)
                continue;
            if (menu_item.button.data != .workspace)
                continue;
            // logger.info("leafes on workspace {d}", .{index});

            const workspace: *Workspace = &menu_item.button.data.workspace;

            var leaf_iterator = workspace.window_tree.leafIterator();

            while (leaf_iterator.next()) |leaf| {
                // logger.info("  available node: {}", .{leaf});
                switch (leaf.*) {
                    .starting, .connected, .exited => {
                        try updateAppInstance(leaf, dt);
                    },
                    .empty, .group => {
                        // those have no update logic, but .group might be animated in the future which would go here
                    },
                }
            }
        }
    }

    var builder = self.ui.construct(self.size);
    defer builder.finish();

    // Update workspaces
    {
        const workspace_area = self.getWorkspaceRectangle();
        for (self.menu_items.items) |*item, button_index| {
            switch (item.*) {
                .button => |*btn| {
                    if (btn.data == .workspace) {
                        if (button_index == self.current_workspace) {
                            var hovered_rectangle: ?Rectangle = null;
                            try self.updateWorkspace(builder, workspace_area, &btn.data.workspace, &hovered_rectangle);

                            // if (self.mode != .app_menu) {
                            //     if (hovered_rectangle) |area| {
                            //         try renderer.drawRectangle(area, self.config.workspace.active_app_border);
                            //     }
                            // }

                            if (self.mode == .app_drag_desktop) {
                                if (btn.data.workspace.window_tree.findInsertLocation(workspace_area, self.mouse_pos.x, self.mouse_pos.y)) |path| {
                                    const insert_location = btn.data.workspace.window_tree.getInsertLocationRectangle(workspace_area, path);

                                    try builder.panel(insert_location.splitter.shrink(1), .{
                                        .style = ui_split_panel,
                                    });

                                    // try renderer.drawRectangle(insert_location.container, self.config.workspace.insert_highlight_color);
                                    // try renderer.fillRectangle(insert_location.splitter, self.config.workspace.insert_highlight_fill_color);
                                }
                            }
                            break;
                        }
                    }
                },
                else => {},
            }
        }
    }

    const dragged_app_index: ?usize = switch (self.mode) {
        .app_drag_desktop => |index| index,
        .app_drag_menu => |index| index,
        else => null,
    };

    // Update workspace bar
    {
        try builder.panel(self.getBarRectangle(), .{});

        for (self.menu_items.items) |item, button_index| {
            const button_rect = self.getMenuButtonRectangle(button_index);

            if (item == .button) {
                const button = &item.button;

                const icon = switch (button.data) {
                    .app_menu => @as([]const u8, &icons.app_menu),
                    .workspace => &icons.workspace,
                };

                const texture = try self.icon_cache.get(icon, self.getPhysicalSize(Size{ .width = 48, .height = 48 }));

                const style = if (button.data == .workspace and button_index == self.current_workspace)
                    ui_workspace_bar_current_button_theme
                else
                    ui_workspace_bar_button_theme;

                if (try builder.button(button_rect, null, texture, .{ .style = style })) {
                    switch (button.data) {
                        .app_menu => {
                            self.openAppMenu();
                        },
                        .workspace => {
                            self.current_workspace = button_index;
                        },
                    }
                }
            }
        }

        if (dragged_app_index) |_| {
            const button_rect = self.getMenuButtonRectangle(self.menu_items.items.len);
            const texture = try self.icon_cache.get(&icons.workspace_add, self.getPhysicalSize(Size{ .width = 48, .height = 48 }));
            const style = if (button_rect.contains(self.mouse_pos))
                ui_workspace_bar_current_button_theme
            else
                ui_workspace_bar_button_theme;
            _ = try builder.button(button_rect, null, texture, .{ .style = style });
        }
    }

    // Update app menu
    if (self.mode.isAppMenuVisible()) app_menu: {
        if (try builder.modalLayer(.{})) {
            self.mode = .default;
            break :app_menu;
        }

        // TODO: Render custom widget here for the menu corner

        try builder.panel(self.getAppMenuRectangle(), .{
            .style = ui_app_menu_panel_theme,
        });

        for (self.available_apps.items) |*app, idx| {
            const button_rect = self.getAppButtonRectangle(idx);

            switch (try self.appButton(builder, button_rect, app, false)) {
                .none => {},
                .clicked => logger.info("app button was clicked!", .{}),
                .dragged => self.mode = .{ .app_drag_menu = idx },
                .context_menu_requested => self.openContextMenu(.{ .app_info = app }),
            }
        }
    } else {
        // When the menu is hidden, we can se
        for (self.available_apps.items) |*app| {
            if (app.application.state == .gone) {
                app.application.destroy() catch |err| logger.err("could not remove application icon '{s}': {}", .{
                    app.application.display_name,
                    err,
                });
            }
        }
    }

    if (dragged_app_index) |index| {
        const app = &self.available_apps.items[index];
        const button_size = self.config.app_menu.button_size;

        const button_rect = Rectangle{
            .x = self.mouse_pos.x - button_size / 2,
            .y = self.mouse_pos.y - button_size / 2,
            .width = button_size,
            .height = button_size,
        };

        _ = try self.appButton(builder, button_rect, app, true);
    }

    if (self.context_menu) |context_menu| {
        switch (context_menu.data) {
            .app_info => |info| {
                const items = [_]MouseMode.ContextMenuItem{
                    .{ .title = "Remove", .enabled = (info.application.state == .gone) },
                    // .{ .title = "Move to workspace", .enabled = false },
                    // .{ .title = "Move to own workspace" },
                };

                const result = try self.doContextMenu(builder, context_menu.position, info.application.display_name, &items);
                switch (result) {
                    .none => {},
                    .clicked => |index| switch (index) {
                        0 => if (info.application.destroy()) |_| {
                            self.closeContextMenu();
                        } else |err| {
                            logger.err("Could not destroy application: {}", .{err});
                        },
                        else => unreachable,
                    },
                    .closed => self.closeContextMenu(),
                }
            },

            .app_instance => |instance| {
                if (instance.application.status == .exited) {
                    const items = [_]MouseMode.ContextMenuItem{
                        .{ .title = "Collapse window" },
                    };

                    const result = try self.doContextMenu(builder, context_menu.position, instance.application.description.display_name, &items);
                    switch (result) {
                        .none => {},
                        .clicked => |index| switch (index) {
                            0 => logger.err("\"collapse window\" not implemented yet", .{}),

                            else => unreachable,
                        },
                        .closed => self.closeContextMenu(),
                    }
                } else {
                    const items = [_]MouseMode.ContextMenuItem{
                        // TODO: Implement a way to move windows between
                        .{ .title = "Move to workspace...", .enabled = false },
                        .{ .title = "Close application" },
                    };

                    const result = try self.doContextMenu(builder, context_menu.position, instance.application.description.display_name, &items);
                    switch (result) {
                        .none => {},
                        .clicked => |index| switch (index) {
                            0 => logger.err("\"move to workspace\" not implemented yet", .{}),
                            1 => {
                                instance.application.close();
                                self.closeContextMenu();
                            },

                            else => unreachable,
                        },
                        .closed => self.closeContextMenu(),
                    }
                }
            },
        }
    }

    // Check if we dragged the icon out of the app menu
    if (self.mode == .app_drag_menu) {
        const app_menu_rect = self.getAppMenuRectangle();

        if (!app_menu_rect.contains(self.mouse_pos)) {
            // RLS bug workaround
            const index = self.mode.app_drag_menu;
            self.mode = .{ .app_drag_desktop = index };
        }
    }

    // Check if we dragged over a workspace button
    if (self.mode == .app_drag_desktop) {
        for (self.menu_items.items) |*item, idx| {
            if (item.* == .button) {
                if (item.button.data == .workspace) {
                    const button_rect = self.getMenuButtonRectangle(idx);
                    if (button_rect.contains(self.mouse_pos)) {
                        if (self.current_workspace != idx) {
                            logger.info("Select workspace {d}", .{idx});
                        }

                        self.current_workspace = idx;
                    }
                }
            }
        }
    }

    // Update all the buttons here:

    {
        var hovered_button: ?usize = null;
        switch (self.mode) {
            .default, .button_press => {
                hovered_button = for (self.menu_items.items) |_, idx| {
                    const button_rect = self.getMenuButtonRectangle(idx);
                    if (button_rect.contains(self.mouse_pos))
                        break idx;
                } else null;
            },
            .app_menu, .app_press, .app_drag_desktop, .app_drag_menu => {},
        }
    }

    {
        var hovered_app: ?usize = null;
        switch (self.mode) {
            .default, .button_press => {},
            .app_menu, .app_press => {
                hovered_app = for (self.available_apps.items) |_, idx| {
                    const button_rect = self.getAppButtonRectangle(idx);
                    if (button_rect.contains(self.mouse_pos))
                        break idx;
                } else null;
            },
            .app_drag_desktop, .app_drag_menu => {},
        }
    }
}

fn updateWorkspace(self: *Self, builder: UserInterface.Builder, area: Rectangle, workspace: *Workspace, hovered_rectangle: *?Rectangle) !void {
    try self.updateTreeNode(builder, area, &workspace.window_tree.root, hovered_rectangle);
}

fn processAppNodeEvent(custom: UserInterface.CustomWidget, event: UserInterface.CustomWidget.Event) ?usize {
    const self = @ptrCast(*Self, @alignCast(@alignOf(Self), custom.config.context orelse unreachable));
    const app = @ptrCast(*AppInstance, @alignCast(@alignOf(AppInstance), custom.user_data orelse unreachable));

    switch (event) {
        .pointer_enter => {},
        .pointer_leave => {
            app.mouse_press_location = null;
        },
        .pointer_press => |data| {
            app.mouse_press_location = data;
        },
        .pointer_release => |data| {
            if (app.mouse_press_location) |loc| {
                app.mouse_press_location = null;
                if (!self.isDragDistanceReached(loc)) {
                    if (data.pointer == .secondary) {
                        self.openContextMenu(.{ .app_instance = app });
                        return 0;
                    }
                }
            }
        },
        .pointer_motion => {},
    }

    return null;
}

fn renderAppNode(custom: UserInterface.CustomWidget, area: Rectangle, renderer: *Renderer2D, info: UserInterface.CustomWidget.DrawInfo) Renderer2D.DrawError!void {
    _ = info;

    const self = @ptrCast(*Self, @alignCast(@alignOf(Self), custom.config.context orelse unreachable));
    const app = @ptrCast(*AppInstance, @alignCast(@alignOf(AppInstance), custom.user_data orelse unreachable));

    switch (app.application.status) {
        .starting => try self.renderStartingAppNode(app, area, renderer),
        .running => try self.renderRunningAppNode(app, area, renderer),
        .exited => try self.renderExitedAppNode(app, area, renderer),
    }
}

fn renderStartingAppNode(self: *Self, app: *AppInstance, area: Rectangle, renderer: *Renderer2D) Renderer2D.DrawError!void {
    _ = renderer;
    const icon_size = std.math.min(area.width - 2, self.config.workspace.app_icon_size);
    if (icon_size > 0) {
        try self.drawIcon(
            Rectangle{
                .x = area.x + (area.width - icon_size) / 2,
                .y = area.y + (area.height - icon_size) / 2,
                .width = icon_size,
                .height = icon_size,
            },
            app.application.description.icon orelse icons.app_placeholder,
            Color.white,
        );
    }

    const display_name = app.application.description.display_name;
    if (display_name.len > 0) {
        const size = self.renderer.measureString(self.app_title_font, display_name);
        try self.renderer.drawString(
            self.app_title_font,
            display_name,
            area.x + (area.width - size.width) / 2,
            area.y + (area.height - icon_size) / 2 - self.app_title_font.font_size,
            .{ .r = 0xFF, .g = 0xFF, .b = 0xFF }, // TODO: Replace by theme config
        );
    }

    const startup_message = app.application.status.starting; // this is safe as the status might only be changed in the update fn
    if (startup_message.len > 0) {
        const size = self.renderer.measureString(self.app_status_font, startup_message);
        try self.renderer.drawString(
            self.app_status_font,
            startup_message,
            area.x + (area.width - size.width) / 2,
            area.y + (area.height + icon_size) / 2,
            .{ .r = 0xFF, .g = 0xFF, .b = 0xFF }, // TODO: Replace by theme config
        );
    }
}

fn renderRunningAppNode(self: *Self, app: *AppInstance, area: Rectangle, renderer: *Renderer2D) Renderer2D.DrawError!void {
    _ = self;
    _ = renderer;
    app.application.render(area, renderer) catch |err| logger.err("failed to render application '{s}': {s}", .{
        app.application.description.display_name,
        @errorName(err),
    });
}

fn renderExitedAppNode(self: *Self, app: *AppInstance, area: Rectangle, renderer: *Renderer2D) Renderer2D.DrawError!void {
    const exit_message = app.application.status.exited; // this is safe as the status might only be changed in the update fn
    if (exit_message.len > 0) {
        const size = renderer.measureString(self.app_status_font, exit_message);
        try renderer.drawString(
            self.app_status_font,
            exit_message,
            area.x + (area.width - size.width) / 2,
            area.y + area.height / 2,
            .{ .r = 0xFF, .g = 0x00, .b = 0x00 }, // TODO: Replace by theme config
        );
    }
}

fn updateTreeNode(self: *Self, builder: UserInterface.Builder, area: Rectangle, node: *WindowTree.Node, hovered_rectangle: *?Rectangle) ApplicationInstance.Interface.UiError!void {
    const is_hovered = area.contains(self.mouse_pos);
    if (is_hovered and (node.* == .empty or node.* == .starting or node.* == .connected)) {
        hovered_rectangle.* = area;
    }

    const panel_style = if (is_hovered)
        ui_active_window_panel_theme
    else
        ui_window_panel_theme;

    try builder.panel(area, .{
        .id = node,
        .style = panel_style,
    });

    switch (node.*) {
        .empty => {},
        .starting, .connected, .exited => |*app| {
            _ = try builder.custom(area.shrink(1), app, .{
                .id = node,
                .draw = renderAppNode,
                .context = self,
                .process_event = processAppNodeEvent,
            });

            if (node.* == .connected and app.application.status == .running) {
                try app.application.processUserInterface(area.shrink(1), builder);
            }
        },
        .group => |*group| {
            // if we have 1 or less children, the tree would be denormalized.
            // we assume we have a normalized tree at this point.
            std.debug.assert(group.children.len >= 2);
            switch (group.split) {
                .vertical => {
                    const item_height = area.height / group.children.len;
                    for (group.children) |*item, i| {
                        const h = if (i == group.children.len - 1)
                            item_height
                        else
                            (area.height - item_height * (group.children.len - 1));
                        var child_area = area;
                        child_area.y += @intCast(u15, item_height * i);
                        child_area.height = @intCast(u15, h);
                        try self.updateTreeNode(builder, child_area, item, hovered_rectangle);
                    }
                },
                .horizontal => {
                    const item_width = area.width / group.children.len;
                    for (group.children) |*item, i| {
                        const w = if (i == group.children.len - 1)
                            item_width
                        else
                            (area.width - item_width * (group.children.len - 1));
                        var child_area = area;
                        child_area.x += @intCast(u15, item_width * i);
                        child_area.width = @intCast(u15, w);
                        try self.updateTreeNode(builder, child_area, item, hovered_rectangle);
                    }
                },
            }
        },
    }
}

// const SubCanvas = struct {
//     canvas: *Canvas,

//     alpha: f32 = 1.0,
//     x: isize,
//     y: isize,
//     width: usize,
//     height: usize,

//     pub fn setPixel(section: @This(), x: isize, y: isize, color: [4]u8) void {
//         if (x < 0 or y < 0)
//             return;
//         if (x >= section.width or y >= section.height)
//             return;
//         section.canvas.setPixel(section.x + x, section.y + y, Color{
//             .r = color[0],
//             .g = color[1],
//             .b = color[2],
//             .a = @floatToInt(u8, section.alpha * @intToFloat(f32, color[3])),
//         });
//     }
// };

const RenderError = error{OutOfMemory} || zerog.Renderer2D.DrawError;
pub fn render(self: *Self) RenderError!void {
    const renderer = self.renderer;

    try self.ui.render();

    // Long-click activity rendering
    if (self.mouse_down_timestamp) |ts| {
        if (self.mouse_down_pos) |mdp| {
            if (!self.isDragDistanceReached(mdp)) {
                const delta = std.math.clamp(std.time.nanoTimestamp() - ts, 0, long_click_period);
                if (delta >= long_click_indicator_period) {
                    const Helper = struct {
                        center: Point,

                        fn getFromAngle(help: @This(), radius: f32, a: f32) Point {
                            var dx = std.math.round(radius * std.math.sin(a));
                            var dy = std.math.round(radius * std.math.cos(a));
                            return Point{
                                .x = help.center.x + @floatToInt(i16, dx),
                                .y = help.center.y - @floatToInt(i16, dy),
                            };
                        }
                    };

                    const delta_f = @intToFloat(f32, delta) / @intToFloat(f32, long_click_period);

                    const segment_count: usize = 36; // 10° max

                    const helper = Helper{
                        .center = mdp,
                    };

                    const inner_radius = 16;
                    const outer_radius = 24;

                    {
                        var last_inner = helper.getFromAngle(inner_radius, 0);
                        var last_outer = helper.getFromAngle(outer_radius, 0);

                        var i: usize = 1;
                        while (i <= segment_count) : (i += 1) {
                            const a = 2.0 * std.math.pi * @intToFloat(f32, i) / @intToFloat(f32, segment_count);

                            const current_inner = helper.getFromAngle(inner_radius, delta_f * a);
                            const current_outer = helper.getFromAngle(outer_radius, delta_f * a);

                            try renderer.fillQuad(
                                [4]Point{
                                    last_inner,
                                    last_outer,
                                    current_inner,
                                    current_outer,
                                },
                                self.config.longclick_indicator.fill_color,
                            );

                            last_inner = current_inner;
                            last_outer = current_outer;
                        }
                    }

                    {
                        var last_inner = helper.getFromAngle(inner_radius, 0);
                        var last_outer = helper.getFromAngle(outer_radius, 0);

                        var i: usize = 1;
                        while (i <= segment_count) : (i += 1) {
                            const a = 2.0 * std.math.pi * @intToFloat(f32, i) / @intToFloat(f32, segment_count);

                            const current_inner = helper.getFromAngle(inner_radius, a);
                            const current_outer = helper.getFromAngle(outer_radius, a);

                            try renderer.drawLine(
                                last_outer.x,
                                last_outer.y,
                                current_outer.x,
                                current_outer.y,
                                self.config.longclick_indicator.outline,
                            );
                            try renderer.drawLine(
                                last_inner.x,
                                last_inner.y,
                                current_inner.x,
                                current_inner.y,
                                self.config.longclick_indicator.outline,
                            );

                            last_inner = current_inner;
                            last_outer = current_outer;
                        }
                    }
                }
            }
        }
    }
}

fn getPhysicalSize(self: Self, virtual_size: Size) Size {
    const ratio = self.renderer.unit_to_pixel_ratio;
    return Size{
        .width = @floatToInt(u15, ratio * @intToFloat(f32, virtual_size.width)),
        .height = @floatToInt(u15, ratio * @intToFloat(f32, virtual_size.height)),
    };
}

fn drawIcon(self: *Self, target: Rectangle, icon: []const u8, tint: Color) !void {
    const physical_size = self.getPhysicalSize(target.size());

    const texture = try self.icon_cache.get(icon, physical_size);

    try self.renderer.fillTexturedRectangle(
        target,
        texture,
        tint,
    );
}

fn initColor(r: u8, g: u8, b: u8, a: u8) Color {
    return Color{ .r = r, .g = g, .b = b, .a = a };
}

fn alphaBlend(c: u8, f: f32) u8 {
    return @floatToInt(u8, f * @intToFloat(f32, c));
}

const AppButtonResult = enum(usize) {
    none = 0,
    clicked = 1,
    dragged = 2,
    context_menu_requested = 3,
};

/// A startable application available in the app menu.
const AppReference = struct {
    application: *ApplicationDescription,

    mouse_press_location: ?Point = null,

    fn init(app: *ApplicationDescription) AppReference {
        return .{
            .application = app,
        };
    }
};

fn appButton(
    self: *Self,
    builder: UserInterface.Builder,
    rectangle: Rectangle,
    app: *AppReference,
    translucent: bool,
) !AppButtonResult {
    var render_fn = if (translucent)
        renderApplicationButtonWidgetTranslucent
    else
        renderApplicationButtonWidgetOpaque;

    const result = try builder.custom(rectangle, app, .{
        .id = app,
        .draw = render_fn,
        .context = self,
        .process_event = processApplicationButtonWidgetEvent,
    });
    return @intToEnum(AppButtonResult, result orelse @enumToInt(AppButtonResult.none));
}

fn processApplicationButtonWidgetEvent(custom: UserInterface.CustomWidget, event: UserInterface.CustomWidget.Event) ?usize {
    const self = @ptrCast(*Self, @alignCast(@alignOf(Self), custom.config.context orelse unreachable));
    const app = @ptrCast(*AppReference, @alignCast(@alignOf(AppReference), custom.user_data orelse unreachable));

    switch (event) {
        .pointer_enter => {},
        .pointer_leave => {
            app.mouse_press_location = null;
        },
        .pointer_press => |data| {
            app.mouse_press_location = data;
        },
        .pointer_release => |data| {
            if (app.mouse_press_location) |loc| {
                app.mouse_press_location = null;
                if (!self.isDragDistanceReached(loc)) {
                    if (data.pointer == .primary) {
                        return @enumToInt(AppButtonResult.clicked);
                    } else {
                        return @enumToInt(AppButtonResult.context_menu_requested);
                    }
                }
            }
        },
        .pointer_motion => {
            if (app.mouse_press_location) |loc| {
                if (app.application.state == .ready and self.isDragDistanceReached(loc)) {
                    return @enumToInt(AppButtonResult.dragged);
                }
            }
        },
    }

    return null;
}

fn renderApplicationButtonWidgetTranslucent(
    custom: UserInterface.CustomWidget,
    rectangle: Rectangle,
    renderer: *Renderer2D,
    info: UserInterface.CustomWidget.DrawInfo,
) Renderer2D.DrawError!void {
    try renderApplicationButtonWidget(custom, rectangle, renderer, info, 0.5);
}

fn renderApplicationButtonWidgetOpaque(
    custom: UserInterface.CustomWidget,
    rectangle: Rectangle,
    renderer: *Renderer2D,
    info: UserInterface.CustomWidget.DrawInfo,
) Renderer2D.DrawError!void {
    try renderApplicationButtonWidget(custom, rectangle, renderer, info, 1.0);
}

fn renderApplicationButtonWidget(
    custom: UserInterface.CustomWidget,
    rectangle: Rectangle,
    renderer: *Renderer2D,
    info: UserInterface.CustomWidget.DrawInfo,
    alpha: f32,
) Renderer2D.DrawError!void {
    const self = @ptrCast(*Self, @alignCast(@alignOf(Self), custom.config.context orelse unreachable));
    const app = @ptrCast(*AppReference, @alignCast(@alignOf(AppReference), custom.user_data orelse unreachable));

    const style = if (app.application.state != .ready)
        self.config.app_menu.button_theme.disabled
    else if (info.is_pressed)
        self.config.app_menu.button_theme.clicked
    else if (info.is_hovered)
        self.config.app_menu.button_theme.hovered
    else
        self.config.app_menu.button_theme.default;

    const byte_alpha = @floatToInt(u8, 255.0 * alpha);

    var back_color = style.background;
    var outline_color = style.outline;

    back_color.a = @floatToInt(u8, @intToFloat(f32, back_color.a) * alpha);
    outline_color.a = @floatToInt(u8, @intToFloat(f32, outline_color.a) * alpha);

    const icon = app.application.icon orelse icons.app_placeholder;
    const label = app.application.display_name;

    try renderer.fillRectangle(rectangle, back_color);
    try renderer.drawRectangle(rectangle, outline_color);

    const icon_size = std.math.min(rectangle.width - 2, self.config.app_menu.button_theme.icon_size);

    if (icon_size > 0) {
        try self.drawIcon(
            rectangle.centered(icon_size, icon_size),
            icon,
            Color{ .r = 0xFF, .g = 0xFF, .b = 0xFF, .a = byte_alpha },
        );
    }
    {
        const top = ((rectangle.height + icon_size) / 2 + rectangle.height) / 2;

        const size = renderer.measureString(self.app_button_font, label);

        try renderer.drawString(
            self.app_button_font,
            label,
            rectangle.x + clampSub(rectangle.width, size.width) / 2,
            rectangle.y + @intCast(u15, clampSub(top, self.app_button_font.font_size / 2)),
            .{ .r = 0xFF, .g = 0xFF, .b = 0xFF, .a = byte_alpha }, // TODO: Introduce proper config here
        );
    }
}

fn clampSub(a: u15, b: anytype) u15 {
    return if (b < a)
        @intCast(u15, a - b)
    else
        0;
}

fn getBarRectangle(self: Self) Rectangle {
    const bar_width = self.config.workspace_bar.getWidth();
    return switch (self.config.workspace_bar.location) {
        .top => Rectangle{ .x = 0, .y = 0, .width = self.size.width, .height = bar_width },
        .bottom => Rectangle{ .x = 0, .y = self.size.height - bar_width, .width = self.size.width, .height = bar_width },
        .left => Rectangle{ .x = 0, .y = 0, .width = bar_width, .height = self.size.height },
        .right => Rectangle{ .x = self.size.width - bar_width, .y = 0, .width = bar_width, .height = self.size.height },
    };
}

fn getWorkspaceRectangle(self: Self) Rectangle {
    const bar_width = self.config.workspace_bar.getWidth();
    return switch (self.config.workspace_bar.location) {
        .top => Rectangle{ .x = 0, .y = bar_width + 1, .width = self.size.width, .height = self.size.height - bar_width },
        .bottom => Rectangle{ .x = 0, .y = 0, .width = self.size.width, .height = self.size.height - bar_width },
        .left => Rectangle{ .x = bar_width + 1, .y = 0, .width = self.size.width - bar_width - 1, .height = self.size.height },
        .right => Rectangle{ .x = 0, .y = 0, .width = self.size.width - bar_width - 1, .height = self.size.height },
    };
}

const AppMenuLayout = struct {
    rows: u15,
    cols: u15,
};

/// This function computes the layout (number of rows/cols) for the application
/// menu and tries to get as close as possible to 
fn getAppMenuLayout(self: Self) AppMenuLayout {
    const count = self.available_apps.items.len;

    const preferred_aspect: f32 = 4.0 / 3.0;

    const count_f = @intToFloat(f32, count);

    const rows_temp_f = std.math.sqrt(count_f / preferred_aspect);
    const cols_f = std.math.ceil(rows_temp_f * preferred_aspect);
    const rows_f = std.math.ceil(cols_f / preferred_aspect);

    // Minimum layout is 3×2 (roughly requires 300×200)
    const max_cols: u15 = std.math.max(3, (self.size.width - self.config.workspace_bar.getWidth() - 3 * self.config.workspace_bar.margins) / (self.config.app_menu.margins + self.config.app_menu.button_size));
    const max_rows: u15 = std.math.max(2, (self.size.height - self.config.workspace_bar.getWidth() - 2 * self.config.workspace_bar.margins) / (self.config.app_menu.margins + self.config.app_menu.button_size));

    const layout = AppMenuLayout{
        .cols = std.math.clamp(@floatToInt(u15, cols_f), 3, max_cols),
        .rows = std.math.clamp(@floatToInt(u15, rows_f), 2, max_rows),
    };
    // std.debug.assert(layout.rows * layout.cols >= count);

    return layout;
}

fn getAppButtonRectangle(self: Self, index: usize) Rectangle {
    const layout = self.getAppMenuLayout();
    const app_menu_rect = self.getAppMenuRectangle();
    const margin = self.config.app_menu.margins;
    const button_size = self.config.app_menu.button_size;

    const col = @intCast(u15, index) % layout.cols;
    const row = @intCast(u15, index) / layout.cols;

    return Rectangle{
        // 1 is the padding to the outline
        .x = app_menu_rect.x + 1 + margin + col * (margin + button_size),
        .y = app_menu_rect.y + 1 + margin + row * (margin + button_size),
        .width = button_size,
        .height = button_size,
    };
}

fn getAppMenuRectangle(self: Self) Rectangle {
    const app_button_rect = self.getMenuButtonRectangle(0);
    const layout = self.getAppMenuLayout();
    const margin = self.config.app_menu.margins;
    const button_size = self.config.app_menu.button_size;

    // The rectangle has some margins for scroll bar and 1 pixel lines
    const width = @intCast(u15, 3 + 2 * margin + button_size * layout.cols + (layout.cols - 1) * margin + self.config.app_menu.scrollbar_width);
    const height = @intCast(u15, 2 + 2 * margin + button_size * layout.rows + (layout.rows - 1) * margin);

    return switch (self.config.workspace_bar.location) {
        .left => Rectangle{
            .x = app_button_rect.x + app_button_rect.width + margin,
            .y = app_button_rect.y,
            .width = width,
            .height = height,
        },
        .right => Rectangle{
            .x = app_button_rect.x - width - margin,
            .y = app_button_rect.y,
            .width = width,
            .height = height,
        },
        .top => Rectangle{
            .x = app_button_rect.x,
            .y = app_button_rect.y + app_button_rect.height + margin,
            .width = width,
            .height = height,
        },
        .bottom => Rectangle{
            .x = app_button_rect.x,
            .y = app_button_rect.y - height - margin,
            .width = width,
            .height = height,
        },
    };
}

fn getMenuButtonRectangle(self: Self, index: usize) Rectangle {
    var offset: u15 = self.config.workspace_bar.margins;

    for (self.menu_items.items[0..index]) |item| {
        offset += self.config.workspace_bar.margins;
        switch (item) {
            .separator => offset += 1,
            .button => offset += self.config.workspace_bar.button_size,
        }
    }

    const size = if (index < self.menu_items.items.len)
        switch (self.menu_items.items[index]) {
            .separator => 1,
            .button => self.config.workspace_bar.button_size,
        }
    else
        // Assume the item directly after in the list is a button
        // which is used for the "new workspace" button
        self.config.workspace_bar.button_size;

    const base_rect = self.getBarRectangle();

    return switch (self.config.workspace_bar.location) {
        .left, .right => Rectangle{
            .x = base_rect.x + self.config.workspace_bar.margins,
            .y = base_rect.y + offset,
            .width = self.config.workspace_bar.button_size,
            .height = size,
        },
        .top, .bottom => Rectangle{
            .x = base_rect.x + offset,
            .y = base_rect.y + self.config.workspace_bar.margins,
            .width = size,
            .height = self.config.workspace_bar.button_size,
        },
    };
}

const MenuItem = union(enum) {
    separator,
    button: Button,
};

const Button = struct {
    const Data = union(enum) {
        app_menu,
        workspace: Workspace,
    };

    data: Data,

    fn deinit(self: *Button, screen: *Self) void {
        switch (self.data) {
            .workspace => |*ws| ws.deinit(screen),
            else => {},
        }
        self.* = undefined;
    }
};

const Workspace = struct {
    allocator: *std.mem.Allocator,
    window_tree: WindowTree,

    fn init(allocator: *std.mem.Allocator) Workspace {
        return Workspace{
            .allocator = allocator,
            .window_tree = WindowTree{
                .allocator = allocator,
                .root = .empty,
            },
        };
    }

    fn deinit(self: *Workspace, screen: *Self) void {
        self.window_tree.deinit(screen);
        self.* = undefined;
    }
};

fn performAppTransition(leaf: *WindowTree.Node) !void {
    switch (leaf.*) {
        .starting => |*app| {
            if (app.application.status == .running) {
                // workaround for re-tagging with RLS
                var app_copy = app.*;
                leaf.* = .{ .connected = app_copy };
            } else if (app.application.status == .exited) {
                // workaround for re-tagging with RLS
                var app_copy = app.*;
                leaf.* = .{ .exited = app_copy };
            }
        },
        .connected => |*app| {
            std.debug.assert(app.application.status == .running or app.application.status == .exited);
            if (app.application.status == .exited) {
                // workaround for re-tagging with RLS
                var app_copy = app.*;
                leaf.* = .{ .exited = app_copy };
            }
        },
        .exited => |*app| {
            std.debug.assert(app.application.status == .exited);
            // the exited application isn't updated anymore
            // as there is nothing to do here
        },
        else => unreachable,
    }
}

fn updateAppInstance(node: *WindowTree.Node, dt: f32) !void {
    try performAppTransition(node);
    switch (node.*) {
        .starting, .connected => |*app| {
            try app.application.update(dt);
        },
        .exited => {
            // the exited application isn't updated anymore
            // as there is nothing to do here
        },
        else => unreachable,
    }
    try performAppTransition(node);
}

/// A abstract application on the desktop.
/// This might be backed by any application/window provider.
const AppInstance = struct {
    application: *ApplicationInstance,

    mouse_press_location: ?Point = null,

    pub fn deinit(self: *AppInstance, screen: *Self) void {
        if (screen.context_menu != null and screen.context_menu.?.data == .app_instance and screen.context_menu.?.data.app_instance == self)
            screen.closeContextMenu();
        self.application.deinit();
        self.* = undefined;
    }
};

const WindowTree = struct {
    pub const Layout = enum {
        /// Windows are stacked on top of each other.
        vertical,

        /// Windows are side-by-side next to each other
        horizontal,
    };

    pub const Node = union(enum) {
        /// A grouping of several other nodes in vertical or horizontal direction.
        group: Group,

        /// A freshly initialized application that is currently starting up (connecting, loading resources, ...)
        starting: AppInstance,

        /// A ready-to-use application that is fully initialized and has connected to the application server.
        connected: AppInstance,

        /// An application that has been terminated on the remote end and not by the user.
        exited: AppInstance,

        /// A empty node is required to manage empty workspaces
        /// or applications that have exited on their on
        /// and thus will leave empty space on the desktop
        /// instead of collapsing and potentially making the user misclick.
        empty,
    };

    pub const Group = struct {
        split: Layout,
        children: []Node,

        fn getChildRectangle(self: @This(), area: FloatRectangle, child_index: usize) FloatRectangle {
            return switch (self.split) {
                .horizontal => FloatRectangle{
                    .x = area.x + @intToFloat(f32, child_index) * (area.width / @intToFloat(f32, self.children.len)),
                    .y = area.y,
                    .width = area.width / @intToFloat(f32, self.children.len),
                    .height = area.height,
                },
                .vertical => FloatRectangle{
                    .x = area.x,
                    .y = area.y + @intToFloat(f32, child_index) * (area.height / @intToFloat(f32, self.children.len)),
                    .width = area.width,
                    .height = area.height / @intToFloat(f32, self.children.len),
                },
            };
        }
    };

    pub const NodeInsertLocation = struct {
        /// path to find the final node to insert.
        /// empty path selects the root node.
        path: [max_depth]usize,

        /// Number of elements in the `path`
        path_len: usize = 0,

        /// The position where the element is inserted.
        position: Position,

        const Position = union(enum) {

            /// Inserts the node into a group node.
            /// This is only valid when the selected node
            /// is a group node.
            /// The value will give the new index of the inserted node.
            insert_in_group: usize,

            /// Splits the node into a new group, and
            /// inserts the new node on the given side.
            /// left/right create a horizontal group,
            /// top/bottom create a vertical group.
            /// left/top inserts at the "low" position, 
            /// right/bottom inserts at the "high" position
            split_and_insert: RectangleSide,

            /// Replaces the node selected by path with a new node.
            /// This is only legal for `.empty` nodes that contain no
            /// application.
            replace,
        };
    };

    /// A relative screen rectangle. Base coordinates are [0,0,1,1]
    pub const FloatRectangle = struct {
        x: f32,
        y: f32,
        width: f32,
        height: f32,

        fn contains(self: @This(), x: f32, y: f32) bool {
            return (x >= self.x) and
                (y >= self.y) and
                (x <= self.x + self.width) and
                (y <= self.y + self.height);
        }
    };

    /// Maximum tree nesting depth
    pub const max_depth = 16;
    /// The padding on the side of a rectangle, increases each nesting level by factor 1
    pub const side_padding_per_nest_level = 48;
    /// The padding on the separator between groups, increases each nesting level by factor 1
    pub const separator_padding_per_nest_level = 24;

    allocator: *std.mem.Allocator,
    root: Node,

    pub fn deinit(self: *WindowTree, screen: *Self) void {
        self.destroyNode(&self.root, screen);
        self.* = undefined;
    }

    /// Frees memory for the node.
    pub fn freeNode(self: WindowTree, node: *Node) void {
        if (node == .group) {
            self.allocator.free(node.group.children);
        }
        self.allocator.destroy(node);
    }

    pub fn destroyNode(self: WindowTree, node: *Node, screen: *Self) void {
        switch (node.*) {
            .empty => {},
            .group => |group| {
                for (group.children) |*child| {
                    self.destroyNode(child, screen);
                }
                self.allocator.free(group.children);
            },
            .starting, .connected, .exited => |*app| app.deinit(screen),
        }
        node.* = undefined;
    }

    /// Searches the window tree on a certain coordinate to find a leaf node.
    pub fn findLeaf(self: *WindowTree, x: f32, y: f32) ?*Node {
        std.debug.assert(x >= 0.0 and x <= 1.0);
        std.debug.assert(y >= 0.0 and y <= 1.0);
        return self.findLeafRecursive(
            &self.root,
            FloatRectangle{ .x = 0, .y = 0, .width = 1, .height = 1 },
            x,
            y,
        );
    }

    fn findLeafRecursive(self: *WindowTree, node: *Node, area: FloatRectangle, x: f32, y: f32) ?*Node {
        return switch (node.*) {
            .group => |*group| for (group.children) |*child, index| {
                if (self.findLeafRecursive(child, group.getChildRectangle(area, index), x, y)) |found| {
                    break found;
                }
            } else null,
            else => if (area.contains(x, y))
                node
            else
                null,
        };
    }

    const VisualInsertLocation = struct {
        container: Rectangle,
        splitter: Rectangle,
    };

    /// Returns the rectangle that displays the insert location
    pub fn getInsertLocationRectangle(self: WindowTree, full_area: Rectangle, location: NodeInsertLocation) VisualInsertLocation {
        var node = self.root;
        var rectangle = FloatRectangle{
            .x = @intToFloat(f32, full_area.x),
            .y = @intToFloat(f32, full_area.y),
            .width = @intToFloat(f32, full_area.width),
            .height = @intToFloat(f32, full_area.height),
        };

        for (location.path[0..location.path_len]) |child_index| {
            rectangle = node.group.getChildRectangle(rectangle, child_index);
            node = node.group.children[child_index];
        }

        const side_padding = side_padding_per_nest_level * @intToFloat(f32, location.path_len + 1);
        const separator_padding = separator_padding_per_nest_level * @intToFloat(f32, location.path_len + 1);

        const rel_rect = switch (location.position) {
            .insert_in_group => |index| blk: {
                const size: f32 = switch (node.group.split) {
                    .horizontal => rectangle.width,
                    .vertical => rectangle.height,
                };
                const segment = size / @intToFloat(f32, node.group.children.len);

                const offset = @intToFloat(f32, index) * segment;

                break :blk switch (node.group.split) {
                    .horizontal => FloatRectangle{
                        .x = rectangle.x + offset - 0.5 * separator_padding,
                        .y = rectangle.y,
                        .width = separator_padding,
                        .height = rectangle.height,
                    },
                    .vertical => FloatRectangle{
                        .x = rectangle.x,
                        .y = rectangle.y + offset - 0.5 * separator_padding,
                        .width = rectangle.width,
                        .height = separator_padding,
                    },
                };
            },
            .replace => FloatRectangle{
                .x = rectangle.x + side_padding,
                .y = rectangle.y + side_padding,
                .width = rectangle.width - 2 * side_padding,
                .height = rectangle.height - 2 * side_padding,
            },
            .split_and_insert => |loc| switch (loc) {
                .top => FloatRectangle{ .x = rectangle.x, .y = rectangle.y, .width = rectangle.width, .height = side_padding },
                .bottom => FloatRectangle{ .x = rectangle.x, .y = rectangle.y + rectangle.height - side_padding, .width = rectangle.width, .height = side_padding },
                .left => FloatRectangle{ .x = rectangle.x, .y = rectangle.y, .width = side_padding, .height = rectangle.height },
                .right => FloatRectangle{ .x = rectangle.x + rectangle.width - side_padding, .y = rectangle.y, .width = side_padding, .height = rectangle.height },
            },
        };
        return VisualInsertLocation{
            .container = Rectangle{
                .x = @floatToInt(i16, rectangle.x),
                .y = @floatToInt(i16, rectangle.y),
                .width = @floatToInt(u15, rectangle.width),
                .height = @floatToInt(u15, rectangle.height),
            },
            .splitter = Rectangle{
                .x = @floatToInt(i16, rel_rect.x),
                .y = @floatToInt(i16, rel_rect.y),
                .width = @floatToInt(u15, rel_rect.width),
                .height = @floatToInt(u15, rel_rect.height),
            },
        };
    }

    /// Searches the window tree for a insert location at the given point.
    /// The insert location memory is backed by the `backing_buffer` data.
    pub fn findInsertLocation(self: WindowTree, target: Rectangle, x: i16, y: i16) ?NodeInsertLocation {
        if (x < target.x or y < target.y)
            return null;
        if (x >= target.x + target.width or y >= target.y + target.height)
            return null;
        var backing_buffer = [1]usize{0} ** 16; // insert the root node into the backing buffer
        return self.findInsertLocationRecursive(
            &backing_buffer,
            @intToFloat(f32, x - target.x),
            @intToFloat(f32, y - target.y),
            self.root,
            FloatRectangle{ .x = 0, .y = 0, .width = @intToFloat(f32, target.width), .height = @intToFloat(f32, target.height) },
            0,
        );
    }

    fn findInsertLocationRecursive(
        self: WindowTree,
        backing_buffer: *[max_depth]usize,
        x: f32,
        y: f32,
        node: Node,
        area: FloatRectangle,
        nesting: usize,
    ) ?NodeInsertLocation {
        std.debug.assert(nesting < max_depth);
        std.debug.assert(area.contains(x, y));

        var location: ?NodeInsertLocation = null;

        if (node == .group) {
            for (node.group.children) |chld, index| {
                var child_area = node.group.getChildRectangle(area, index);
                if (child_area.contains(x, y)) {
                    backing_buffer[nesting] = index;
                    location = self.findInsertLocationRecursive(backing_buffer, x, y, chld, child_area, nesting + 1) orelse location;
                }
            }
        }

        // Find insertion on the node itself
        {
            const padding = side_padding_per_nest_level * @intToFloat(f32, nesting + 1);

            if (node == .empty or node == .exited) {
                location = NodeInsertLocation{
                    .path = backing_buffer.*,
                    .path_len = nesting,
                    .position = .replace,
                };
            }

            const insert_side: ?RectangleSide = blk: {
                if (x < area.x + padding)
                    break :blk .left;
                if (x >= area.x + area.width - padding)
                    break :blk .right;
                if (y < area.y + padding)
                    break :blk .top;
                if (y >= area.y + area.height - padding)
                    break :blk .bottom;
                break :blk null;
            };

            if (insert_side) |side| {
                location = NodeInsertLocation{
                    .path = backing_buffer.*,
                    .path_len = nesting,
                    .position = .{
                        .split_and_insert = side,
                    },
                };
            }
        }

        // find split positions
        if (node == .group) {
            const padding = separator_padding_per_nest_level * @intToFloat(f32, nesting + 1);

            const group = node.group;

            const insert_index_opt: ?usize = blk: {
                const size: f32 = switch (group.split) {
                    .horizontal => area.width,
                    .vertical => area.height,
                };
                const pos: f32 = switch (group.split) {
                    .horizontal => x - area.x,
                    .vertical => y - area.y,
                };
                const segment = size / @intToFloat(f32, group.children.len);

                var edge: usize = 0;
                while (edge <= group.children.len) : (edge += 1) {
                    const edge_pos = @intToFloat(f32, edge) * segment;
                    if (std.math.fabs(pos - edge_pos) < padding / 2)
                        break :blk edge;
                }

                break :blk null;
            };

            if (insert_index_opt) |insert_index| {
                // we hovered over a group edge, return the proper path here
                location = NodeInsertLocation{
                    .path = backing_buffer.*,
                    .path_len = nesting,
                    .position = .{
                        .insert_in_group = insert_index,
                    },
                };
            }
        }

        return location;
    }

    /// Inserts a new leaf in the tree at the given location. The node will be copied into the tree and the
    /// original variant might not be used anymore. 
    pub fn insertLeaf(self: *WindowTree, location: NodeInsertLocation, node: Node, screen: *Self) !void {
        var target_node = &self.root;
        for (location.path[0..location.path_len]) |child_index| {
            target_node = &target_node.group.children[child_index];
        }
        switch (location.position) {
            .insert_in_group => |index| {
                std.debug.assert(target_node.* == .group);
                const group = &target_node.group;

                const old_items = group.children;

                const new_items = try self.allocator.alloc(Node, old_items.len + 1);
                errdefer self.allocator.free(new_items);

                if (index > 0) {
                    std.mem.copy(Node, new_items[0..index], old_items[0..index]);
                }
                if (index < old_items.len) {
                    std.mem.copy(Node, new_items[index + 1 ..], old_items[index..]);
                }
                new_items[index] = node;

                group.children = new_items;
                self.allocator.free(old_items);
            },
            .split_and_insert => |side| {
                var splitter = Node{
                    .group = .{
                        .split = switch (side) {
                            .top, .bottom => Layout.vertical,
                            .left, .right => Layout.horizontal,
                        },
                        .children = try self.allocator.alloc(Node, 2),
                    },
                };
                errdefer self.allocator.free(splitter.group.children);

                const new_node_index: usize = switch (side) {
                    .top, .left => 0,
                    .bottom, .right => 1,
                };
                const old_node_index = 1 - new_node_index;

                splitter.group.children[new_node_index] = node;
                splitter.group.children[old_node_index] = target_node.*;

                target_node.* = splitter;
            },
            .replace => {
                std.debug.assert(target_node.* == .empty or target_node.* == .exited);
                self.destroyNode(target_node, screen);
                target_node.* = node;
            },
        }
    }

    pub fn leafIterator(self: *WindowTree) LeafIterator {
        var iter = LeafIterator{
            .stack = undefined,
            .stack_depth = 1,
        };
        iter.stack[0] = .{ .node = &self.root };
        return iter;
    }

    pub const LeafIterator = struct {
        stack: [max_depth]StackItem,
        stack_depth: usize,

        const StackItem = struct {
            node: *Node,
            index: usize = 0,
        };

        pub fn next(self: *@This()) ?*Node {
            while (true) {
                if (self.stack_depth == 0)
                    return null;
                const top = &self.stack[self.stack_depth - 1];
                if (top.node.* != .group) {
                    defer self.stack_depth -= 1; // pop the item
                    return top.node;
                } else {
                    if (top.index >= top.node.group.children.len) {
                        self.stack_depth -= 1; // pop the group from the stack, continue with the next stack item
                    } else {
                        self.stack[self.stack_depth] = StackItem{
                            .node = &top.node.group.children[top.index],
                        };
                        self.stack_depth += 1;
                        top.index += 1;
                    }
                }
            }
        }
    };
};

// https://en.wikipedia.org/wiki/Smoothstep
fn smoothstep(x: f32, edge0: f32, edge1: f32) f32 {
    // Scale, bias and saturate x to 0..1 range
    const f = std.math.clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0);
    // Evaluate polynomial
    return f * f * (3 - 2 * f);
}

fn lerpColor(a: Color, b: Color, x: f32) Color {
    return if (x >= 1.0)
        b
    else if (x <= 0.0)
        a
    else
        Color{
            .r = @floatToInt(u8, lerp(@intToFloat(f32, a.r), @intToFloat(f32, b.r), x)),
            .g = @floatToInt(u8, lerp(@intToFloat(f32, a.g), @intToFloat(f32, b.g), x)),
            .b = @floatToInt(u8, lerp(@intToFloat(f32, a.b), @intToFloat(f32, b.b), x)),
            .a = @floatToInt(u8, lerp(@intToFloat(f32, a.a), @intToFloat(f32, b.a), x)),
        };
}

fn lerp(a: f32, b: f32, x: f32) f32 {
    return a + (b - a) * x;
}
