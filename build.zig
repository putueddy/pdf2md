const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ONNX Runtime path configuration
    const onnx_path_opt = b.option([]const u8, "onnx-path", "Path to ONNX Runtime installation (default: /opt/homebrew/opt/onnxruntime)");
    const onnx_path = onnx_path_opt orelse "/opt/homebrew/opt/onnxruntime";
    const onnx_include = b.pathJoin(&.{ onnx_path, "include" });
    const onnx_lib = b.pathJoin(&.{ onnx_path, "lib" });

    // Create the main module
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/pdf2md.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Main executable
    const exe = b.addExecutable(.{
        .name = "pdf2md",
        .root_module = exe_mod,
    });

    // Add C wrapper object file
    const ort_wrapper_o = b.path("src/ml/ort_wrapper.o");
    exe.addObjectFile(ort_wrapper_o);

    // ONNX Runtime
    exe.addIncludePath(.{ .cwd_relative = onnx_include });
    exe.addLibraryPath(.{ .cwd_relative = onnx_lib });
    exe.linkSystemLibrary("onnxruntime");
    exe.linkLibC();

    // System libraries for PDF processing
    exe.linkSystemLibrary("poppler-glib");

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
    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/pdf2md.zig"),
        .target = target,
        .optimize = optimize,
    });
    const unit_tests = b.addTest(.{
        .root_module = test_mod,
    });
    unit_tests.addObjectFile(ort_wrapper_o);
    unit_tests.addIncludePath(.{ .cwd_relative = onnx_include });
    unit_tests.addLibraryPath(.{ .cwd_relative = onnx_lib });
    unit_tests.linkSystemLibrary("onnxruntime");
    unit_tests.linkLibC();

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    // PDF Pipeline test executable
    const pdf_test_mod = b.createModule(.{
        .root_source_file = b.path("scripts/test-pdf-pipeline.zig"),
        .target = target,
        .optimize = optimize,
    });
    const pdf_test_compile = b.addExecutable(.{
        .name = "test-pdf-pipeline",
        .root_module = pdf_test_mod,
    });
    pdf_test_compile.addObjectFile(ort_wrapper_o);
    pdf_test_compile.addIncludePath(.{ .cwd_relative = onnx_include });
    pdf_test_compile.addLibraryPath(.{ .cwd_relative = onnx_lib });
    pdf_test_compile.linkSystemLibrary("onnxruntime");
    pdf_test_compile.linkLibC();
    b.installArtifact(pdf_test_compile);

    const pdf_test_run = b.addRunArtifact(pdf_test_compile);
    pdf_test_run.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        pdf_test_run.addArgs(args);
    }
    const pdf_test_step = b.step("test-pdf", "Test PDF to image pipeline");
    pdf_test_step.dependOn(&pdf_test_run.step);

    // Model validator executable
    const validate_mod = b.createModule(.{
        .root_source_file = b.path("scripts/validate-model.zig"),
        .target = target,
        .optimize = optimize,
    });
    const validate_exe = b.addExecutable(.{
        .name = "validate-model",
        .root_module = validate_mod,
    });
    validate_exe.addObjectFile(ort_wrapper_o);
    validate_exe.addIncludePath(.{ .cwd_relative = onnx_include });
    validate_exe.addLibraryPath(.{ .cwd_relative = onnx_lib });
    validate_exe.linkSystemLibrary("onnxruntime");
    validate_exe.linkLibC();
    b.installArtifact(validate_exe);

    const validate_run = b.addRunArtifact(validate_exe);
    validate_run.step.dependOn(b.getInstallStep());
    const validate_step = b.step("validate-model", "Validate ONNX models");
    validate_step.dependOn(&validate_run.step);

    // GPU/ONNX info step
    const info_step = b.step("info", "Show build configuration");
    const info_cmd = b.addSystemCommand(&.{
        "echo",
        "Build Configuration:",
        "",
        "ONNX Runtime Path:",
        onnx_path,
        "Include:",
        onnx_include,
        "Lib:",
        onnx_lib,
        "",
        "To use custom ONNX Runtime (e.g., with CoreML):",
        "  zig build -Donnx-path=/path/to/onnxruntime",
        "",
        "To build ONNX Runtime with CoreML support:",
        "  ./scripts/build-onnx-coreml.sh",
    });
    info_step.dependOn(&info_cmd.step);
}
