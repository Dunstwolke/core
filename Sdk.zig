const std = @import("std");

const Step = std.build.Step;
const FileSource = std.build.FileSource;
const GeneratedFile = std.build.GeneratedFile;

pub const Sdk = @This();

fn sdkRoot() []const u8 {
    return std.fs.path.dirname(@src().file) orelse ".";
}

builder: *std.build.Builder,

pub fn init(b: *std.build.Builder) Sdk {
    return Sdk{
        .builder = b,
    };
}

pub fn addCompileLayout(sdk: Sdk) *CompileLayoutStep {
    @panic("not implemented!");
}

pub const CompileLayoutStep = struct {
    step: Step,

    pub fn getOutputFile(self: *CompileImageStep) FileSource {
        unreachable;
    }

    fn make(step: *Step) anyerror!void {
        const self = @fieldParentPtr(BundleResourcesStep, "step", step);

        return error.NotImplemented;
    }
};

pub fn addCompileImage(sdk: Sdk, image_path: []const u8) *CompileImageStep {
    @panic("not implemented!");
}

pub const CompileImageStep = struct {
    step: Step,

    pub fn getOutputFile(self: *CompileImageStep) FileSource {
        unreachable;
    }

    fn make(step: *Step) anyerror!void {
        const self = @fieldParentPtr(BundleResourcesStep, "step", step);

        return error.NotImplemented;
    }
};

pub fn addBundleResources(sdk: *Sdk) *BundleResourcesStep {
    const step = sdk.builder.allocator.create(BundleResourcesStep) catch unreachable;
    step.* = BundleResourcesStep{
        .sdk = sdk,
        .step = Step.init(
            .custom,
            "bundle resources",
            sdk.builder.allocator,
            BundleResourcesStep.make,
        ),
        .output_file = undefined,
    };
    step.output_file = GeneratedFile{ .step = &step.step };

    return step;
}

pub const BundleResourcesStep = struct {
    sdk: *Sdk,
    step: Step,
    output_file: GeneratedFile,
    // resources: std.StringHashMap(

    pub fn addLayout(self: *BundleResourcesStep, name: []const u8, file: []const u8) void {
        //
    }

    pub fn getPackage(self: *BundleResourcesStep, name: []const u8) std.build.Pkg {
        return std.build.Pkg{
            .name = name,
            .path = .{ .generated = &self.output_file },
        };
    }

    fn make(step: *Step) anyerror!void {
        const self = @fieldParentPtr(BundleResourcesStep, "step", step);

        return error.NotImplemented;
    }
};
