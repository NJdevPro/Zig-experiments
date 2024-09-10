const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const MatrixError = error{ InvalidArraySize, IncompatibleDimensions, OutOfMemory };

const ZMatrix = struct {
    allocator: *const Allocator,
    rows: usize = 0,
    cols: usize = 0,
    name: []const u8 = "",
    elem: []f32,

    fn init(alloc: *const Allocator, name: []const u8, rows: usize, cols: usize) !ZMatrix {
        const tmp = try alloc.alloc(f32, rows * cols);
        errdefer alloc.free(tmp);
        return .{
            .allocator = alloc,
            .rows = rows,
            .cols = cols,
            .name = name,
            .elem = tmp,
        };
    }

    pub fn initWithArray(alloc: *const Allocator, name: []const u8, rows: usize, cols: usize, arr: []const f32) !ZMatrix {
        if (arr.len != rows * cols) return error.InvalidArraySize;
        var matrix = try ZMatrix.init(alloc, name, rows, cols);
        errdefer matrix.deinit(alloc);
        @memcpy(matrix.elem, arr);
        return matrix;
    }

    pub fn deinit(self: ZMatrix) void {
        self.allocator.free(self.elem);
    }

    pub fn copy(self: ZMatrix, name: []const u8) !ZMatrix {
        return try ZMatrix.initWithArray(self.allocator, name, self.rows, self.cols, self.elem);
    }

    pub fn equals(self: *const ZMatrix, v: *const ZMatrix, eps: f32) bool {
        if (self.rows != v.rows or self.cols != v.cols) return false;
        for (self.elem, v.elem) |x, y| {
            if (@abs(x - y) > eps) return false;
        }
        return true;
    }

    pub fn print(self: *const ZMatrix) void {
        std.debug.print("Matrix {s}({d} x {d}):\n", .{ self.name, self.rows, self.cols });
        for (0..self.rows) |i| {
            for (0..self.cols) |j| {
                std.debug.print("{d:.1} ", .{self.elem[i * self.cols + j]});
            }
            std.debug.print("\n", .{});
        }
    }

    // extract a submatrix
    pub fn extract(self: *const ZMatrix, name: []const u8, beg_i: usize, beg_j: usize, end_i: usize, end_j: usize) !ZMatrix {
        if (beg_i > self.rows or end_i > self.rows or beg_j > self.cols or end_j > self.cols) return MatrixError.InvalidArraySize;
        const num_rows = end_i - beg_i + 1;
        const num_cols = end_j - beg_j + 1;
        const arr: []f32 = try self.allocator.alloc(f32, num_rows * num_cols);
        defer self.allocator.free(arr);
        var new_i: usize = 0;
        while (new_i < num_rows) : (new_i += 1) {
            const old_i = beg_i + new_i;
            const old_start = old_i * self.cols + beg_j;
            const new_start = new_i * num_cols;
            @memcpy(arr[new_start .. new_start + num_cols], self.elem[old_start .. old_start + num_cols]);
        }
        return ZMatrix.initWithArray(self.allocator, name, num_rows, num_cols, arr);
    }

    pub fn add(self: *ZMatrix, v: *const ZMatrix) !*ZMatrix {
        if (self.rows != v.rows or self.cols != v.cols) return MatrixError.IncompatibleDimensions;
        for (self.elem, v.elem) |*x, y| x.* += y;
        return self;
    }

    pub fn sub(self: *ZMatrix, v: *const ZMatrix) !*ZMatrix {
        if (self.rows != v.rows or self.cols != v.cols) return MatrixError.IncompatibleDimensions;
        for (self.elem, v.elem) |*x, y| x.* -= y;
        return self;
    }

    pub fn dot(self: *ZMatrix, name: []const u8, v: *const ZMatrix) !ZMatrix {
        if (self.cols != v.rows) return MatrixError.IncompatibleDimensions;
        var w = try ZMatrix.init(self.allocator, name, self.rows, v.cols);
        errdefer w.deinit(.allocator);

        for (0..self.rows) |i| {
            for (0..v.cols) |j| {
                var sum: f32 = 0.0;
                for (0..self.cols) |k| {
                    sum += self.elem[i * self.cols + k] * v.elem[k * v.cols + j];
                }
                w.elem[i * w.cols + j] = sum;
            }
        }
        return w;
    }

    pub fn transpose(self: *ZMatrix, name: []const u8) !ZMatrix {
        var t = try ZMatrix.init(self.allocator, name, self.cols, self.rows);
        errdefer t.deinit();
        for (0..self.rows) |i|
            for (0..self.cols) |j| {
                t.elem[j * self.rows + i] = self.elem[i * self.cols + j];
            };
        return t;
    }
};

const expect = std.testing.expect;

test "add 2 matrices" {
    var alloc = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = alloc.allocator();

    var a = try ZMatrix.initWithArray(&gpa, "A", 2, 3, &.{ 1.0, 2.0, 3.0, 4.0, 5.0, 6.0 });
    const b = try ZMatrix.initWithArray(&gpa, "B", 2, 3, &.{ 6.0, 5.0, 4.0, 3.0, 2.0, 1.0 });
    defer a.deinit();
    defer b.deinit();
    a.print();
    b.print();

    _ = try a.add(&b);
    a.print();
    const expected = try ZMatrix.initWithArray(&gpa, "A", 2, 3, &.{ 7.0, 7.0, 7.0, 7.0, 7.0, 7.0 });
    try expect(a.equals(&expected, 1e-6));
}

test "sub 2 matrices" {
    var alloc = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = alloc.allocator();

    var a = try ZMatrix.initWithArray(&gpa, "A", 2, 3, &.{ 1.0, 2.0, 3.0, 4.0, 5.0, 6.0 });
    const b = try a.copy("B");
    defer a.deinit();
    defer b.deinit();
    a.print();
    b.print();

    _ = try a.sub(&b);
    a.print();
    const expected = try ZMatrix.initWithArray(&gpa, "A", 2, 3, &.{ 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 });
    try expect(a.equals(&expected, 1e-6));
}

test "dot 2 matrices" {
    var alloc = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = alloc.allocator();

    var a = try ZMatrix.initWithArray(&gpa, "A", 2, 3, &.{ 1.0, 2.0, 3.0, 4.0, 5.0, 6.0 });
    const b = try ZMatrix.initWithArray(&gpa, "B", 3, 2, &.{ 1.0, 2.0, 3.0, 4.0, 5.0, 6.0 });
    defer a.deinit();
    defer b.deinit();
    a.print();
    b.print();

    const c = try a.dot("A.B", &b);
    defer c.deinit();
    c.print();
    const expected = try ZMatrix.initWithArray(&gpa, "Expected", 2, 2, &.{ 22.0, 28.0, 49.0, 64.0 });
    try expect(c.equals(&expected, 1e-6));
}

test "transpose matrix" {
    var alloc = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = alloc.allocator();

    var a = try ZMatrix.initWithArray(&gpa, "A", 2, 3, &.{ 1.0, 2.0, 3.0, 4.0, 5.0, 6.0 });
    defer a.deinit();
    a.print();

    const t = try a.transpose("t(A)");
    defer t.deinit();
    t.print();
    const expected = try ZMatrix.initWithArray(&gpa, "Expected", 3, 2, &.{ 1.0, 4.0, 2.0, 5.0, 3.0, 6.0 });
    try expect(t.equals(&expected, 1e-6));
}

test "extract submatrices" {
    var alloc = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = alloc.allocator();

    var a = try ZMatrix.initWithArray(&gpa, "A", 3, 3, &.{ 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0 });
    defer a.deinit();
    a.print();

    var b = try a.extract("row 1", 0, 0, 0, 2);
    b.print();
    var c = try a.extract("row 3", 2, 0, 2, 2);
    c.print();
    var d = try a.extract("col 1", 0, 0, 2, 0);
    d.print();
    var e = try a.extract("col 3", 0, 2, 2, 2);
    e.print();
    var f = try a.extract("submatrix", 1, 1, 2, 2);
    f.print();
}
