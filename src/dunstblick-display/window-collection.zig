const std = @import("std");
const sdl = @import("sdl2");
const log = std.log.scoped(.app);

const Window = @import("window.zig").Window;
const Session = @import("session.zig").Session;

pub const WindowCollection = struct {
    const Self = @This();
    const ListType = std.TailQueue(Window);

    window_list: ListType,
    allocator: *std.mem.Allocator,

    pub fn init(allocator: *std.mem.Allocator) Self {
        return Self{
            .window_list = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.window_list.len > 0) {
            log.info("Cleaning up {} unclosed windows...\n", .{
                self.window_list.len,
            });
            while (self.window_list.pop()) |node| {
                node.data.deinit();
                self.allocator.destroy(node);
            }
        }
        self.* = undefined;
    }

    pub fn addWindow(self: *Self, title: [:0]const u8, width: u32, height: u32, driver: *Session) !*ListType.Node {
        var context = try Window.init(title, width, height);
        errdefer context.deinit();

        const node = try self.allocator.create(ListType.Node);
        node.* = .{ .data = context };

        // Window.session is initialized with `null` to allow windows without
        // a connected session.
        // we have to initialize it *after* we created the UiNode, as
        // Window will take ownership of `driver` and would free it in case of
        // a error which we don't want.
        node.data.session = driver;

        self.window_list.append(node);

        return node;
    }

    pub fn find(self: *Self, window_id: u32) ?*ListType.Node {
        const win = sdl.Window.fromID(window_id) orelse return null;

        var it = self.window_list.first;
        return while (it) |c| : (it = c.next) {
            if (c.data.window.ptr == win.ptr)
                break c;
        } else null;
    }

    pub fn close(self: *Self, context: *ListType.Node) void {
        self.window_list.remove(context);
        context.data.deinit();
        self.allocator.destroy(context);
    }
};
