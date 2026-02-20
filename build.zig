const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Main executable
    const exe = b.addExecutable(.{
        .name = "pdf2md",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Dependencies
    const zml_dep = b.dependency("zml", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("zml", zml_dep.module("zml"));

    const zigimg_dep = b.dependency("zigimg", .{});
    exe.root_module.addImport("zigimg", zigimg_dep.module("zigimg"));

    // System libraries for PDF processing
    exe.linkSystemLibrary("poppler-glib");
    exe.linkSystemLibrary("gobject-2.0");
    exe.linkLibC();

    b.installArtifact(exe);

    // Run command
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Tests
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    // PDF Pipeline test executable
    const pdf_test_exe = b.addExecutable(.{
        .name = "test-pdf-pipeline",
        .root_source_file = b.path("scripts/test-pdf-pipeline.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(pdf_test_exe);

    const pdf_test_run = b.addRunArtifact(pdf_test_exe);
    pdf_test_run.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        pdf_test_run.addArgs(args);
    }
    const pdf_test_step = b.step("test-pdf", "Test PDF to image pipeline");
    pdf_test_step.dependOn(&pdf_test_run.step);

    // Model validator executable
    const validate_exe = b.addExecutable(.{
        .name = "validate-model",
        .root_source_file = b.path("scripts/validate-model.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(validate_exe);

    const validate_run = b.addRunArtifact(validate_exe);
    validate_run.step.dependOn(b.getInstallStep());
    const validate_step = b.step("validate-model", "Validate ONNX models");
    validate_step.dependOn(&validate_run.step);
}
