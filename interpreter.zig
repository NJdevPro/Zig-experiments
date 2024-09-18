const std = @import("std");

const Operation = enum {
    Add,
    Subtract,
    Multiply,
    LessThan,
    GreaterThan,
    Equals,
    Assign
};

const Statement = enum {
    For,
    If,
    Else,
    EndFor,
    EndIf
};

const Token = union(enum) {
    Number: f64,
    Variable: []const u8,
    Operation: Operation,
    Statement: Statement,
};

const Interpreter = struct {
    variables: std.StringHashMap(f64),
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator) Interpreter {
        return .{
            .variables = std.StringHashMap(f64).init(allocator),
            .allocator = allocator,
        };
    }

    fn deinit(self: *Interpreter) void {
        self.variables.deinit();
    }

    inline fn assignVariable(self: *Interpreter, name: []const u8, value: f64) !void {
        try self.variables.put(name, value);
    }

    inline fn getVariable(self: *Interpreter, name: []const u8) ?f64 {
        return self.variables.get(name);
    }

    fn findStatement(tokens: []const Token, start: usize, stmt: Statement, err: anyerror) !usize {
        var j = start;
        if (j == tokens.len) return start;
        while (j < tokens.len) : (j += 1) {
            if (tokens[j] == .Statement and tokens[j].Statement == stmt) break;
        }
        if (j == tokens.len and err != error.NoError) return err;
        return j;
    }

    fn evaluate(self: *Interpreter, tokens: []const Token) !f64 {
        var result: f64 = 0;
        var current_op: ?Operation = null;
        var i: usize = 0;

        while (i < tokens.len) : (i += 1) {
            switch (tokens[i]) {
                 .Number => |num| {
                    if (current_op) |op| {
                        if (op == .Assign) {
                            if (i > 1 and tokens[i - 2] == .Variable) {
                                try self.assignVariable(tokens[i - 2].Variable, num);
                                result = num;
                            } else {
                                return error.InvalidAssignment;
                            }
                        } else {
                            result = try Interpreter.applyOperation(result, num, op);
                        }
                        current_op = null;
                    } else {
                        result = num;
                    }
                },
                .Variable => |name| {
                    const value = self.getVariable(name) orelse return error.UndefinedVariable;
                    if (current_op) |op| {
                        if (op == .Assign) {
                            return error.InvalidAssignment;
                        }
                        result = try Interpreter.applyOperation(result, value, op);
                        current_op = null;
                    } else {
                        result = value;
                    }
                },
                .Operation => |op| {
                    current_op = op;
                },
                .Statement => |stmt| {
                    switch (stmt) {
                        .For => {
                            if (i + 5 >= tokens.len) return error.InvalidForLoop;
                            const loop_var = tokens[i + 1].Variable;
                            const start = try self.evaluate(tokens[i + 2 .. i + 3]);
                            const end = try self.evaluate(tokens[i + 3 .. i + 4]);
                            const loop_body_start = i + 4;
                            const loop_body_end = try findStatement(tokens, loop_body_start, .EndFor, error.MissingEndFor);

                            var j: f64 = start;
                            while (j <= end) : (j += 1) {
                                try self.assignVariable(loop_var, j);
                                result = try self.evaluate(tokens[loop_body_start..loop_body_end]);
                                try self.assignVariable(tokens[loop_body_start].Variable, result);
                            }

                            i = loop_body_end;
                        },
                        .If => {
                            if (i + 3 >= tokens.len) return error.InvalidIfStatement;
                            const condition = try self.evaluate(tokens[i + 1 .. i + 4]);
                            const then_body_start = i + 4;
                            var then_body_else = then_body_start;
                            var then_body_end = then_body_start;

                            then_body_else = try findStatement(tokens, then_body_start, .Else, error.NoError); // then.. else
                            then_body_end = try findStatement(tokens, then_body_else, .EndIf, error.MissingEndIf); // else.. endif
                            if (condition != 0) {
                                result = try self.evaluate(tokens[then_body_start..then_body_else]);
                            } else {
                                result = try self.evaluate(tokens[then_body_else..then_body_end]);
                            }
                            i = then_body_end;
                        },
                        else => {},
                    }
                },
            }
        }

        return result;
    }

    fn applyOperation(left: f64, right: f64, op: Operation) !f64 {
        return switch (op) {
            .Add => left + right,
            .Subtract => left - right,
            .Multiply => left * right,
            .LessThan => if (left <= right) 1 else 0,
            .GreaterThan => if (left > right) 1 else 0,
            .Equals => if (@abs(left - right) < 1.0e-8) 1 else 0,
            .Assign => right,
        };
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var interpreter = Interpreter.init(allocator);
    defer interpreter.deinit();

    // Assign variables
    try interpreter.assignVariable("x", 5);
    try interpreter.assignVariable("y", 3);
    std.debug.print("x  = {d}\n", .{5});
    std.debug.print("y  = {d}\n", .{3});

    // Example expressions
    const expr1 = [_]Token{ .{ .Variable = "x" }, .{ .Operation = .Add }, .{ .Number = 2 } };
    const expr2 = [_]Token{ .{ .Variable = "x" }, .{ .Operation = .Multiply }, .{ .Variable = "y" } };

    const result1 = try interpreter.evaluate(&expr1);
    const result2 = try interpreter.evaluate(&expr2);

    std.debug.print("x + 2 = {d}\n", .{result1});
    std.debug.print("x * y = {d}\n", .{result2});

    // Example: for loop to calculate sum of numbers from 1 to 5
    const for_loop_expr = [_]Token{
        .{ .Statement = .For },
        .{ .Variable = "i" },
        .{ .Number = 1 },
        .{ .Number = 5 },
        .{ .Variable = "sum" },
        .{ .Operation = .Add },
        .{ .Variable = "i" },
        .{ .Statement = .EndFor },
    };

    try interpreter.assignVariable("sum", 0);
    _ = try interpreter.evaluate(&for_loop_expr);
    const sum_result = interpreter.getVariable("sum").?;
    std.debug.print("Sum of numbers from 1 to 5: {d}\n", .{sum_result});

    // Example: if-then statement
    try interpreter.assignVariable("a", 11);
    try interpreter.assignVariable("b", -1);
    const if_expr = [_]Token{
        .{ .Statement = .If },
        .{ .Variable = "a" },
        .{ .Operation = .GreaterThan },
        .{ .Number = 10 },
        .{ .Variable = "b" },
        .{ .Operation = .Assign },
        .{ .Number = 1 },
        .{ .Statement = .EndIf },
    };
    _ = try interpreter.evaluate(&if_expr);
    const if_result = interpreter.getVariable("b").?;
    std.debug.print("If (a > 10) b = 1: {d}\n", .{if_result});

    // Example: if-then-else statement
    try interpreter.assignVariable("a", 9);
    try interpreter.assignVariable("b", -1);
    const if_else_expr = [_]Token{
        .{ .Statement = .If },
        .{ .Variable = "a" },
        .{ .Operation = .LessThan },
        .{ .Number = 10 },
        .{ .Variable = "b" },
        .{ .Operation = .Assign },
        .{ .Number = 42 },
        .{ .Statement = .Else },
        .{ .Variable = "b" },
        .{ .Operation = .Assign },
        .{ .Number = 0 },
        .{ .Statement = .EndIf },
    };

    _ = try interpreter.evaluate(&if_else_expr);
    std.debug.print("If (a <= 10) b = 42 else 0: {d}\n", .{interpreter.getVariable("b").?});
}
