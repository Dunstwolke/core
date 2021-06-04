const std = @import("std");
const painterz = @import("painterz");
const tvg = @import("tvg");

const zerog = @import("zero-graphics");

const icons = @import("icons/data.zig");

const logger = std.log.scoped(.home_screen);

const Self = @This();

const UserInterface = zerog.UserInterface;
const Renderer2D = zerog.Renderer2D;
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

const HomeScreenConfig = struct {
    const WorkspaceBarConfig = struct {
        background: Color,
        border: Color,
        button_theme: ButtonTheme,
        button_size: u15,
        margins: u15,
        location: RectangleSide,

        fn getWidth(self: @This()) u15 {
            return 2 * self.margins + self.button_size;
        }
    };

    const AppMenuConfig = struct {
        button_theme: ButtonTheme,

        dimmer: Color,
        outline: Color,
        background: Color,
        button_size: u15,
        scrollbar_width: u15,
        margins: u15,
    };

    const WorkspaceConfig = struct {
        app_icon_size: u15,
        active_app_border: Color,
        background_color: Color,
        insert_highlight_color: Color,
        insert_highlight_fill_color: Color,
    };

    app_menu: AppMenuConfig = AppMenuConfig{
        .dimmer = rgba("292f35", 0.5),
        .outline = rgb("1abc9c"),
        .background = rgb("255953"),
        .scrollbar_width = 8,
        .margins = 8,

        .button_size = 100,
        .button_theme = ButtonTheme{
            .text_color = rgb("ffffff"),
            .icon_size = 64,
            .default = .{
                .outline = rgb("1abc9c"),
                .background = rgb("255953"),
            },
            .hovered = .{
                .outline = rgb("1abc9c"),
                .background = rgb("0e443f"),
            },
            .clicked = .{
                .outline = rgb("1abc9c"),
                .background = rgb("0e443f"),
            },
            .disabled = .{
                .outline = rgb("a6a6a6"),
                .background = rgb("505050"),
            },
        },
    },

    workspace_bar: WorkspaceBarConfig = WorkspaceBarConfig{
        .location = .bottom,
        .background = rgb("292f35"),
        .border = rgb("212529"),
        .button_size = 50,
        .margins = 8,
        .button_theme = ButtonTheme{
            .icon_size = 48,
            .text_color = rgb("ffffff"),
            .default = .{
                .outline = rgb("363c42"),
                .background = rgb("292f35"),
            },
            .hovered = .{
                .outline = rgb("1abc9c"),
                .background = rgb("255953"),
            },
            .clicked = .{
                .outline = rgb("1abc9c"),
                .background = rgb("0e443f"),
            },
            .disabled = .{
                .outline = rgb("a6a6a6"),
                .background = rgb("505050"),
            },
        },
    },

    workspace: WorkspaceConfig = WorkspaceConfig{
        .app_icon_size = 96,
        .background_color = rgb("263238"),
        .active_app_border = rgb("255853"),
        .insert_highlight_color = rgb("FF00FF"),
        .insert_highlight_fill_color = rgba("FF00FF", 0.3),
    },
};

const ui_workspace_bar_button_theme = UserInterface.ButtonTheme{
    .icon_size = 48,
    .default = .{
        .border = rgb("363c42"),
        .background = rgb("292f35"),
        .text_color = Color.white,
    },
    .hovered = .{
        .border = rgb("1abc9c"),
        .background = rgb("0e443f"),
        .text_color = Color.white,
    },
    .clicked = .{
        .border = rgb("1abc9c"),
        .background = rgb("003934"),
        .text_color = Color.white,
    },
    .disabled = .{
        .border = rgb("363c42"),
        .background = rgb("292f35"),
        .text_color = rgb("cccccc"),
    },
};

const ui_contextmenu_panel_theme = UserInterface.BoxStyle{
    .border = rgb("212529"),
    .background = rgb("255953"),
};

const ui_window_panel_theme = UserInterface.BoxStyle{
    .border = rgb("212529"),
    .background = rgb("263238"),
};

const ui_active_window_panel_theme = UserInterface.BoxStyle{
    .border = rgb("1abc9c"),
    .background = rgb("263238"),
};

const ui_workspace_bar_current_button_theme = UserInterface.ButtonTheme{
    .icon_size = 48,
    .default = .{
        .border = rgb("1abc9c"),
        .background = rgb("0e443f"),
        .text_color = Color.white,
    },
    .hovered = .{
        .border = rgb("1abc9c"),
        .background = rgb("0e443f"),
        .text_color = Color.white,
    },
    .clicked = .{
        .border = rgb("1abc9c"),
        .background = rgb("003934"),
        .text_color = Color.white,
    },
    .disabled = .{
        .border = rgb("363c42"),
        .background = rgb("292f35"),
        .text_color = rgb("cccccc"),
    },
};

const ui_appmenu_button_theme = UserInterface.ButtonTheme{
    .icon_size = 64,
    .default = .{
        .border = rgb("1abc9c"),
        .background = rgb("255953"),
        .text_color = Color.white,
    },
    .hovered = .{
        .border = rgb("1abc9c"),
        .background = rgb("0e443f"),
        .text_color = Color.white,
    },
    .clicked = .{
        .border = rgb("1abc9c"),
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
            .border = rgb("1abc9c"),
            .background = rgb("255953"),
            .text_color = Color.white,
        },
        .hovered = .{
            .border = rgb("1abc9c"),
            .background = rgb("0e443f"),
            .text_color = Color.white,
        },
        .clicked = .{
            .border = rgb("1abc9c"),
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
        .background = rgb("292f35"),
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
        try writer.writeAll("\"");
        try writer.writeAll(std.meta.tagName(value));
        try writer.writeAll("\"");
    }
};

/// A startable application available in the app menu.
const AppReference = struct {
    application: *ApplicationDescription,

    button_state: ButtonState = .{},
};

const IconCache = struct {
    const SizedIcons = std.AutoHashMapUnmanaged(u30, *const Renderer2D.Texture);
    const Map = std.StringHashMapUnmanaged(SizedIcons);

    allocator: *std.mem.Allocator,
    renderer: *Renderer2D,
    icon_map: Map,

    pub fn get(self: *IconCache, icon: []const u8, size: Size) !*const Renderer2D.Texture {
        const gop1 = try self.icon_map.getOrPut(self.allocator, icon);
        if (!gop1.found_existing) {
            gop1.entry.value = SizedIcons{};
        }

        const size_key = (@as(u30, size.width) << 15) | size.width;

        const gop2 = try gop1.entry.value.getOrPut(self.allocator, size_key);
        if (!gop2.found_existing) {
            var arena = std.heap.ArenaAllocator.init(self.allocator);
            defer arena.deinit();

            const swidth = @as(usize, size.width);
            const sheight = @as(usize, size.height);

            const pixels = try arena.allocator.alloc(Color, swidth * sheight);
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

            gop2.entry.value = self.renderer.createTexture(size.width, size.height, std.mem.sliceAsBytes(pixels)) catch return error.OutOfMemory;
        }
        return gop2.entry.value;
    }

    pub fn deinit(self: *IconCache) void {
        var outer_it = self.icon_map.iterator();
        while (outer_it.next()) |list| {
            var inner_it = list.value.iterator();
            while (inner_it.next()) |item| {
                self.renderer.destroyTexture(item.value);
            }
        }
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
config: HomeScreenConfig,
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

renderer: *Renderer2D,

ui: UserInterface,
input_processor: ?UserInterface.InputProcessor = null,

app_title_font: *const Renderer2D.Font,
app_status_font: *const Renderer2D.Font,
app_button_font: *const Renderer2D.Font,

icon_cache: IconCache,

pub fn init(allocator: *std.mem.Allocator, renderer: *Renderer2D) !Self {
    var self = Self{
        .allocator = allocator,
        .size = Size{ .width = 0, .height = 0 },
        .menu_items = std.ArrayList(MenuItem).init(allocator),
        .config = HomeScreenConfig{},
        .mouse_pos = Point{ .x = 0, .y = 0 },
        .current_workspace = 2, // first workspace after app_menu, separator
        .mode = .default,
        .available_apps = std.ArrayList(AppReference).init(allocator),
        .app_title_font = undefined,
        .app_status_font = undefined,
        .app_button_font = undefined,
        .renderer = renderer,
        .ui = undefined,
        .icon_cache = IconCache{
            .allocator = allocator,
            .renderer = renderer,
            .icon_map = .{},
        },
    };

    const ttf_font_data = @embedFile("fonts/firasans-regular.ttf");

    self.app_title_font = try self.renderer.createFont(ttf_font_data, 30);
    errdefer self.renderer.destroyFont(self.app_title_font);

    self.app_status_font = try self.renderer.createFont(ttf_font_data, 20);
    errdefer self.renderer.destroyFont(self.app_status_font);

    self.app_button_font = try self.renderer.createFont(ttf_font_data, 12);
    errdefer self.renderer.destroyFont(self.app_button_font);

    self.ui = try UserInterface.init(self.allocator, self.renderer);
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
            .button => |*b| b.deinit(),
            else => {},
        }
    }
    self.icon_cache.deinit();
    self.menu_items.deinit();
    self.available_apps.deinit();
    self.ui.deinit();
    self.renderer.destroyFont(self.app_status_font);
    self.renderer.destroyFont(self.app_title_font);
    self.renderer.destroyFont(self.app_button_font);
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
            app.* = AppReference{
                .application = apps[i],
            };
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
    std.debug.assert(self.input_processor != null);

    if (mouse_button != .primary) {
        self.config.workspace_bar.location = switch (self.config.workspace_bar.location) {
            .top => RectangleSide.right,
            .right => RectangleSide.bottom,
            .bottom => RectangleSide.left,
            .left => RectangleSide.top,
        };

        return;
    }

    self.input_processor.?.pointerDown();

    self.mouse_down_timestamp = std.time.nanoTimestamp();
    self.mouse_down_pos = self.mouse_pos;

    switch (self.mode) {
        .default => {
            // Check if the user pressed the mouse on a button
            for (self.menu_items.items) |btn, i| {
                const rect = self.getMenuButtonRectangle(i);
                if (rect.contains(self.mouse_pos)) {
                    if (btn == .button and btn.button.state.enabled) {
                        self.mode = .{ .button_press = i };
                    }
                    return;
                }
            }
        },
        .button_press => unreachable,
        .app_menu => {
            const app_menu = self.getAppMenuRectangle();

            if (app_menu.contains(self.mouse_pos)) {

                // Check if the user pressed the mouse on a button
                for (self.available_apps.items) |app, i| {
                    const rect = self.getAppButtonRectangle(i);
                    if (rect.contains(self.mouse_pos)) {
                        if (app.application.state == .ready) {
                            self.mode = .{ .app_press = .{
                                .index = i,
                                .position = self.mouse_pos,
                            } };
                        }
                        return;
                    }
                }
            } else {
                self.mode = .default;
            }
        },
        .app_press, .app_drag_menu, .app_drag_desktop => unreachable,
    }
}

pub fn mouseUp(self: *Self, mouse_button: zerog.Input.MouseButton) !void {
    std.debug.assert(self.input_processor != null);

    if (mouse_button != .primary)
        return;

    self.input_processor.?.pointerUp();

    const long_click = if (self.mouse_down_timestamp) |ts|
        (std.time.nanoTimestamp() - ts) > long_click_period
    else
        false;
    self.mouse_down_timestamp = null;
    self.mouse_down_pos = null;

    switch (self.mode) {
        .default => {
            // do nothing on a mouse-up, we process clicks via .button_press
        },
        .button_press => |button_index| {
            self.mode = .default;

            const rect = self.getMenuButtonRectangle(button_index);

            if (rect.contains(self.mouse_pos)) {
                const menu_item = &self.menu_items.items[button_index];
                switch (menu_item.*) {
                    .button => |*button| {
                        switch (button.data) {
                            .app_menu => {
                                self.openAppMenu();
                                return;
                            },

                            .workspace => {
                                self.current_workspace = button_index;
                                return;
                            },

                            //else => logger.info("clicked on button {}: {}", .{ button_index, button.data }),
                        }
                    },

                    else => logger.info("clicked on something else {}: {}", .{ button_index, std.meta.activeTag(menu_item.*) }),
                }
            }
        },
        .app_menu => {},
        .app_press => |info| {
            self.mode = .app_menu;

            const rect = self.getAppButtonRectangle(info.index);
            if (rect.contains(self.mouse_pos)) {
                const app = &self.available_apps.items[info.index];

                if (long_click) {
                    logger.info("long-clicked on the app[{d}] '{s}'", .{ info.index, app.application.display_name });
                } else {
                    logger.info("clicked on the app[{d}] '{s}'", .{ info.index, app.application.display_name });
                }
            }
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

                    try workspace.window_tree.insertLeaf(target_location, node);
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

const ContextMenuResult = union(enum) {
    none,
    clicked: usize,
    closed,
};

fn doContextMenu(self: Self, builder: UserInterface.Builder, title: []const u8, menu_items: []const MouseMode.ContextMenuItem) !ContextMenuResult {
    const menu_rectangle = Rectangle{
        .x = (self.size.width - 210) / 2,
        .y = (self.size.height - 240) / 2,
        .width = 210,
        .height = @intCast(u15, 40 * (menu_items.len + 1)) + 1,
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
        for (self.menu_items.items) |*menu_item, index| {
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
                    .starting => |*app| {
                        try app.application.update(dt);
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
                        try app.application.update(dt);
                        if (app.application.status == .exited) {
                            // workaround for re-tagging with RLS
                            var app_copy = app.*;
                            leaf.* = .{ .exited = app_copy };
                        }
                    },
                    .exited => {
                        // the exited application isn't updated anymore
                        // as there is nothing to do here
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
                                // if (btn.data.workspace.window_tree.findInsertLocation(workspace_area, self.mouse_pos.x, self.mouse_pos.y)) |path| {
                                //     const insert_location = btn.data.workspace.window_tree.getInsertLocationRectangle(workspace_area, path);

                                //     try renderer.drawRectangle(insert_location.container, self.config.workspace.insert_highlight_color);
                                //     try renderer.fillRectangle(insert_location.splitter, self.config.workspace.insert_highlight_fill_color);
                                // }
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

        for (self.menu_items.items) |item, idx| {
            const button_rect = self.getMenuButtonRectangle(idx);

            if (item == .button) {
                const button = &item.button;

                const icon = switch (button.data) {
                    .app_menu => @as([]const u8, &icons.app_menu),
                    .workspace => &icons.workspace,
                };

                const texture = try self.icon_cache.get(icon, Size{ .width = 48, .height = 48 });

                const style = if (button.data == .workspace and idx == self.current_workspace)
                    ui_workspace_bar_current_button_theme
                else
                    ui_workspace_bar_button_theme;

                if (try builder.button(button_rect, null, texture, .{ .style = style })) {
                    logger.info("ui button was clicked!", .{});
                }
            }
        }

        if (dragged_app_index) |_| {
            const button_rect = self.getMenuButtonRectangle(self.menu_items.items.len);
            const texture = try self.icon_cache.get(&icons.workspace_add, Size{ .width = 48, .height = 48 });
            _ = try builder.button(button_rect, null, texture, .{ .style = ui_workspace_bar_button_theme });
        }
    }

    // Update app menu
    if (self.mode.isAppMenuVisible()) {
        _ = try builder.modalLayer(.{});

        try builder.panel(self.getAppMenuRectangle(), .{});

        for (self.available_apps.items) |app, idx| {
            const button_rect = self.getAppButtonRectangle(idx);

            if (try self.appButton(builder, button_rect, app.application)) {
                logger.info("app button was clicked!", .{});
            }
        }
    }

    if (dragged_app_index) |index| {
        const app = self.available_apps.items[index];
        const button_size = self.config.app_menu.button_size;

        const button_rect = Rectangle{
            .x = self.mouse_pos.x - button_size / 2,
            .y = self.mouse_pos.y - button_size / 2,
            .width = button_size,
            .height = button_size,
        };

        _ = try self.appButton(builder, button_rect, app.application);
    }

    // Update context menu
    const ContextMenu = struct {
        var open: bool = false;
    };

    if (try builder.button(Rectangle{ .x = 100, .y = 100, .width = 80, .height = 32 }, "Context Menu", null, .{}))
        ContextMenu.open = true;

    if (ContextMenu.open) {
        const items = [_]MouseMode.ContextMenuItem{
            .{ .title = "Move to workspace", .enabled = false },
            .{ .title = "Move to own workspace" },
            .{ .title = "Close application" },
        };

        const result = try self.doContextMenu(builder, "Dummy Application", &items);
        switch (result) {
            .none => {},
            .clicked => |index| {
                logger.info("clicked on menu item {}: {s}", .{ index, items[index].title });
            },
            .closed => ContextMenu.open = false,
        }
    }

    // Check if we started dragging a app.
    // This must be done before checking the (app_drag_menu -> app_drag_desktop) transition as this might happen in the same frame!
    if (self.mode == .app_press) {
        const info = self.mode.app_press;
        if (self.isDragDistanceReached(info.position)) {
            self.mode = .{ .app_drag_menu = info.index };
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

        for (self.menu_items.items) |*item, idx| {
            switch (item.*) {
                .button => |*button| {
                    button.state.clicked = (self.mode == .button_press and self.mode.button_press == idx) or
                        (self.current_workspace == idx);
                    button.state.hovered = (if (hovered_button) |i| (i == idx) else false) or
                        ((button.data == .app_menu) and (self.mode == .app_menu)) or
                        (self.current_workspace == idx);
                    button.state.update(dt);
                },
                else => {},
            }
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

        for (self.available_apps.items) |*app, app_index| {
            app.button_state.clicked = (self.mode == .app_press and self.mode.app_press.index == app_index);
            app.button_state.hovered = (if (hovered_app) |i| (i == app_index) else false);
            app.button_state.enabled = (app.application.state == .ready);
            app.button_state.update(dt);
        }
    }
}

fn updateWorkspace(self: *Self, builder: UserInterface.Builder, area: Rectangle, workspace: *Workspace, hovered_rectangle: *?Rectangle) RenderError!void {
    try self.updateTreeNode(builder, area, &workspace.window_tree.root, hovered_rectangle);
}

fn renderStartingAppNode(custom: UserInterface.CustomWidget, area: Rectangle, renderer: *Renderer2D, info: UserInterface.CustomWidget.DrawInfo) Renderer2D.DrawError!void {
    const self = @ptrCast(*Self, @alignCast(@alignOf(Self), custom.config.context orelse unreachable));
    const application = @ptrCast(*ApplicationInstance, @alignCast(@alignOf(ApplicationInstance), custom.user_data orelse unreachable));

    const icon_size = std.math.min(area.width - 2, self.config.workspace.app_icon_size);
    if (icon_size > 0) {
        try self.drawIcon(
            Rectangle{
                .x = area.x + (area.width - icon_size) / 2,
                .y = area.y + (area.height - icon_size) / 2,
                .width = icon_size,
                .height = icon_size,
            },
            application.description.icon orelse icons.app_placeholder,
            Color.white,
        );
    }

    const display_name = application.description.display_name;
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

    const startup_message = application.status.starting; // this is safe as the status might only be changed in the update fn
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

fn renderRunningAppNode(custom: UserInterface.CustomWidget, area: Rectangle, renderer: *Renderer2D, info: UserInterface.CustomWidget.DrawInfo) Renderer2D.DrawError!void {
    const self = @ptrCast(*Self, @alignCast(@alignOf(Self), custom.config.context orelse unreachable));
    const application = @ptrCast(*ApplicationInstance, @alignCast(@alignOf(ApplicationInstance), custom.user_data orelse unreachable));

    application.render(area, self.renderer) catch |err| logger.err("failed to render application '{s}': {s}", .{
        application.description.display_name,
        @errorName(err),
    });
}

fn renderExitedAppNode(custom: UserInterface.CustomWidget, area: Rectangle, renderer: *Renderer2D, info: UserInterface.CustomWidget.DrawInfo) Renderer2D.DrawError!void {
    const self = @ptrCast(*Self, @alignCast(@alignOf(Self), custom.config.context orelse unreachable));
    const application = @ptrCast(*ApplicationInstance, @alignCast(@alignOf(ApplicationInstance), custom.user_data orelse unreachable));

    const exit_message = application.status.exited; // this is safe as the status might only be changed in the update fn
    if (exit_message.len > 0) {
        const size = self.renderer.measureString(self.app_status_font, exit_message);
        try self.renderer.drawString(
            self.app_status_font,
            exit_message,
            area.x + (area.width - size.width) / 2,
            area.y + area.height / 2,
            .{ .r = 0xFF, .g = 0x00, .b = 0x00 }, // TODO: Replace by theme config
        );
    }
}

fn updateTreeNode(self: *Self, builder: UserInterface.Builder, area: Rectangle, node: *WindowTree.Node, hovered_rectangle: *?Rectangle) RenderError!void {
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
        .starting => |app| {
            _ = try builder.custom(area.shrink(1), app.application, .{
                .id = node,
                .draw = renderStartingAppNode,
                .context = self,
            });
        },
        .connected => |app| {
            _ = try builder.custom(area.shrink(1), app.application, .{
                .id = node,
                .draw = renderRunningAppNode,
                .context = self,
            });

            try app.application.processUserInterface(area, builder);
        },
        .exited => |app| {
            _ = try builder.custom(area.shrink(1), app.application, .{
                .id = node,
                .draw = renderExitedAppNode,
                .context = self,
            });
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

const SubCanvas = struct {
    canvas: *Canvas,

    alpha: f32 = 1.0,
    x: isize,
    y: isize,
    width: usize,
    height: usize,

    pub fn setPixel(section: @This(), x: isize, y: isize, color: [4]u8) void {
        if (x < 0 or y < 0)
            return;
        if (x >= section.width or y >= section.height)
            return;
        section.canvas.setPixel(section.x + x, section.y + y, Color{
            .r = color[0],
            .g = color[1],
            .b = color[2],
            .a = @floatToInt(u8, section.alpha * @intToFloat(f32, color[3])),
        });
    }
};

const RenderError = error{OutOfMemory} || zerog.Renderer2D.DrawError;
pub fn render(self: *Self) RenderError!void {
    const bar_width = self.config.workspace_bar.getWidth();

    const workspace_area = self.getWorkspaceRectangle();

    const bar_area = self.getBarRectangle();

    const renderer = self.renderer;

    try self.ui.render();

    // Long-click activity rendering
    if (self.mouse_down_timestamp) |ts| {
        if (self.mouse_down_pos) |mdp| {
            if (!self.isDragDistanceReached(mdp)) {
                const delta = std.math.clamp(std.time.nanoTimestamp() - ts, 0, long_click_period);
                if (delta >= long_click_indicator_period) {
                    const Helper = struct {
                        const radius = 24;
                        center: Point,

                        fn getFromAngle(help: @This(), a: f32) Point {
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

                    var last = helper.getFromAngle(0);

                    var i: usize = 1;
                    while (i <= segment_count) : (i += 1) {
                        const current = helper.getFromAngle(delta_f * 2.0 * std.math.pi * @intToFloat(f32, i) / @intToFloat(f32, segment_count));

                        try renderer.drawLine(
                            last.x,
                            last.y,
                            current.x,
                            current.y,
                            Color.red,
                        );

                        last = current;
                    }
                }
            }
        }
    }
}

fn drawIcon(self: *Self, target: Rectangle, icon: []const u8, tint: Color) !void {
    const texture = try self.icon_cache.get(icon, target.size());

    try self.renderer.fillTexturedRectangle(
        target,
        texture,
        tint,
    );
}

fn initColor(r: u8, g: u8, b: u8, a: u8) Color {
    return Color{ .r = r, .g = g, .b = b, .a = a };
}

const ButtonState = struct {
    pub const normal = ButtonState{};
    pub const pressed = ButtonState{ .visual_pressed = 1.0, .clicked = true };
    pub const hovered = ButtonState{ .visual_highlight = 1.0, .hovered = true };

    hovered: bool = false,
    clicked: bool = false,
    enabled: bool = true,

    visual_highlight: f32 = 0.0,
    visual_pressed: f32 = 0.0,

    fn update(self: *ButtonState, dt: f32) void {
        const hover_delta = if (self.hovered)
            @as(f32, 5.0) // fade-in time, normal
        else
            @as(f32, -5.0); // fade-out time

        const click_delta = if (self.clicked and self.hovered)
            @as(f32, 15.0) // fade-in time
        else
            @as(f32, -3.0); // fade-out time

        self.visual_highlight = std.math.clamp(self.visual_highlight + dt * hover_delta, 0.0, 1.0);
        self.visual_pressed = std.math.clamp(self.visual_pressed + dt * click_delta, 0.0, 1.0);
    }
};

fn alphaBlend(c: u8, f: f32) u8 {
    return @floatToInt(u8, f * @intToFloat(f32, c));
}

fn appButton(
    self: *Self,
    builder: UserInterface.Builder,
    rectangle: Rectangle,
    app: *ApplicationDescription,
) !bool {
    const result = try builder.custom(rectangle, app, .{
        .id = app,
        .draw = renderApplicationButtonWidget,
        .context = self,
    });
    return (result != null);
}

fn renderApplicationButtonWidget(
    custom: UserInterface.CustomWidget,
    rectangle: Rectangle,
    renderer: *Renderer2D,
    info: UserInterface.CustomWidget.DrawInfo,
) Renderer2D.DrawError!void {
    const self = @ptrCast(*Self, @alignCast(@alignOf(Self), custom.config.context orelse unreachable));
    const application = @ptrCast(*ApplicationInstance, @alignCast(@alignOf(ApplicationInstance), custom.user_data orelse unreachable));

    const style = if (info.is_pressed)
        self.config.app_menu.button_theme.clicked
    else if (info.is_hovered)
        self.config.app_menu.button_theme.hovered
    else
        self.config.app_menu.button_theme.default;

    const back_color = style.background;
    const outline_color = style.outline;

    const alpha = 1.0;

    const icon = application.description.icon orelse icons.app_placeholder;
    const label = application.description.display_name;

    try self.renderer.fillRectangle(rectangle, back_color);
    try self.renderer.drawRectangle(rectangle, outline_color);

    const icon_size = std.math.min(rectangle.width - 2, self.config.app_menu.button_theme.icon_size);

    if (icon_size > 0) {
        try self.drawIcon(
            rectangle.centered(icon_size, icon_size),
            icon,
            Color{ .r = 0xFF, .g = 0xFF, .b = 0xFF, .a = @floatToInt(u8, 255.0 * alpha) },
        );
    }
    {
        const top = ((rectangle.height + icon_size) / 2 + rectangle.height) / 2;

        const size = self.renderer.measureString(self.app_button_font, label);

        try self.renderer.drawString(
            self.app_button_font,
            label,
            rectangle.x + (rectangle.width - size.width) / 2,
            rectangle.y + @intCast(u15, top - self.app_button_font.font_size / 2),
            .{ .r = 0xFF, .g = 0xFF, .b = 0xFF }, // TODO: Introduce proper config here
        );
    }
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
    state: ButtonState = .{},

    fn deinit(self: *Button) void {
        switch (self.data) {
            .workspace => |*ws| ws.deinit(),
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

    fn deinit(self: *Workspace) void {
        self.window_tree.deinit();
        self.* = undefined;
    }
};

/// A abstract application on the desktop.
/// This might be backed by any application/window provider.
const AppInstance = struct {
    application: *ApplicationInstance,

    // TODO: Add other runtime data here

    pub fn deinit(self: *AppInstance) void {
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

    pub fn deinit(self: *WindowTree) void {
        self.destroyNode(&self.root);
        self.* = undefined;
    }

    /// Frees memory for the node.
    pub fn freeNode(self: WindowTree, node: *Node) void {
        if (node == .group) {
            self.allocator.free(node.group.children);
        }
        self.allocator.destroy(node);
    }

    pub fn destroyNode(self: WindowTree, node: *Node) void {
        switch (node.*) {
            .empty => {},
            .group => |group| {
                for (group.children) |*child| {
                    self.destroyNode(child);
                }
                self.allocator.free(group.children);
            },
            .starting, .connected, .exited => |*app| app.deinit(),
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
    pub fn insertLeaf(self: *WindowTree, location: NodeInsertLocation, node: Node) !void {
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
                self.destroyNode(target_node);
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
