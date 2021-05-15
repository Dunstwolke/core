const std = @import("std");
const painterz = @import("painterz");
const tvg = @import("tvg");

const icons = @import("icons/data.zig");

const log = std.log.scoped(.home_screen);

const Self = @This();

const Point = @import("Point.zig");
const Size = @import("Size.zig");
const Rectangle = @import("Rectangle.zig");
const Framebuffer = @import("Framebuffer.zig");
const Color = Framebuffer.Color;
const Display = @import("Display.zig");
const TextRenderer = @import("TextRenderer.zig");

const ApplicationInstance = @import("ApplicationInstance.zig");
const ApplicationDescription = @import("ApplicationDescription.zig");

const Canvas = painterz.Canvas(Framebuffer, Framebuffer.Color, setFramebufferPixel);

const ButtonTheme = struct {
    const Style = struct {
        outline: Color,
        background: Color,
    };

    default: Style,
    hovered: Style,
    clicked: Style,

    text_color: Color,
    icon_size: u15,
};

const HomeScreenConfig = struct {
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
                .background = rgb("255953"),
            },
        },
    },

    workspace_bar: WorkspaceBarConfig = WorkspaceBarConfig{
        .location = .left,
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

app_title_font: TextRenderer,
app_status_font: TextRenderer,
app_button_font: TextRenderer,

pub fn init(allocator: *std.mem.Allocator, initial_size: Size) !Self {
    var self = Self{
        .allocator = allocator,
        .size = initial_size,
        .menu_items = std.ArrayList(MenuItem).init(allocator),
        .config = HomeScreenConfig{},
        .mouse_pos = Point{ .x = 0, .y = 0 },
        .current_workspace = 2, // first workspace after app_menu, separator
        .mode = .default,
        .available_apps = std.ArrayList(AppReference).init(allocator),
        .app_title_font = undefined,
        .app_status_font = undefined,
        .app_button_font = undefined,
    };

    const ttf_font_data = @embedFile("fonts/firasans-regular.ttf");

    self.app_title_font = try TextRenderer.init(self.allocator, ttf_font_data, 30);
    errdefer self.app_title_font.deinit();

    self.app_status_font = try TextRenderer.init(self.allocator, ttf_font_data, 20);
    errdefer self.app_status_font.deinit();

    self.app_button_font = try TextRenderer.init(self.allocator, ttf_font_data, 12);
    errdefer self.app_button_font.deinit();

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
    self.menu_items.deinit();
    self.available_apps.deinit();
    self.app_status_font.deinit();
    self.app_title_font.deinit();
    self.app_button_font.deinit();
    self.* = undefined;
}

pub fn setAvailableApps(self: *Self, apps: []const *ApplicationDescription) !void {
    try self.available_apps.resize(apps.len);

    for (self.available_apps.items) |*app, i| {
        app.* = AppReference{
            .application = apps[i],
        };
    }
}

fn openAppMenu(self: *Self) void {
    self.mode = .app_menu;
    log.debug("open app menu", .{});
}

pub fn resize(self: *Self, size: Size) !void {
    self.size = size;
}

pub fn setMousePos(self: *Self, pos: Point) void {
    self.mouse_pos = pos;
}

var rng = std.rand.DefaultPrng.init(0);

pub fn mouseDown(self: *Self, mouse_button: Display.MouseButton) !void {
    if (mouse_button != .left) {
        self.config.workspace_bar.location = switch (self.config.workspace_bar.location) {
            .top => RectangleSide.right,
            .right => RectangleSide.bottom,
            .bottom => RectangleSide.left,
            .left => RectangleSide.top,
        };

        return;
    }

    switch (self.mode) {
        .default => {
            // Check if the user pressed the mouse on a button
            for (self.menu_items.items) |btn, i| {
                const rect = self.getMenuButtonRectangle(i);
                if (rect.contains(self.mouse_pos)) {
                    self.mode = .{ .button_press = i };
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
                        self.mode = .{ .app_press = .{
                            .index = i,
                            .position = self.mouse_pos,
                        } };
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

pub fn mouseUp(self: *Self, mouse_button: Display.MouseButton) !void {
    if (mouse_button != .left)
        return;

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

                            //else => log.info("clicked on button {}: {}", .{ button_index, button.data }),
                        }
                    },

                    else => log.info("clicked on something else {}: {}", .{ button_index, std.meta.activeTag(menu_item.*) }),
                }
            }
        },
        .app_menu => {},
        .app_press => |info| {
            self.mode = .app_menu;

            const rect = self.getAppButtonRectangle(info.index);
            if (rect.contains(self.mouse_pos)) {
                const app = &self.available_apps.items[info.index];
                log.info("clicked on the app[{d}] '{s}'", .{ info.index, app.application.display_name });
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
                log.info("spawning on the app[{d}] '{s}'", .{ app_index, app.application.display_name });

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
                log.info("cancel spawn of app[{d}] '{s}'", .{ app_index, app.application.display_name });
            }
        },
    }
}

pub fn update(self: *Self, dt: f32) !void {

    // Check if we started dragging a app.
    // This must be done before checking the (app_drag_menu -> app_drag_desktop) transition as this might happen in the same frame!
    if (self.mode == .app_press) {
        const info = self.mode.app_press;
        const dx = std.math.absCast(self.mouse_pos.x - info.position.x);
        const dy = std.math.absCast(self.mouse_pos.y - info.position.y);
        if (dx >= 16 or dy >= 16) {
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
                            log.info("Select workspace {d}", .{idx});
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
            app.button_state.update(dt);
        }
    }

    // Update all running applications
    {
        for (self.menu_items.items) |*menu_item, index| {
            if (menu_item.* != .button)
                continue;
            if (menu_item.button.data != .workspace)
                continue;
            // log.info("leafes on workspace {d}", .{index});

            const workspace: *Workspace = &menu_item.button.data.workspace;

            var leaf_iterator = workspace.window_tree.leafIterator();

            while (leaf_iterator.next()) |leaf| {
                // log.info("  available node: {}", .{leaf});
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

pub fn render(self: *Self, target: Framebuffer) void {
    var temp_buffer: [4096]u8 = undefined;
    var temp_allocator = std.heap.FixedBufferAllocator.init(&temp_buffer);

    var fb = Canvas.init(target);

    const bar_width = self.config.workspace_bar.getWidth();

    const workspace_area = self.getWorkspaceRectangle();

    const bar_area = self.getBarRectangle();

    fb.fillRectangle(workspace_area.x, workspace_area.y, workspace_area.width, workspace_area.height, self.config.workspace.background_color);
    fb.fillRectangle(bar_area.x, bar_area.y, bar_area.width, bar_area.height, self.config.workspace_bar.background);

    switch (self.config.workspace_bar.location) {
        .left => fb.drawLine(
            bar_area.x + bar_area.width,
            bar_area.y,
            bar_area.x + bar_area.width,
            bar_area.y + bar_area.height,
            self.config.workspace_bar.border,
        ),
        .right => fb.drawLine(
            bar_area.x,
            0,
            bar_area.x,
            bar_area.height,
            self.config.workspace_bar.border,
        ),
        .top => fb.drawLine(
            bar_area.x,
            bar_area.y + bar_area.height,
            bar_area.x + bar_area.width,
            bar_area.y + bar_area.height,
            self.config.workspace_bar.border,
        ),
        .bottom => fb.drawLine(
            bar_area.x,
            bar_area.y,
            bar_area.x + bar_area.width,
            bar_area.y,
            self.config.workspace_bar.border,
        ),
    }

    const dragged_app_index: ?usize = switch (self.mode) {
        .app_drag_desktop => |index| index,
        .app_drag_menu => |index| index,
        else => null,
    };

    for (self.menu_items.items) |item, idx| {
        const button_rect = self.getMenuButtonRectangle(idx);

        switch (item) {
            .separator => {
                switch (self.config.workspace_bar.location) {
                    .top, .bottom => fb.drawLine(
                        button_rect.x,
                        button_rect.y,
                        button_rect.x,
                        button_rect.y + button_rect.height,
                        self.config.workspace_bar.border,
                    ),
                    .left, .right => fb.drawLine(
                        button_rect.x,
                        button_rect.y,
                        button_rect.x + button_rect.width,
                        button_rect.y,
                        self.config.workspace_bar.border,
                    ),
                }
            },
            .button => |button| {
                self.renderButton(
                    &fb,
                    button_rect,
                    if (dragged_app_index) |_|
                        if (button_rect.contains(self.mouse_pos) and button.data == .workspace)
                            ButtonState.hovered
                        else
                            ButtonState.normal
                    else
                        button.state,
                    self.config.workspace_bar.button_theme,
                    null,
                    switch (button.data) {
                        .app_menu => @as([]const u8, &icons.app_menu),
                        .workspace => &icons.workspace,
                    },
                    1.0,
                );
            },
        }
    }

    if (dragged_app_index) |_| {
        const button_rect = self.getMenuButtonRectangle(self.menu_items.items.len);

        self.renderButton(
            &fb,
            button_rect,
            if (button_rect.contains(self.mouse_pos))
                ButtonState.hovered
            else
                ButtonState.normal,
            self.config.workspace_bar.button_theme,
            null,
            &icons.workspace_add,
            1.0,
        );
    }

    for (self.menu_items.items) |item, button_index| {
        switch (item) {
            .button => |btn| {
                if (btn.data == .workspace) {
                    if (button_index == self.current_workspace) {
                        var hovered_rectangle: ?Rectangle = null;
                        self.renderWorkspace(&fb, workspace_area, btn.data.workspace, &hovered_rectangle);

                        if (self.mode != .app_menu) {
                            if (hovered_rectangle) |area| {
                                fb.drawRectangle(area.x, area.y, area.width, area.height, self.config.workspace.active_app_border);
                            }
                        }
                        if (self.mode == .app_drag_desktop) {
                            if (btn.data.workspace.window_tree.findInsertLocation(workspace_area, self.mouse_pos.x, self.mouse_pos.y)) |path| {
                                const insert_location = btn.data.workspace.window_tree.getInsertLocationRectangle(workspace_area, path);

                                fb.drawRectangle(
                                    insert_location.container.x,
                                    insert_location.container.y,
                                    insert_location.container.width,
                                    insert_location.container.height,
                                    self.config.workspace.insert_highlight_color,
                                );

                                fb.fillRectangle(
                                    insert_location.splitter.x,
                                    insert_location.splitter.y,
                                    insert_location.splitter.width,
                                    insert_location.splitter.height,
                                    self.config.workspace.insert_highlight_fill_color,
                                );
                            }
                        }
                        break;
                    }
                }
            },
            else => {},
        }
    }

    if (self.mode.isAppMenuVisible()) {
        const app_menu_button_rect = self.getMenuButtonRectangle(0);
        const app_menu_rect = self.getAppMenuRectangle();
        const layout = self.getAppMenuLayout();
        const margin = self.config.app_menu.margins;
        const button_size = self.config.app_menu.button_size;

        // draw dimmed background
        fb.fillRectangle(
            0,
            0,
            self.size.width,
            self.size.height,
            self.config.app_menu.dimmer,
        );

        // overdraw button
        {
            const button_rect = app_menu_button_rect;
            const icon_area = Rectangle{
                .x = button_rect.x + 1,
                .y = button_rect.y + 1,
                .width = button_rect.width - 2,
                .height = button_rect.height - 2,
            };

            fb.fillRectangle(
                icon_area.x,
                icon_area.y,
                icon_area.width,
                icon_area.height,
                self.config.app_menu.background,
            );
            fb.drawRectangle(
                button_rect.x,
                button_rect.y,
                button_rect.width,
                button_rect.height,
                self.config.app_menu.outline,
            );

            var icon_canvas = SubCanvas{
                .canvas = &fb,
                .x = icon_area.x,
                .y = icon_area.y,
                .width = icon_area.width,
                .height = icon_area.height,
            };

            tvg.render(
                &temp_allocator.allocator,
                icon_canvas,
                &icons.app_menu,
            ) catch unreachable;
            temp_allocator.reset();
        }

        // draw menu
        fb.fillRectangle(
            app_menu_rect.x + 1,
            app_menu_rect.y + 1,
            app_menu_rect.width - 2,
            app_menu_rect.height - 2,
            self.config.app_menu.background,
        );
        fb.drawRectangle(
            app_menu_rect.x,
            app_menu_rect.y,
            app_menu_rect.width,
            app_menu_rect.height,
            self.config.app_menu.outline,
        );

        fb.drawLine(
            app_menu_rect.x + margin + layout.cols * (margin + button_size),
            app_menu_rect.y + 1,
            app_menu_rect.x + margin + layout.cols * (margin + button_size),
            app_menu_rect.y + app_menu_rect.height - 1,
            self.config.app_menu.outline,
        );
        // draw menu connector
        {
            var i: u15 = 0;
            while (i < self.config.workspace_bar.margins + 2) : (i += 1) {
                switch (self.config.workspace_bar.location) {
                    .left => {
                        const x = app_menu_button_rect.x + app_menu_button_rect.width - 1 + i;
                        fb.setPixel(x, app_menu_button_rect.y, self.config.app_menu.outline);
                        fb.setPixel(x, app_menu_button_rect.y + app_menu_button_rect.height + i, self.config.app_menu.outline);
                        fb.drawLine(
                            x,
                            app_menu_button_rect.y + 1,
                            x,
                            app_menu_button_rect.y + app_menu_button_rect.height - 1 + i,
                            self.config.app_menu.background,
                        );
                    },
                    .right => {
                        const x = app_menu_button_rect.x - i;
                        fb.setPixel(x, app_menu_button_rect.y, self.config.app_menu.outline);
                        fb.setPixel(x, app_menu_button_rect.y + app_menu_button_rect.height + i, self.config.app_menu.outline);
                        fb.drawLine(
                            x,
                            app_menu_button_rect.y + 1,
                            x,
                            app_menu_button_rect.y + app_menu_button_rect.height - 1 + i,
                            self.config.app_menu.background,
                        );
                    },
                    .top => {
                        const y = app_menu_button_rect.y + app_menu_button_rect.height - 1 + i;
                        fb.setPixel(app_menu_button_rect.x, y, self.config.app_menu.outline);
                        fb.setPixel(app_menu_button_rect.x + app_menu_button_rect.width + i, y, self.config.app_menu.outline);
                        fb.drawLine(
                            app_menu_button_rect.x + 1,
                            y,
                            app_menu_button_rect.x + app_menu_button_rect.width - 1 + i,
                            y,
                            self.config.app_menu.background,
                        );
                    },
                    .bottom => {
                        const y = app_menu_button_rect.y - i;
                        fb.setPixel(app_menu_button_rect.x, y, self.config.app_menu.outline);
                        fb.setPixel(app_menu_button_rect.x + app_menu_button_rect.width + i, y, self.config.app_menu.outline);
                        fb.drawLine(
                            app_menu_button_rect.x + 1,
                            y,
                            app_menu_button_rect.x + app_menu_button_rect.width - 1 + i,
                            y,
                            self.config.app_menu.background,
                        );
                    },
                }
            }
        }

        for (self.available_apps.items) |app, app_index| {
            const rect = self.getAppButtonRectangle(app_index);

            // Do not draw the dragged app in the menu
            if (dragged_app_index != null and (dragged_app_index.? == app_index))
                continue;

            self.renderButton(
                &fb,
                rect,
                app.button_state,
                self.config.app_menu.button_theme,
                app.application.display_name,
                app.application.icon orelse icons.app_placeholder,
                1.0,
            );
        }
    }
    if (dragged_app_index) |index| {
        const app = self.available_apps.items[index];
        const button_size = self.config.app_menu.button_size;

        const rect = Rectangle{
            .x = self.mouse_pos.x - button_size / 2,
            .y = self.mouse_pos.y - button_size / 2,
            .width = button_size,
            .height = button_size,
        };
        self.renderButton(
            &fb,
            rect,
            ButtonState.pressed,
            self.config.app_menu.button_theme,
            app.application.display_name,
            app.application.icon orelse icons.app_placeholder,
            0.5,
        );
    }
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

fn renderButton(
    self: *Self,
    framebuffer: anytype,
    rectangle: Rectangle,
    state: ButtonState,
    theme: ButtonTheme,
    text: ?[]const u8,
    icon: ?[]const u8,
    alpha: f32,
) void {
    const interp_hover = smoothstep(state.visual_highlight, 0.0, 1.0);
    var back_color = lerpColor(theme.default.background, theme.hovered.background, interp_hover);
    var outline_color = lerpColor(theme.default.outline, theme.hovered.outline, interp_hover);

    if (state.visual_pressed > 0.0) {
        const interp_click = smoothstep(state.visual_pressed, 0.0, 1.0);
        back_color = lerpColor(back_color, theme.clicked.background, interp_click);
        outline_color = lerpColor(outline_color, theme.clicked.outline, interp_click);
    }

    back_color.a = alphaBlend(back_color.a, alpha);
    outline_color.a = alphaBlend(back_color.a, alpha);

    framebuffer.fillRectangle(
        rectangle.x + 1,
        rectangle.y + 1,
        rectangle.width - 1,
        rectangle.height - 1,
        back_color,
    );
    framebuffer.drawRectangle(
        rectangle.x,
        rectangle.y,
        rectangle.width,
        rectangle.height,
        outline_color,
    );

    const icon_size = std.math.min(rectangle.width - 2, theme.icon_size);

    if (icon) |icon_source| {
        if (icon_size > 0) {
            var temp_buffer: [4096]u8 = undefined;
            var temp_allocator = std.heap.FixedBufferAllocator.init(&temp_buffer);

            var icon_canvas = SubCanvas{
                .canvas = framebuffer,
                .x = rectangle.x + (rectangle.width - icon_size) / 2,
                .y = rectangle.y + (rectangle.height - icon_size) / 2,
                .width = icon_size,
                .height = icon_size,
                .alpha = alpha,
            };

            // Debug painter: Draw the outline of the icon
            // framebuffer.drawRectangle(
            //     icon_canvas.x,
            //     icon_canvas.y,
            //     icon_canvas.width,
            //     icon_canvas.height,
            //     Color{ .r = 0xFF, .g = 0x00, .b = 0xFF },
            // );

            tvg.render(
                &temp_allocator.allocator,
                icon_canvas,
                icon_source,
            ) catch {}; // on error, just "fuck it" and let the icon be half-rendered
            temp_allocator.reset();
        }
    }

    if (text) |label| {
        if (label.len > 0) {
            const top = ((rectangle.height + icon_size) / 2 + rectangle.height) / 2;

            // Debug painter: draw the middle line of the button label
            // framebuffer.drawLine(
            //     rectangle.x,
            //     rectangle.y + top,
            //     rectangle.x + rectangle.width,
            //     rectangle.y + top,
            //     Color{ .r = 0xFF, .g = 0x00, .b = 0xFF },
            // );

            const size = self.app_button_font.measureString(label);

            self.app_button_font.drawString(
                framebuffer.framebuffer.subView(rectangle.x, rectangle.y, rectangle.width, rectangle.height),
                label,
                (rectangle.width - size.width) / 2,
                @intCast(u15, top - self.app_button_font.font_size / 2),
                .{ .r = 0xFF, .g = 0xFF, .b = 0xFF }, // TODO: Introduce proper config here
            );
        }
    }
}

fn renderWorkspace(self: *Self, canvas: *Canvas, area: Rectangle, workspace: Workspace, hovered_rectangle: *?Rectangle) void {
    self.renderTreeNode(canvas, area, workspace.window_tree.root, hovered_rectangle);
}

fn renderTreeNode(self: *Self, canvas: *Canvas, area: Rectangle, node: WindowTree.Node, hovered_rectangle: *?Rectangle) void {
    if (area.contains(self.mouse_pos) and (node == .empty or node == .starting or node == .connected))
        hovered_rectangle.* = area;
    switch (node) {
        .empty => {
            canvas.drawRectangle(
                area.x,
                area.y,
                area.width,
                area.height,
                HomeScreenConfig.rgb("363c42"),
            );
            //canvas.fillRectangle(area.x + 1, area.y + 1, area.width - 2, area.height - 2, Color{ .r = 0x80, .g = 0x00, .b = 0x00 });
        },
        .starting => |app| {
            const icon_size = std.math.min(area.width - 2, self.config.workspace.app_icon_size);
            if (icon_size > 0) {
                var temp_buffer: [4096]u8 = undefined;
                var temp_allocator = std.heap.FixedBufferAllocator.init(&temp_buffer);

                var icon_canvas = SubCanvas{
                    .canvas = canvas,
                    .x = area.x + (area.width - icon_size) / 2,
                    .y = area.y + (area.height - icon_size) / 2,
                    .width = icon_size,
                    .height = icon_size,
                };

                tvg.render(
                    &temp_allocator.allocator,
                    icon_canvas,
                    app.application.description.icon orelse icons.app_placeholder,
                ) catch {}; // on error, just "fuck it" and let the icon be half-rendered
                temp_allocator.reset();
            }

            const display_name = app.application.description.display_name;
            if (display_name.len > 0) {
                const size = self.app_title_font.measureString(display_name);
                self.app_title_font.drawString(
                    canvas.framebuffer.subView(area.x, area.y, area.width, area.height),
                    display_name,
                    (area.width - size.width) / 2,
                    (area.height - icon_size) / 2 - self.app_title_font.font_size,
                    .{ .r = 0xFF, .g = 0xFF, .b = 0xFF }, // TODO: Replace by theme config
                );
            }

            const startup_message = app.application.status.starting; // this is safe as the status might only be changed in the update fn
            if (startup_message.len > 0) {
                const size = self.app_status_font.measureString(startup_message);
                self.app_status_font.drawString(
                    canvas.framebuffer.subView(area.x, area.y, area.width, area.height),
                    startup_message,
                    (area.width - size.width) / 2,
                    (area.height + icon_size) / 2,
                    .{ .r = 0xFF, .g = 0xFF, .b = 0xFF }, // TODO: Replace by theme config
                );
            }
        },
        .connected => |app| {
            app.application.render(canvas.framebuffer.subView(area.x, area.y, area.width, area.height)) catch |err| log.err("failed to render application '{s}': {s}", .{
                app.application.description.display_name,
                @errorName(err),
            });
        },
        .exited => |app| {
            const exit_message = app.application.status.exited; // this is safe as the status might only be changed in the update fn
            if (exit_message.len > 0) {
                const size = self.app_status_font.measureString(exit_message);
                self.app_status_font.drawString(
                    canvas.framebuffer.subView(area.x, area.y, area.width, area.height),
                    exit_message,
                    (area.width - size.width) / 2,
                    area.height / 2,
                    .{ .r = 0xFF, .g = 0x00, .b = 0x00 }, // TODO: Replace by theme config
                );
            }
        },
        .group => |group| {
            // if we have 1 or less children, the tree would be denormalized.
            // we assume we have a normalized tree at this point.
            std.debug.assert(group.children.len >= 2);
            switch (group.split) {
                .vertical => {
                    const item_height = area.height / group.children.len;
                    for (group.children) |item, i| {
                        const h = if (i == group.children.len - 1)
                            item_height
                        else
                            (area.height - item_height * (group.children.len - 1));
                        var child_area = area;
                        child_area.y += @intCast(u15, item_height * i);
                        child_area.height = @intCast(u15, h);
                        self.renderTreeNode(canvas, child_area, item, hovered_rectangle);
                    }
                },
                .horizontal => {
                    const item_width = area.width / group.children.len;
                    for (group.children) |item, i| {
                        const w = if (i == group.children.len - 1)
                            item_width
                        else
                            (area.width - item_width * (group.children.len - 1));
                        var child_area = area;
                        child_area.x += @intCast(u15, item_width * i);
                        child_area.width = @intCast(u15, w);
                        self.renderTreeNode(canvas, child_area, item, hovered_rectangle);
                    }
                },
            }
        },
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

                if (index < old_items.len) {
                    std.mem.copy(Node, new_items[0..index], old_items[0..index]);
                }
                if (index > 0) {
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

fn setFramebufferPixel(target: Framebuffer, x: isize, y: isize, col: Framebuffer.Color) void {
    if (x < 0 or y < 0)
        return;
    if (x >= target.width or y >= target.height)
        return;
    const px = @intCast(usize, x);
    const py = @intCast(usize, y);
    const slot = &target.scanline(py)[px];

    switch (col.a) {
        0 => return, // no blending, fully transparent
        else => {
            var old = slot.*;
            slot.* = lerpColor(old, col, @intToFloat(f32, col.a) / 255.0);
            slot.a = 0xFF;
        },
        255 => slot.* = col, // 100% opaque
    }
}