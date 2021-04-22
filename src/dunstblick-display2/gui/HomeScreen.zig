const std = @import("std");
const painterz = @import("painterz");
const tvg = @import("tvg");

const icons = @import("icons/data.zig");

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

    button_size: u15 = 50,
    button_margin: u15 = 8,

    button_base: ButtonColors = ButtonColors{
        .outline = Color.rgb("363c42"),
        .background = Color.rgb("292f35"),
    },
    button_hovered: ButtonColors = ButtonColors{
        .outline = Color.rgb("1abc9c"),
        .background = Color.rgb("255953"),
    },
    button_active: ButtonColors = ButtonColors{
        .outline = Color.rgb("1abc9c"),
        .background = Color.rgb("0e443f"),
    },

    bar_background: Color = Color.rgb("292f35"),
    bar_outline: Color = Color.rgb("212529"),

    background_color: Color = Color.rgb("263238"),
};

const MouseMode = union(enum) {
    /// Nothing special is happening, the user is moving the mouse and can click buttons
    /// by clicking them with pressing and releasing the mouse button in them.
    /// Widget interaction on the workspaces behave normal.
    default,

    /// The mouse was pressed on a button and is now held.
    /// The value is the index of the button that was pressed.
    button_press: usize,
};

allocator: *std.mem.Allocator,
size: Size,
config: HomeScreenConfig,
mouse_pos: Point,

current_workspace: usize,

menu_items: std.ArrayList(MenuItem),

mouse_mode: MouseMode,

pub fn init(allocator: *std.mem.Allocator, initial_size: Size) !Self {
    var self = Self{
        .allocator = allocator,
        .size = initial_size,
        .menu_items = std.ArrayList(MenuItem).init(allocator),
        .config = HomeScreenConfig{},
        .mouse_pos = Point{ .x = 0, .y = 0 },
        .current_workspace = 0,
        .mouse_mode = .default,
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
    self.* = undefined;
}

pub fn resize(self: *Self, size: Size) !void {
    self.size = size;
}

pub fn setMousePos(self: *Self, pos: Point) void {
    self.mouse_pos = pos;
}

pub fn mouseDown(self: *Self, mouse_button: Display.MouseButton) !void {
    if (mouse_button != .left)
        return;

    switch (self.mouse_mode) {
        .default => {
            // Check if the user pressed the mouse on a button
            for (self.menu_items.items) |btn, i| {
                const rect = self.getMenuButtonRectangle(i);
                if (rect.contains(self.mouse_pos)) {
                    self.mouse_mode = .{ .button_press = i };
                    return;
                }
            }
        },
        .button_press => unreachable,
    }
}

pub fn mouseUp(self: *Self, mouse_button: Display.MouseButton) !void {
    if (mouse_button != .left)
        return;

    switch (self.mouse_mode) {
        .default => {
            // do nothing on a mouse-up, we process clicks via .button_press
        },
        .button_press => |button| {
            defer self.mouse_mode = .default;

            const rect = self.getMenuButtonRectangle(button);

            if (rect.contains(self.mouse_pos)) {
                // we actually clicked that button!
                std.log.info("clcked on button {}: {}", .{ button, self.menu_items.items[button] });
            }
        },
    }
}

pub fn update(self: *Self, dt: f32) !void {
    var hovered_button: ?usize = for (self.menu_items.items) |_, idx| {
        const button_rect = self.getMenuButtonRectangle(idx);
        if (button_rect.contains(self.mouse_pos))
            break idx;
    } else null;

    for (self.menu_items.items) |*item, idx| {
        switch (item.*) {
            .button => |*button| {
                button.clicked = (self.mouse_mode == .button_press and self.mouse_mode.button_press == idx);
                button.hovered = (if (hovered_button) |i| (i == idx) else false);
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

    const bar_width = 2 * self.config.button_margin + self.config.button_size;

    const workspace_area = Rectangle{
        .x = bar_width + 1,
        .y = 0,
        .width = self.size.width - bar_width - 1,
        .height = self.size.height,
    };

    fb.fillRectangle(workspace_area.x, workspace_area.y, workspace_area.width, workspace_area.height, self.config.background_color);
    fb.fillRectangle(0, 0, bar_width, self.size.height, self.config.bar_background);
    fb.drawLine(
        2 * self.config.button_margin + self.config.button_size,
        0,
        2 * self.config.button_margin + self.config.button_size,
        self.size.height,
        self.config.bar_outline,
    );

    for (self.menu_items.items) |item, idx| {
        const button_rect = self.getMenuButtonRectangle(idx);

        switch (item) {
            .separator => {
                fb.drawLine(
                    0,
                    button_rect.y,
                    2 * self.config.button_margin + self.config.button_size,
                    button_rect.y,
                    self.config.bar_outline,
                );
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

                            if (hovered_rectangle) |area| {
                                fb.drawRectangle(area.x, area.y, area.width, area.height, Color.rgb("255853"));
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
                Color.rgb("363c42"),
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

fn getMenuButtonRectangle(self: Self, index: usize) Rectangle {
    var offset_y: u15 = self.config.button_margin;

    for (self.menu_items.items[0..index]) |item| {
        offset_y += self.config.button_margin;
        switch (item) {
            .separator => offset_y += 1,
            .button => offset_y += self.config.button_size,
        }
    }

    const height = switch (self.menu_items.items[index]) {
        .separator => 1,
        .button => self.config.button_size,
    };

    return Rectangle{
        .x = self.config.button_margin,
        .y = offset_y,
        .width = self.config.button_size,
        .height = height,
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
    target.scanline(py)[px] = col;
}
