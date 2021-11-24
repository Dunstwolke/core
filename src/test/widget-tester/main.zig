const std = @import("std");
const dunstblick = @import("dunstblick");
const app_data = @import("app-data");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var app = try dunstblick.Application.open(
        &gpa.allocator,
        "Widget Tester",
        "A overview over all Dunstblick widgets",
        app_data.resources.app_icon.data,
    );
    defer app.close();

    inline for (std.meta.declarations(app_data.resources)) |decl| {
        const res = @field(app_data.resources, decl.name);
        try app.addResource(res.id, res.kind, res.data);
    }

    while (true) {
        const event = (try app.pollEvent(null)) orelse break;
        switch (event.*) {
            .connected => |event_args| {
                const con = event_args.connection;
                try con.setView(app_data.resources.index.id);

                // var root_obj = try con.beginChangeObject(data.objects.root);
                // errdefer root_obj.cancel();

                // try root_obj.setProperty(data.properties.@"current-song", .{
                //     .string = dunstblick.String.readOnly("Current Song"),
                // });

                // try root_obj.setProperty(data.properties.@"current-artist", .{
                //     .string = dunstblick.String.readOnly("Current Artist"),
                // });

                // try root_obj.setProperty(data.properties.@"current-albumart", .{
                //     .resource = data.resources.album_placeholder.id,
                // });

                // try root_obj.commit();

                // try con.setRoot(data.objects.root);
            },
            .disconnected => {
                //
            },
            .widget_event => |event_args| {
                std.log.info("User triggerd {}", .{event_args.event});
            },
            .property_changed => {
                //
            },
        }
    }
}
