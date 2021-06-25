const std = @import("std");
const logger = std.log.scoped(.dunstblick_sdk);

const Pkg = std.build.Pkg;
const Step = std.build.Step;
const FileSource = std.build.FileSource;
const GeneratedFile = std.build.GeneratedFile;

const protocol = @import("src/dunstblick-protocol/protocol.zig");

const Database = @import("src/dunstblick-compiler/Database.zig");

pub const Sdk = @This();

builder: *std.build.Builder,

// build tools
compiler: *std.build.LibExeObjStep,

pub fn init(b: *std.build.Builder) *Sdk {
    const sdk = b.allocator.create(Sdk) catch unreachable;
    sdk.* = Sdk{
        .builder = b,
        .compiler = b.addExecutable("layout-compiler", sdkRoot() ++ "/src/dunstblick-compiler/main.zig"),
    };

    sdk.compiler.addPackage(pkgs.args);
    sdk.compiler.addPackage(pkgs.dunstblick_protocol);

    return sdk;
}

pub fn getAppPackage(sdk: *const Sdk, name: []const u8) Pkg {
    return sdk.builder.dupePkg(Pkg{
        .name = sdk.builder.dupe(name),
        .path = FileSource{ .path = sdkRoot() ++ "/src/dunstblick-app/dunstblick.zig" },
        .dependencies = &[_]std.build.Pkg{
            pkgs.network,
            pkgs.dunstblick_protocol,
        },
    });
}

pub fn getCompilerPackage(sdk: *const Sdk, name: []const u8) Pkg {
    return sdk.builder.dupePkg(Pkg{
        .name = sdk.builder.dupe(name),
        .path = FileSource{ .path = sdkRoot() ++ "/src/dunstblick-compiler/package.zig" },
        .dependencies = &[_]std.build.Pkg{
            pkgs.dunstblick_protocol,
        },
    });
}

pub fn addCompileLayout(sdk: *const Sdk, file: FileSource, config: ?FileSource, update_config: bool) *CompileLayoutStep {
    const step = sdk.builder.allocator.create(CompileLayoutStep) catch unreachable;
    step.* = CompileLayoutStep{
        .sdk = sdk,
        .step = Step.init(
            .custom,
            "compile layout",
            sdk.builder.allocator,
            CompileLayoutStep.make,
        ),
        .input_file = file,
        .config_file = config,
        .update_config = update_config,
        .output_file = GeneratedFile{ .step = &step.step },
    };
    step.step.dependOn(&sdk.compiler.step); // we want to run the compiler
    file.addStepDependencies(&step.step); // and we need our input file to be done

    return step;
}

pub const CompileLayoutStep = struct {
    const Self = @This();

    pub const FileType = enum { binary, header };

    sdk: *const Sdk,
    step: Step,
    input_file: FileSource,
    config_file: ?FileSource,
    update_config: bool,
    output_file: GeneratedFile,
    file_type: FileType = .binary,

    pub fn getOutputFile(self: *Self) FileSource {
        return FileSource{ .generated = &self.output_file };
    }

    fn make(step: *Step) anyerror!void {
        const self = @fieldParentPtr(Self, "step", step);

        const exe = self.sdk.compiler.getOutputSource().getPath(self.sdk.builder);
        const input_file = self.input_file.getPath(self.sdk.builder);

        var cache_hash = CacheBuilder.init(self.sdk.builder, "dunstblick");
        try cache_hash.addFile(self.input_file);

        const root = try cache_hash.createAndGetPath();

        self.output_file.path = try std.fs.path.join(self.sdk.builder.allocator, &[_][]const u8{
            root,
            std.fs.path.basename(input_file),
        });

        var argv = std.ArrayList([]const u8).init(self.sdk.builder.allocator);
        defer argv.deinit();

        try argv.appendSlice(&[_][]const u8{
            exe,
            input_file,
            "--output",
            self.output_file.path.?,
            "--file-type",
            switch (self.file_type) {
                .binary => "binary",
                .header => "header",
            },
        });

        if (self.config_file) |file| {
            try argv.appendSlice(&[_][]const u8{
                "--config",
                file.getPath(self.sdk.builder),
            });
        }
        if (self.update_config) {
            try argv.append("--update-config");
        }

        _ = try self.sdk.builder.execFromStep(argv.items, step);
    }
};

pub fn addCompileBitmap(sdk: *const Sdk, input_file: FileSource) *CompileImageStep {
    const step = sdk.builder.allocator.create(CompileImageStep) catch unreachable;
    step.* = CompileImageStep{
        .sdk = sdk,
        .step = Step.init(
            .custom,
            "compile bitmap",
            sdk.builder.allocator,
            CompileImageStep.make,
        ),
        .input_file = input_file,
        .output_file = GeneratedFile{ .step = &step.step },
    };
    input_file.addStepDependencies(&step.step); // and we need our input file to be done
    return step;
}

pub const CompileImageStep = struct {
    const Self = @This();

    sdk: *const Sdk,
    step: Step,
    input_file: FileSource,
    output_file: GeneratedFile,

    pub fn getOutputFile(self: *Self) FileSource {
        return FileSource{ .generated = &self.output_file };
    }

    fn make(step: *Step) anyerror!void {
        const self = @fieldParentPtr(Self, "step", step);

        const src_path = self.input_file.getPath(self.sdk.builder);

        const ext = std.fs.path.extension(src_path);
        if (!std.mem.eql(u8, ext, ".png")) {
            logger.err("Cannot compile bitmap: Unsupported extension {s} on file {s}", .{
                ext, src_path,
            });
            return error.InvalidExtension;
        }

        // TODO: Convert input files to png if necessary

        // TODO: Verify for PNG signature!

        self.output_file.path = src_path;
    }
};

pub fn addBundleResources(sdk: *const Sdk) *BundleResourcesStep {
    const prepare_step = sdk.builder.allocator.create(PrepareConfigFile) catch unreachable;

    const step = sdk.builder.allocator.create(BundleResourcesStep) catch unreachable;
    step.* = BundleResourcesStep{
        .sdk = sdk,
        .step = Step.init(
            .custom,
            "bundle resources",
            sdk.builder.allocator,
            BundleResourcesStep.make,
        ),
        .output_file = GeneratedFile{ .step = &step.step },
        .prepare_step = prepare_step,

        .resources = std.StringHashMap(BundleResourcesStep.Resource).init(sdk.builder.allocator),
        .properties = std.StringHashMap(void).init(sdk.builder.allocator),
        .objects = std.StringHashMap(void).init(sdk.builder.allocator),
        .events = std.StringHashMap(void).init(sdk.builder.allocator),
        .widgets = std.StringHashMap(void).init(sdk.builder.allocator),
    };

    prepare_step.* = .{
        .resource_step = step,
        .step = Step.init(
            .custom,
            "prepare bundle resources",
            sdk.builder.allocator,
            PrepareConfigFile.make,
        ),
        .config_json = GeneratedFile{ .step = &prepare_step.step },
    };

    step.step.dependOn(&prepare_step.step);

    return step;
}

const PrepareConfigFile = struct {
    const Self = @This();

    resource_step: *BundleResourcesStep,
    step: Step,
    config_json: GeneratedFile,

    fn getConfigJson(self: *Self) FileSource {
        return FileSource{ .generated = &self.config_json };
    }

    fn make(step: *Step) anyerror!void {
        const self = @fieldParentPtr(Self, "step", step);

        const allocator = self.resource_step.sdk.builder.allocator;

        var db = Database.init(allocator, true);
        defer db.deinit();

        {
            var it = self.resource_step.resources.iterator();
            while (it.next()) |entry| {
                _ = try db.get(.resource, entry.key_ptr.*);
            }
        }
        {
            var it = self.resource_step.events.iterator();
            while (it.next()) |entry| {
                _ = try db.get(.event, entry.key_ptr.*);
            }
        }
        {
            var it = self.resource_step.objects.iterator();
            while (it.next()) |entry| {
                _ = try db.get(.object, entry.key_ptr.*);
            }
        }
        {
            var it = self.resource_step.widgets.iterator();
            while (it.next()) |entry| {
                _ = try db.get(.widget, entry.key_ptr.*);
            }
        }
        {
            var it = self.resource_step.properties.iterator();
            while (it.next()) |entry| {
                _ = try db.get(.property, entry.key_ptr.*);
            }
        }

        var json = std.ArrayList(u8).init(allocator);
        defer json.deinit();

        try db.toJson(json.writer());

        var cache = CacheBuilder.init(self.resource_step.sdk.builder, "dunstblick");
        cache.addBytes(json.items);

        self.config_json.path = try std.fs.path.join(allocator, &[_][]const u8{
            try cache.createAndGetPath(),
            "config.json",
        });

        // Just blank the file, we do everything via updating
        try std.fs.cwd().writeFile(self.config_json.path.?, json.items);
    }
};

pub const BundleResourcesStep = struct {
    const Self = @This();

    const Resource = struct {
        kind: protocol.ResourceKind,
        data: ?FileSource,
    };

    sdk: *const Sdk,
    step: Step,
    output_file: GeneratedFile,

    resources: std.StringHashMap(Resource),
    properties: std.StringHashMap(void),
    objects: std.StringHashMap(void),
    events: std.StringHashMap(void),
    widgets: std.StringHashMap(void),

    prepare_step: *PrepareConfigFile,

    pub fn addLayout(self: *Self, name: []const u8, file: FileSource) void {
        const step = self.sdk.addCompileLayout(file, self.prepare_step.getConfigJson(), true);

        self.resources.putNoClobber(
            self.sdk.builder.dupe(name),
            Resource{ .kind = .layout, .data = step.getOutputFile() },
        ) catch unreachable;

        step.step.dependOn(&self.prepare_step.step);
        self.step.dependOn(&step.step);
    }

    pub fn addBitmap(self: *Self, name: []const u8, file: FileSource) void {
        const step = self.sdk.addCompileBitmap(file);

        self.resources.putNoClobber(
            self.sdk.builder.dupe(name),
            Resource{ .kind = .bitmap, .data = step.getOutputFile() },
        ) catch unreachable;

        self.step.dependOn(&step.step);
    }

    pub fn addRuntimeResource(self: *Self, name: []const u8, kind: protocol.ResourceKind) void {
        self.resources.putNoClobber(
            self.sdk.builder.dupe(name),
            Resource{ .kind = kind, .data = null },
        ) catch unreachable;
    }

    pub fn addProperty(self: *Self, name: []const u8) void {
        self.properties.putNoClobber(self.sdk.builder.dupe(name), {}) catch unreachable;
    }

    pub fn addObject(self: *Self, name: []const u8) void {
        self.objects.putNoClobber(self.sdk.builder.dupe(name), {}) catch unreachable;
    }

    pub fn addEvent(self: *Self, name: []const u8) void {
        self.events.putNoClobber(self.sdk.builder.dupe(name), {}) catch unreachable;
    }

    pub fn addWidget(self: *Self, name: []const u8) void {
        self.widgets.putNoClobber(self.sdk.builder.dupe(name), {}) catch unreachable;
    }

    pub fn getPackage(self: *Self, name: []const u8) std.build.Pkg {
        return std.build.Pkg{
            .name = name,
            .path = .{ .generated = &self.output_file },
            .dependencies = &[_]Pkg{
                pkgs.dunstblick_protocol,
            },
        };
    }

    fn make(step: *Step) anyerror!void {
        const self = @fieldParentPtr(Self, "step", step);

        const allocator = self.sdk.builder.allocator;

        var source = try std.fs.cwd().readFileAlloc(allocator, self.prepare_step.config_json.path.?, 1 << 20); // 1 MB should be enough
        defer allocator.free(source);

        var db = try Database.fromJson(allocator, true, source);
        defer db.deinit();

        {
            var iter = self.resources.iterator();
            while (iter.next()) |entry| {
                _ = try db.get(.resource, entry.key_ptr.*);
            }
        }

        // try db.toJson(std.io.getStdOut().writer());

        var output_file = std.ArrayList(u8).init(allocator);
        defer output_file.deinit();

        {
            var writer = output_file.writer();

            try writer.writeAll(
                \\const protocol = @import("dunstblick-protocol");
                \\
                \\pub const Resource = struct {
                \\    data: []const u8,
                \\    id: protocol.ResourceID,
                \\    kind: protocol.ResourceKind,
                \\};
                \\pub const RuntimeResource = struct {
                \\    id: protocol.ResourceID,
                \\    kind: protocol.ResourceKind,
                \\};
                \\
                \\pub const resources = struct {
                \\
            );

            {
                var bad = false;
                var it = db.iterator(.resource);
                while (it.next()) |entry| {
                    const resource = self.resources.get(entry.key_ptr.*) orelse {
                        logger.err("Resource '{s}' was required by a layout, but is not declared in the build script.", .{entry.key_ptr.*});
                        bad = true;
                        continue;
                    };

                    // TODO: Add definition of resource kind, so we know in the application
                    // what kind of resource we have :)

                    if (resource.data) |file_source| {
                        const path = try std.fs.path.resolve(allocator, &[_][]const u8{file_source.getPath(self.sdk.builder)});
                        try writer.print("    pub const @\"{s}\" = Resource{{ .id = @intToEnum(protocol.ResourceID, {}), .kind = protocol.ResourceKind.{s}, .data = @embedFile(\"{s}\") }};\n", .{
                            entry.key_ptr.*,
                            entry.value_ptr.*,
                            @tagName(resource.kind),
                            path,
                        });
                    } else {
                        try writer.print("    pub const @\"{s}\" = RuntimeResource{{ .id = @intToEnum(protocol.ResourceID, {}), .kind = protocol.ResourceKind.{s} }};\n", .{
                            entry.key_ptr.*,
                            entry.value_ptr.*,
                            @tagName(resource.kind),
                        });
                    }
                }

                if (bad)
                    return error.MissingResource;
            }

            const IDSetup = struct {
                key: Database.Entry,
                group: []const u8,
                type: []const u8,
            };

            for ([_]IDSetup{
                IDSetup{ .key = .event, .group = "events", .type = "EventID" },
                IDSetup{ .key = .property, .group = "properties", .type = "PropertyName" },
                IDSetup{ .key = .object, .group = "objects", .type = "ObjectID" },
                IDSetup{ .key = .widget, .group = "widgets", .type = "WidgetName" },
            }) |setup| {
                try writer.print("}};\n\npub const {s} = struct {{\n", .{
                    setup.group,
                });

                var it = db.iterator(setup.key);
                while (it.next()) |entry| {
                    try writer.print("    pub const @\"{s}\" = @intToEnum(protocol.{s}, {});\n", .{
                        entry.key_ptr.*,
                        setup.type,
                        entry.value_ptr.*,
                    });
                }
            }

            try writer.writeAll(
                \\};
                \\
            );
        }

        var cache = CacheBuilder.init(self.sdk.builder, "dunstblick");
        cache.addBytes(output_file.items);

        var root_path = try cache.createAndGetPath();

        self.output_file.path = try std.fs.path.join(allocator, &[_][]const u8{
            root_path,
            "package.zig",
        });

        try std.fs.cwd().writeFile(self.output_file.path.?, output_file.items);
    }
};

fn sdkRoot() []const u8 {
    return std.fs.path.dirname(@src().file) orelse ".";
}

const pkgs = struct {
    const network = std.build.Pkg{
        .name = "network",
        .path = FileSource{ .path = sdkRoot() ++ "/lib/zig-network/network.zig" },
    };

    const dunstblick_protocol = std.build.Pkg{
        .name = "dunstblick-protocol",
        .path = FileSource{ .path = sdkRoot() ++ "/src/dunstblick-protocol/protocol.zig" },
        .dependencies = &[_]std.build.Pkg{
            charm,
        },
    };

    const args = std.build.Pkg{
        .name = "args",
        .path = FileSource{ .path = sdkRoot() ++ "/lib/zig-args/args.zig" },
    };

    const charm = std.build.Pkg{
        .name = "charm",
        .path = .{ .path = sdkRoot() ++ "/lib/zig-charm/src/main.zig" },
    };
};

const CacheBuilder = struct {
    const Self = @This();

    builder: *std.build.Builder,
    hasher: std.crypto.hash.Sha1,
    subdir: ?[]const u8,

    pub fn init(builder: *std.build.Builder, subdir: ?[]const u8) Self {
        return Self{
            .builder = builder,
            .hasher = std.crypto.hash.Sha1.init(.{}),
            .subdir = if (subdir) |s|
                builder.dupe(s)
            else
                null,
        };
    }

    pub fn addBytes(self: *Self, bytes: []const u8) void {
        self.hasher.update(bytes);
    }

    pub fn addFile(self: *Self, file: std.build.FileSource) !void {
        const path = file.getPath(self.builder);

        const data = try std.fs.cwd().readFileAlloc(self.builder.allocator, path, 1 << 32); // 4 GB
        defer self.builder.allocator.free(data);

        self.addBytes(data);
    }

    fn createPath(self: *Self) ![]const u8 {
        var hash: [20]u8 = undefined;
        self.hasher.final(&hash);

        const path = if (self.subdir) |subdir|
            try std.fmt.allocPrint(
                self.builder.allocator,
                "{s}/{s}/o/{}",
                .{
                    self.builder.cache_root,
                    subdir,
                    std.fmt.fmtSliceHexLower(&hash),
                },
            )
        else
            try std.fmt.allocPrint(
                self.builder.allocator,
                "{s}/o/{}",
                .{
                    self.builder.cache_root,
                    std.fmt.fmtSliceHexLower(&hash),
                },
            );

        return path;
    }

    pub const DirAndPath = struct {
        dir: std.fs.Dir,
        path: []const u8,
    };
    pub fn createAndGetDir(self: *Self) !DirAndPath {
        const path = try self.createPath();
        return DirAndPath{
            .path = path,
            .dir = try std.fs.cwd().makeOpenPath(path, .{}),
        };
    }

    pub fn createAndGetPath(self: *Self) ![]const u8 {
        const path = try self.createPath();
        try std.fs.cwd().makePath(path);
        return path;
    }
};
