const std = @import("std");
const fmt = std.fmt;
const math = std.math;
const base64 = std.base64.standard.Encoder;
const zigimg = @import("zigimg");

const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;
const Window = vaxis.Window;
const Placement = vaxis.Image.Placement;
const DrawOptions = vaxis.Image.DrawOptions;

pub const Image = @This();

const transmit_opener = "\x1b_Gf=32,i={d},s={d},v={d},m={d};";

pub const Source = union(enum) {
    path: []const u8,
    mem: []const u8,
};

pub const TransmitFormat = enum {
    rgb,
    rgba,
    png,
};

pub const TransmitMedium = enum {
    file,
    temp_file,
    shared_mem,
};

pub const CellSize = struct {
    rows: u16,
    cols: u16,
};

/// unique identifier for this image. This will be managed by the screen.
id: u32,

/// width in pixels
width: u16,
/// height in pixels
height: u16,

fn drawHandle(ptr: *anyopaque, ctx: vxfw.DrawContext) error{OutOfMemory}!vxfw.Surface {
    var self: *Image = @ptrCast(@alignCast(ptr));

    const size: vxfw.Size = .{
        .width = @max(1, ctx.min.width),
        .height = @max(1, ctx.min.height),
    };
    const surface = try vxfw.Surface.init(ctx.arena, self.widget(), size);
//    @memset(surface.buffer, .{.style = self.style});

    self.draw(surface, .{.scale = .contain}, ctx.cell_size) catch |err| {
        std.debug.print("failed to draw image: {any}\n", .{err});
    };

    return surface;
}

pub fn draw(self: Image, surface: vxfw.Surface, opts: DrawOptions, cell_size: vxfw.Size) !void {
    var p_opts = opts;
    switch (opts.scale) {
        .none => {},
        .fill => {
            p_opts.size = .{
                .rows = surface.size.height,
                .cols = surface.size.width,
            };
        },
        .fit,
        .contain,
        => contain: {
            // cell geometry
            const x_pix = cell_size.width; //surface.screen.width_pix;
            const y_pix = cell_size.height; //surface.screen.height_pix;
            const w = surface.size.width;
            const h = surface.size.height;

            const pix_per_col = try std.math.divCeil(usize, x_pix, w);
            const pix_per_row = try std.math.divCeil(usize, y_pix, h);

            const win_width_pix = pix_per_col * surface.size.width;
            const win_height_pix = pix_per_row * surface.size.height;

            const fit_x: bool = if (win_width_pix >= self.width) true else false;
            const fit_y: bool = if (win_height_pix >= self.height) true else false;

            // Does the image fit with no scaling?
            if (opts.scale == .contain and fit_x and fit_y) break :contain;

            // Does the image require vertical scaling?
            if (fit_x and !fit_y)
                p_opts.size = .{
                    .rows = surface.size.height,
                }

                    // Does the image require horizontal scaling?
            else if (!fit_x and fit_y)
                p_opts.size = .{
                    .cols = surface.size.width,
                }
            else if (!fit_x and !fit_y) {
                const diff_x = self.width - win_width_pix;
                const diff_y = self.height - win_height_pix;
                // The width difference is larger than the height difference.
                // Scale by width
                if (diff_x > diff_y)
                    p_opts.size = .{
                        .cols = surface.size.width,
                    }
                else
                    // The height difference is larger than the width difference.
                    // Scale by height
                    p_opts.size = .{
                        .rows = surface.size.height,
                    };
            } else {
                std.debug.assert(opts.scale == .fit);
                std.debug.assert(win_width_pix >= self.width);
                std.debug.assert(win_height_pix >= self.height);

                // Fits in both directions. Find the closer direction
                const diff_x = win_width_pix - self.width;
                const diff_y = win_height_pix - self.height;
                // The width is closer in dimension. Scale by that
                if (diff_x < diff_y)
                    p_opts.size = .{
                        .cols = surface.size.width,
                    }
                else
                    p_opts.size = .{
                        .rows = surface.size.height,
                    };
            }
        },
    }
    const p = Placement{
        .img_id = self.id,
        .options = p_opts,
    };
    surface.writeCell(0, 0, .{ .image = p });
}

/// the size of the image, in cells
pub fn cellSize(self: Image, win: Window) !CellSize {
    // cell geometry
    const x_pix = win.screen.width_pix;
    const y_pix = win.screen.height_pix;
    const w = win.screen.width;
    const h = win.screen.height;

    const pix_per_col = try std.math.divCeil(u16, x_pix, w);
    const pix_per_row = try std.math.divCeil(u16, y_pix, h);

    const cell_width = std.math.divCeil(u16, self.width, pix_per_col) catch 0;
    const cell_height = std.math.divCeil(u16, self.height, pix_per_row) catch 0;
    return .{
        .rows = cell_height,
        .cols = cell_width,
    };
}

pub fn widget(self: *Image) vxfw.Widget {
    return .{
        .userdata = self,
        .eventHandler = null,
        .drawFn = Image.drawHandle,
    };
}
