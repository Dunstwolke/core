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

const Canvas = painterz.Canvas(Framebuffer, Framebuffer.Color, setFramebufferPixel);

const HomeScreenConfig = struct {
    const ButtonColors = struct {
        outline: Color,
        background: Color,
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

    button_size: u15 = 50,
    button_margin: u15 = 8,

    app_button_size: u15 = 100,
    app_icon_size: u15 = 64,
    app_scrollbar_width: u15 = 8,

    button_base: ButtonColors = ButtonColors{
        .outline = rgb("363c42"),
        .background = rgb("292f35"),
    },
    button_hovered: ButtonColors = ButtonColors{
        .outline = rgb("1abc9c"),
        .background = rgb("255953"),
    },
    button_active: ButtonColors = ButtonColors{
        .outline = rgb("1abc9c"),
        .background = rgb("0e443f"),
    },

    bar_background: Color = rgb("292f35"),
    bar_outline: Color = rgb("212529"),

    background_color: Color = rgb("263238"),

    app_menu_dimmer: Color = rgba("292f35", 0.5),
    app_menu_outline: Color = rgb("1abc9c"),
    app_menu_background: Color = rgb("255953"),

    bar_location: BarLocation = .left,

    fn getBarWidth(config: @This()) u15 {
        return 2 * config.button_margin + config.button_size;
    }
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
};

const BarLocation = enum {
    top,
    bottom,
    left,
    right,
};

/// An application available in the app menu
const App = struct {
    /// The name that is displayed to the user
    display_name: []const u8,

    /// The TVG icon of the application
    icon: []const u8,
};

allocator: *std.mem.Allocator,
size: Size,
config: HomeScreenConfig,
mouse_pos: Point,

current_workspace: usize,

menu_items: std.ArrayList(MenuItem),

available_apps: std.ArrayList(App),

mode: MouseMode,

pub fn init(allocator: *std.mem.Allocator, initial_size: Size) !Self {
    var self = Self{
        .allocator = allocator,
        .size = initial_size,
        .menu_items = std.ArrayList(MenuItem).init(allocator),
        .config = HomeScreenConfig{},
        .mouse_pos = Point{ .x = 0, .y = 0 },
        .current_workspace = 0,
        .mode = .default,
        .available_apps = std.ArrayList(App).init(allocator),
    };

    try self.menu_items.append(MenuItem{ .button = Button{ .data = .app_menu } });
    try self.menu_items.append(.separator);
    try self.menu_items.append(MenuItem{ .button = Button{ .data = .{ .workspace = Workspace.init(allocator) } } });
    try self.menu_items.append(MenuItem{ .button = Button{ .data = .new_workspace } });

    {
        const ws: *Workspace = &self.menu_items.items[2].button.data.workspace;

        var v_children = try allocator.alloc(WindowTree.Node, 3);
        errdefer allocator.free(v_children);

        v_children[0] = .empty;
        v_children[1] = .empty;
        v_children[2] = .empty;

        var h_children = try allocator.alloc(WindowTree.Node, 2);
        errdefer allocator.free(h_children);

        h_children[0] = .empty;
        h_children[1] = WindowTree.Node{ .group = WindowTree.Group{
            .split = .vertical,
            .children = v_children,
        } };

        ws.window_tree.root = WindowTree.Node{ .group = WindowTree.Group{
            .split = .horizontal,
            .children = h_children,
        } };
    }

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
    self.* = undefined;
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
        if (self.mouse_pos.x >= self.size.width / 2) {
            self.config.bar_location = switch (self.config.bar_location) {
                .top => BarLocation.right,
                .right => BarLocation.bottom,
                .bottom => BarLocation.left,
                .left => BarLocation.top,
            };
        } else {
            const names = [_][]const u8{
                "Archive Manager",
                "Calculator",
                "Mahjongg",
                "Notepad",
                "Notes",
                "Text Editor",
                "Gemini Browser",
                "Web Browser",
            };

            try self.available_apps.append(App{
                .display_name = names[rng.random.uintLessThan(usize, names.len)],
                .icon = &icons.app_placeholder,
            });
        }
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
            // TODO: Process clicks on apps and the background
        },
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

                            else => log.info("clicked on button {}: {}", .{ button_index, button.data }),
                        }
                    },

                    else => log.info("clicked on something else {}: {}", .{ button_index, std.meta.activeTag(menu_item.*) }),
                }
            }
        },
        .app_menu => {},
    }
}

pub fn update(self: *Self, dt: f32) !void {
    var hovered_button: ?usize = null;
    switch (self.mode) {
        .default, .button_press => {
            hovered_button = for (self.menu_items.items) |_, idx| {
                const button_rect = self.getMenuButtonRectangle(idx);
                if (button_rect.contains(self.mouse_pos))
                    break idx;
            } else null;
        },
        .app_menu => {
            // todo: do app menu here
        },
    }

    for (self.menu_items.items) |*item, idx| {
        switch (item.*) {
            .button => |*button| {
                button.clicked = (self.mode == .button_press and self.mode.button_press == idx);
                button.hovered = (if (hovered_button) |i| (i == idx) else false) or ((button.data == .app_menu) and (self.mode == .app_menu));
                button.update(dt);
            },
            else => {},
        }
    }
}

pub fn render(self: Self, target: Framebuffer) void {
    var temp_buffer: [4096]u8 = undefined;
    var temp_allocator = std.heap.FixedBufferAllocator.init(&temp_buffer);

    var fb = Canvas.init(target);

    const SubCanvas = struct {
        canvas: *Canvas,

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
                .a = color[3],
            });
        }
    };

    const bar_width = self.config.getBarWidth();

    const workspace_area = self.getWorkspaceRectangle();

    const bar_area = self.getBarRectangle();

    fb.fillRectangle(workspace_area.x, workspace_area.y, workspace_area.width, workspace_area.height, self.config.background_color);
    fb.fillRectangle(bar_area.x, bar_area.y, bar_area.width, bar_area.height, self.config.bar_background);

    switch (self.config.bar_location) {
        .left => fb.drawLine(
            bar_area.x + bar_area.width,
            bar_area.y,
            bar_area.x + bar_area.width,
            bar_area.y + bar_area.height,
            self.config.bar_outline,
        ),
        .right => fb.drawLine(
            bar_area.x,
            0,
            bar_area.x,
            bar_area.height,
            self.config.bar_outline,
        ),
        .top => fb.drawLine(
            bar_area.x,
            bar_area.y + bar_area.height,
            bar_area.x + bar_area.width,
            bar_area.y + bar_area.height,
            self.config.bar_outline,
        ),
        .bottom => fb.drawLine(
            bar_area.x,
            bar_area.y,
            bar_area.x + bar_area.width,
            bar_area.y,
            self.config.bar_outline,
        ),
    }

    for (self.menu_items.items) |item, idx| {
        const button_rect = self.getMenuButtonRectangle(idx);

        switch (item) {
            .separator => {
                switch (self.config.bar_location) {
                    .top, .bottom => fb.drawLine(
                        button_rect.x,
                        button_rect.y,
                        button_rect.x,
                        button_rect.y + button_rect.height,
                        self.config.bar_outline,
                    ),
                    .left, .right => fb.drawLine(
                        button_rect.x,
                        button_rect.y,
                        button_rect.x + button_rect.width,
                        button_rect.y,
                        self.config.bar_outline,
                    ),
                }
            },
            .button => |button| {
                const icon_area = Rectangle{
                    .x = button_rect.x + 1,
                    .y = button_rect.y + 1,
                    .width = button_rect.width - 2,
                    .height = button_rect.height - 2,
                };

                const interp_hover = smoothstep(button.visual_highlight, 0.0, 1.0);
                var back_color = lerpColor(self.config.button_base.background, self.config.button_hovered.background, interp_hover);
                var outline_color = lerpColor(self.config.button_base.outline, self.config.button_hovered.outline, interp_hover);

                if (button.visual_pressed > 0.0) {
                    const interp_click = smoothstep(button.visual_pressed, 0.0, 1.0);
                    back_color = lerpColor(back_color, self.config.button_active.background, interp_click);
                    outline_color = lerpColor(outline_color, self.config.button_active.outline, interp_click);
                }

                fb.fillRectangle(
                    icon_area.x,
                    icon_area.y,
                    icon_area.width,
                    icon_area.height,
                    back_color,
                );
                fb.drawRectangle(
                    button_rect.x,
                    button_rect.y,
                    button_rect.width,
                    button_rect.height,
                    outline_color,
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
                    switch (button.data) {
                        .app_menu => @as([]const u8, &icons.app_menu),
                        .workspace => &icons.workspace,
                        .new_workspace => &icons.workspace_add,
                    },
                ) catch unreachable;
                temp_allocator.reset();
            },
        }
    }

    {
        var i: usize = 0;
        for (self.menu_items.items) |item| {
            switch (item) {
                .button => |btn| {
                    if (btn.data == .workspace) {
                        if (i == self.current_workspace) {
                            var hovered_rectangle: ?Rectangle = null;
                            self.renderWorkspace(&fb, workspace_area, btn.data.workspace, &hovered_rectangle);

                            if (self.mode != .app_menu) {
                                if (hovered_rectangle) |area| {
                                    fb.drawRectangle(area.x, area.y, area.width, area.height, HomeScreenConfig.rgb("255853"));
                                }
                            }
                            break;
                        } else {
                            i += 1;
                        }
                    }
                },
                else => {},
            }
        }
    }

    if (self.mode == .app_menu) {
        fb.fillRectangle(
            0,
            0,
            self.size.width,
            self.size.height,
            self.config.app_menu_dimmer,
        );
    }
    {
        const app_menu_rect = self.getAppMenuRectangle();
        const layout = self.getAppMenuLayout();
        const margin = self.config.button_margin;
        const button_size = self.config.app_button_size;

        fb.fillRectangle(
            app_menu_rect.x + 1,
            app_menu_rect.y + 1,
            app_menu_rect.width - 2,
            app_menu_rect.height - 2,
            self.config.app_menu_background,
        );
        fb.drawRectangle(
            app_menu_rect.x,
            app_menu_rect.y,
            app_menu_rect.width,
            app_menu_rect.height,
            self.config.app_menu_outline,
        );

        fb.drawLine(
            app_menu_rect.x + margin + layout.cols * (margin + button_size),
            app_menu_rect.y + 1,
            app_menu_rect.x + margin + layout.cols * (margin + button_size),
            app_menu_rect.y + app_menu_rect.height - 1,
            self.config.app_menu_outline,
        );

        var row: u15 = 0;
        var col: u15 = 0;
        for (self.available_apps.items) |item| {
            const x = app_menu_rect.x + margin + col * (margin + button_size);
            const y = app_menu_rect.y + margin + row * (margin + button_size);

            fb.drawRectangle(
                x,
                y,
                button_size,
                button_size,
                self.config.app_menu_outline,
            );

            var icon_canvas = SubCanvas{
                .canvas = &fb,
                .x = x + (button_size - self.config.app_icon_size) / 2,
                .y = y + (button_size - self.config.app_icon_size) / 2,
                .width = self.config.app_icon_size,
                .height = self.config.app_icon_size,
            };

            tvg.render(&temp_allocator.allocator, icon_canvas, item.icon) catch unreachable;
            temp_allocator.reset();

            col += 1;
            if (col >= layout.cols) {
                col = 0;
                row += 1;
            }
            if (row >= layout.rows)
                break;
        }
    }
}

fn initColor(r: u8, g: u8, b: u8, a: u8) Color {
    return Color{ .r = r, .g = g, .b = b, .a = a };
}

fn renderWorkspace(self: Self, canvas: *Canvas, area: Rectangle, workspace: Workspace, hovered_rectangle: *?Rectangle) void {
    self.renderTreeNode(canvas, area, workspace.window_tree.root, hovered_rectangle);
}

fn renderTreeNode(self: Self, canvas: *Canvas, area: Rectangle, node: WindowTree.Node, hovered_rectangle: *?Rectangle) void {
    if (area.contains(self.mouse_pos) and (node == .empty or node == .window))
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
        .window => |window| @panic("rendering windows not supported yet!"),
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
    const bar_width = self.config.getBarWidth();
    return switch (self.config.bar_location) {
        .top => Rectangle{ .x = 0, .y = 0, .width = self.size.width, .height = bar_width },
        .bottom => Rectangle{ .x = 0, .y = self.size.height - bar_width, .width = self.size.width, .height = bar_width },
        .left => Rectangle{ .x = 0, .y = 0, .width = bar_width, .height = self.size.height },
        .right => Rectangle{ .x = self.size.width - bar_width, .y = 0, .width = bar_width, .height = self.size.height },
    };
}

fn getWorkspaceRectangle(self: Self) Rectangle {
    const bar_width = self.config.getBarWidth();
    return switch (self.config.bar_location) {
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
    const max_cols: u15 = std.math.max(3, (self.size.width - self.config.getBarWidth() - 3 * self.config.button_margin) / (self.config.button_margin + self.config.app_button_size));
    const max_rows: u15 = std.math.max(2, (self.size.height - self.config.getBarWidth() - 2 * self.config.button_margin) / (self.config.button_margin + self.config.app_button_size));

    const layout = AppMenuLayout{
        .cols = std.math.clamp(@floatToInt(u15, cols_f), 3, max_cols),
        .rows = std.math.clamp(@floatToInt(u15, rows_f), 2, max_rows),
    };
    // std.debug.assert(layout.rows * layout.cols >= count);

    return layout;
}

fn getAppMenuRectangle(self: Self) Rectangle {
    const app_button_rect = self.getMenuButtonRectangle(0);
    const layout = self.getAppMenuLayout();
    const margin = self.config.button_margin;
    const button_size = self.config.app_button_size;

    // The rectangle has some margins for scroll bar and 1 pixel lines
    const width = @intCast(u15, 3 + 2 * margin + button_size * layout.cols + (layout.cols - 1) * margin + self.config.app_scrollbar_width);
    const height = @intCast(u15, 2 + 2 * margin + button_size * layout.rows + (layout.rows - 1) * margin);

    return switch (self.config.bar_location) {
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
    var offset: u15 = self.config.button_margin;

    for (self.menu_items.items[0..index]) |item| {
        offset += self.config.button_margin;
        switch (item) {
            .separator => offset += 1,
            .button => offset += self.config.button_size,
        }
    }

    const size = switch (self.menu_items.items[index]) {
        .separator => 1,
        .button => self.config.button_size,
    };

    const base_rect = self.getBarRectangle();

    return switch (self.config.bar_location) {
        .left, .right => Rectangle{
            .x = base_rect.x + self.config.button_margin,
            .y = base_rect.y + offset,
            .width = self.config.button_size,
            .height = size,
        },
        .top, .bottom => Rectangle{
            .x = base_rect.x + offset,
            .y = base_rect.y + self.config.button_margin,
            .width = size,
            .height = self.config.button_size,
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
        new_workspace,
    };

    data: Data,
    hovered: bool = false,
    clicked: bool = false,

    visual_highlight: f32 = 0.0,
    visual_pressed: f32 = 0.0,

    fn update(self: *Button, dt: f32) void {
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

const WindowTree = struct {
    const Layout = enum {
        /// Windows are stacked on top of each other.
        vertical,

        /// Windows are side-by-side next to each other
        horizontal,
    };

    const Window = struct {
        window: void,
    };

    const Group = struct {
        split: Layout,
        children: []Node,
    };

    const Node = union(enum) {
        window: Window,
        group: Group,
        empty,
    };

    /// A relative screen rectangle. Base coordinates are [0,0,1,1]
    const Rectangle = struct {
        x: f32,
        y: f32,
        width: f32,
        height: f32,
    };

    allocator: *std.mem.Allocator,
    root: Node,

    fn destroyNode(self: WindowTree, node: *Node) void {
        switch (node.*) {
            .empty => {},
            .group => |group| {
                for (group.children) |*child| {
                    self.destroyNode(child);
                }
                self.allocator.free(group.children);
            },
            .window => @panic("Destroying windows not implemented yet!"),
        }

        node.* = undefined;
    }

    fn findWindowRecursive(self: *WindowTree, area: Rectangle, x: f32, y: f32) ?*Window {
        std.debug.assert(x >= 0.0 and x <= 1.0);
        std.debug.assert(y >= 0.0 and y <= 1.0);
    }

    fn findWindow(self: *WindowTree, x: f32, y: f32) ?*Window {
        return self.findWindowRecursive(Rectangle{ .x = 0, .y = 0, .width = 1, .height = 1 }, x, y);
    }

    fn deinit(self: *WindowTree) void {
        self.destroyNode(&self.root);
        self.* = undefined;
    }
};

// https://en.wikipedia.org/wiki/Smoothstep
fn smoothstep(x: f32, edge0: f32, edge1: f32) f32 {
    // Scale, bias and saturate x to 0..1 range
    const f = std.math.clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0);
    // Evaluate polynomial
    return f * f * (3 - 2 * f);
}

fn lerpColor(a: Color, b: Color, x: f32) Color {
    const cx = std.math.clamp(x, 0.0, 1.0);
    return Color{
        .r = @floatToInt(u8, lerp(@intToFloat(f32, a.r), @intToFloat(f32, b.r), cx)),
        .g = @floatToInt(u8, lerp(@intToFloat(f32, a.g), @intToFloat(f32, b.g), cx)),
        .b = @floatToInt(u8, lerp(@intToFloat(f32, a.b), @intToFloat(f32, b.b), cx)),
        .a = @floatToInt(u8, lerp(@intToFloat(f32, a.a), @intToFloat(f32, b.a), cx)),
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
            slot.* = lerpColor(slot.*, col, @intToFloat(f32, col.a) / 255.0);
            slot.a = 0xFF;
        },
        255 => slot.* = col, // 100% opaque
    }
}
