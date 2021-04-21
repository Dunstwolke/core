const std = @import("std");
const painterz = @import("painterz");
const tvg = @import("tvg");

const Self = @This();

const Point = @import("Point.zig");
const Size = @import("Size.zig");
const Rectangle = @import("Rectangle.zig");
const Framebuffer = @import("Framebuffer.zig");
const Color = Framebuffer.Color;

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
        .background = Color.rgb("1e524c"),
    },

    bar_background: Color = Color.rgb("292f35"),
    bar_outline: Color = Color.rgb("212529"),

    background_color: Color = Color.rgb("263238"),
};

allocator: *std.mem.Allocator,
size: Size,
config: HomeScreenConfig,
mouse_pos: Point,

current_workspace: usize,

buttons: std.ArrayList(Button),

pub fn init(allocator: *std.mem.Allocator, initial_size: Size) !Self {
    var self = Self{
        .allocator = allocator,
        .size = initial_size,
        .buttons = std.ArrayList(Button).init(allocator),
        .config = HomeScreenConfig{},
        .mouse_pos = Point{ .x = 0, .y = 0 },
        .current_workspace = 0,
    };

    try self.buttons.append(Button{ .data = .app_menu });
    try self.buttons.append(Button{ .data = .{ .workspace = Workspace.init(allocator) } });
    try self.buttons.append(Button{ .data = .new_workspace });

    {
        const ws: *Workspace = &self.buttons.items[1].data.workspace;

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
    for (self.buttons.items) |*ws| {
        ws.deinit();
    }
    self.buttons.deinit();
    self.* = undefined;
}

pub fn resize(self: *Self, size: Size) !void {
    self.size = size;
}

pub fn setMousePos(self: *Self, pos: Point) void {
    self.mouse_pos = pos;
}

pub fn update(self: *Self, dt: f32) !void {
    for (self.buttons.items) |*button, idx| {
        const button_rect = self.getMenuButtonRectangle(idx);

        button.hovered = button_rect.contains(self.mouse_pos);

        button.update(dt);
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

    for (self.buttons.items) |button, idx| {
        const button_rect = self.getMenuButtonRectangle(idx);

        const interp = smoothstep(button.highlight, 0.0, 1.0);

        const icon_area = Rectangle{
            .x = button_rect.x + 1,
            .y = button_rect.y + 1,
            .width = button_rect.width - 2,
            .height = button_rect.height - 2,
        };

        fb.drawRectangle(
            button_rect.x,
            button_rect.y,
            button_rect.width,
            button_rect.height,
            lerpColor(self.config.button_base.outline, self.config.button_hovered.outline, interp),
        );
        fb.fillRectangle(
            icon_area.x,
            icon_area.y,
            icon_area.width,
            icon_area.height,
            lerpColor(self.config.button_base.background, self.config.button_hovered.background, interp),
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
    }

    {
        var i: usize = 0;
        for (self.buttons.items) |btn| {
            if (btn.data == .workspace) {
                if (i == self.current_workspace) {
                    self.renderWorkspace(&fb, workspace_area, btn.data.workspace);
                    break;
                } else {
                    i += 1;
                }
            }
        }
    }
}

const icons = struct {
    const builder = tvg.builder(.@"1/256");

    const app_menu = blk: {
        @setEvalBranchQuota(10_000);

        break :blk builder.header(48, 48) ++
            builder.colorTable(&[_]tvg.Color{
            tvg.Color.fromString("000000") catch unreachable,
        }) ++
            builder.fillPolygon(4, .flat, 0) ++
            builder.point(6, 12) ++
            builder.point(42, 12) ++
            builder.point(42, 16) ++
            builder.point(6, 16) ++
            builder.fillPolygon(4, .flat, 0) ++
            builder.point(6, 22) ++
            builder.point(42, 22) ++
            builder.point(42, 26) ++
            builder.point(6, 26) ++
            builder.fillPolygon(4, .flat, 0) ++
            builder.point(6, 32) ++
            builder.point(42, 32) ++
            builder.point(42, 36) ++
            builder.point(6, 36) ++
            builder.end_of_document;
    };

    const workspace = blk: {
        @setEvalBranchQuota(10_000);

        break :blk builder.header(48, 48) ++
            builder.colorTable(&[_]tvg.Color{
            tvg.Color.fromString("008751") catch unreachable,
            tvg.Color.fromString("83769c") catch unreachable,
            tvg.Color.fromString("1d2b53") catch unreachable,
        }) ++
            builder.fillRectangles(1, .flat, 0) ++
            builder.rectangle(6, 6, 16, 36) ++
            builder.fillRectangles(1, .flat, 1) ++
            builder.rectangle(26, 6, 16, 16) ++
            builder.fillRectangles(1, .flat, 2) ++
            builder.rectangle(26, 26, 16, 16) ++
            builder.end_of_document;
    };

    const workspace_add = blk: {
        @setEvalBranchQuota(10_000);

        break :blk builder.header(48, 48) ++
            builder.colorTable(&[_]tvg.Color{
            tvg.Color.fromString("008751") catch unreachable,
            tvg.Color.fromString("83769c") catch unreachable,
            tvg.Color.fromString("ff004d") catch unreachable,
        }) ++
            builder.fillRectangles(1, .flat, 0) ++
            builder.rectangle(6, 6, 16, 36) ++
            builder.fillRectangles(1, .flat, 1) ++
            builder.rectangle(26, 6, 16, 16) ++
            builder.fillPath(11, .flat, 2) ++
            builder.point(26, 32) ++
            builder.path.horiz(32) ++
            builder.path.vert(26) ++
            builder.path.horiz(36) ++
            builder.path.vert(32) ++
            builder.path.horiz(42) ++
            builder.path.vert(36) ++
            builder.path.horiz(36) ++
            builder.path.vert(42) ++
            builder.path.horiz(32) ++
            builder.path.vert(36) ++
            builder.path.horiz(26) ++
            builder.end_of_document;
    };

    const shield = blk: {
        @setEvalBranchQuota(10_000);

        break :blk builder.header(24, 24) ++
            builder.colorTable(&[_]tvg.Color{
            tvg.Color.fromString("29adff") catch unreachable,
            tvg.Color.fromString("fff1e8") catch unreachable,
        }) ++
            builder.fillPath(5, .flat, 0) ++
            builder.point(12, 1) ++ // M 12 1
            builder.path.line(3, 5) ++ // L 3 5
            builder.path.vert(11) ++ // V 11
            builder.path.bezier(3, 16.55, 6.84, 21.74, 12, 23) ++ // C 3     16.55 6.84 21.74 12 23
            builder.path.bezier(17.16, 21.74, 21, 16.55, 21, 11) ++ // C 17.16 21.74 21   16.55 21 11
            builder.path.vert(5) ++ // V 5
            builder.fillPath(6, .flat, 1) ++
            builder.point(17.13, 17) ++ // M 12 1
            builder.path.bezier(15.92, 18.85, 14.11, 20.24, 12, 20.92) ++
            builder.path.bezier(9.89, 20.24, 8.08, 18.85, 6.87, 17) ++
            builder.path.bezier(6.53, 16.5, 6.24, 16, 6, 15.47) ++
            builder.path.bezier(6, 13.82, 8.71, 12.47, 12, 12.47) ++
            builder.path.bezier(15.29, 12.47, 18, 13.79, 18, 15.47) ++
            builder.path.bezier(17.76, 16, 17.47, 16.5, 17.13, 17) ++
            builder.fillPath(4, .flat, 1) ++
            builder.point(12, 5) ++
            builder.path.bezier(13.5, 5, 15, 6.2, 15, 8) ++
            builder.path.bezier(15, 9.5, 13.8, 10.998, 12, 11) ++
            builder.path.bezier(10.5, 11, 9, 9.8, 9, 8) ++
            builder.path.bezier(9, 6.4, 10.2, 5, 12, 5) ++
            builder.end_of_document;
    };
    // comptime {
    //     @compileLog(shield.len);
    // }
};

fn initColor(r: u8, g: u8, b: u8, a: u8) Color {
    return Color{ .r = r, .g = g, .b = b, .a = a };
}

fn renderWorkspace(self: Self, canvas: *Canvas, area: Rectangle, workspace: Workspace) void {
    self.renderTreeNode(canvas, area, workspace.window_tree.root);
}

fn renderTreeNode(self: Self, canvas: *Canvas, area: Rectangle, node: WindowTree.Node) void {
    switch (node) {
        .empty => {
            canvas.drawRectangle(
                area.x,
                area.y,
                area.width,
                area.height,
                if (area.contains(self.mouse_pos))
                    Color.rgb("255853")
                else
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
                        self.renderTreeNode(canvas, child_area, item);
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
                        self.renderTreeNode(canvas, child_area, item);
                    }
                },
            }
        },
    }
}

fn getMenuButtonRectangle(self: Self, index: usize) Rectangle {
    const smol_index = @intCast(u15, index);
    return Rectangle{
        .x = self.config.button_margin,
        .y = self.config.button_margin + (self.config.button_margin + self.config.button_size) * smol_index,
        .width = self.config.button_size,
        .height = self.config.button_size,
    };
}

const Button = struct {
    const Data = union(enum) {
        app_menu,
        workspace: Workspace,
        new_workspace,
    };

    data: Data,
    hovered: bool = false,
    highlight: f32 = 0.0,

    fn update(self: *Button, dt: f32) void {
        self.highlight = std.math.clamp(self.highlight + 5.0 * dt * if (self.hovered)
            @as(f32, 1.0)
        else
            @as(f32, -1.0), 0.0, 1.0);
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
