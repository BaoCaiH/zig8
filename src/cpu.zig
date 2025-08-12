//! By convention, root.zig is the root source file when making a library. If
//! you are making an executable, the convention is to delete this file and
//! start with main.zig instead.
const std = @import("std");
const testing = std.testing;
const FONTSET_SIZE = 80;
const FONTSET_START_ADDRESS = 0x50;
const START_ADDRESS = 0x200;
pub const VIDEO_WIDTH = 64;
pub const VIDEO_HEIGHT = 32;

pub const Chip8 = struct {
    // current opcode
    opcode: u16,
    // chip8 memory
    memory: [4096]u8,
    // cpu registry
    V: [16]u8,

    // index register
    I: u16,

    // program counter
    pc: u16,
    // 0x000-0x1FF - Chip 8 interpreter (contains font set in emu)
    // 0x050-0x0A0 - Used for the built in 4x5 pixel font set (0-F)
    // 0x200-0xFFF - Program ROM and work RAM

    // graphic screen size
    gfx: [VIDEO_WIDTH * VIDEO_HEIGHT]u8,

    // timers
    delay_timer: u8,
    sound_timer: u8,

    // stack and pointer
    stack: [16]u16,
    sp: u16,

    // keypad
    key: [16]u8,

    // draw flag to not draw every cycle
    draw_flag: bool,

    pub fn initialise() Chip8 {
        const chip8_fontset = [80]u8{
            0xF0, 0x90, 0x90, 0x90, 0xF0, // 0
            0x20, 0x60, 0x20, 0x20, 0x70, // 1
            0xF0, 0x10, 0xF0, 0x80, 0xF0, // 2
            0xF0, 0x10, 0xF0, 0x10, 0xF0, // 3
            0x90, 0x90, 0xF0, 0x10, 0x10, // 4
            0xF0, 0x80, 0xF0, 0x10, 0xF0, // 5
            0xF0, 0x80, 0xF0, 0x90, 0xF0, // 6
            0xF0, 0x10, 0x20, 0x40, 0x40, // 7
            0xF0, 0x90, 0xF0, 0x90, 0xF0, // 8
            0xF0, 0x90, 0xF0, 0x10, 0xF0, // 9
            0xF0, 0x90, 0xF0, 0x90, 0x90, // A
            0xE0, 0x90, 0xE0, 0x90, 0xE0, // B
            0xF0, 0x80, 0x80, 0x80, 0xF0, // C
            0xE0, 0x90, 0x90, 0x90, 0xE0, // D
            0xF0, 0x80, 0xF0, 0x80, 0xF0, // E
            0xF0, 0x80, 0xF0, 0x80, 0x80, // F
        };

        var chip8 = Chip8{
            .opcode = 0,
            .memory = undefined,
            .V = undefined,
            .I = 0,
            .pc = START_ADDRESS,
            .gfx = undefined,
            .delay_timer = 0,
            .sound_timer = 0,
            .stack = undefined,
            .sp = 0,
            .key = undefined,
            .draw_flag = false,
        };

        for (0..FONTSET_SIZE, chip8_fontset) |i, elem| {
            chip8.memory[i + FONTSET_START_ADDRESS] = elem;
        }

        return chip8;
    }

    fn runOpcode(self: *Chip8, opcode: u16) !void {
        // TODO: Increase program counter supposed to happen after fetch, chronologically
        self.pc += 2;
        switch (opcode & 0xF000) { // Check the left most byte
            0x0000 => {
                try self.opcode0nnn(opcode);
            },
            0x1000 => {
                self.pc = opcode & 0x0FFF;
            },
            0x2000 => {
                self.stack[self.sp] = self.pc;
                self.sp += 1;
                self.pc = opcode & 0x0FFF;
            },
            0x3000 => {
                const x = (opcode & 0x0F00) >> 8;
                const nn = opcode & 0x00FF;
                if (self.V[x] == nn) {
                    self.pc += 2;
                }
            },
            0x4000 => {
                const x = (opcode & 0x0F00) >> 8;
                const nn = opcode & 0x00FF;
                if (self.V[x] != nn) {
                    self.pc += 2;
                }
            },
            0x5000 => {
                const x = (opcode & 0x0F00) >> 8;
                const y = (opcode & 0x00F0) >> 4;
                if (self.V[x] == self.V[y]) {
                    self.pc += 2;
                }
            },
            0x6000 => {
                const x = (opcode & 0x0F00) >> 8;
                const nn: u8 = @truncate(opcode & 0x00FF);
                self.V[x] = nn;
            },
            0x7000 => {
                // Why doesn't this care about overflow? IT WILL???
                // 30 minutes later me: Okay it does, fixing
                // another 30 minutes: Apparently not, damn, keep both for now
                const x = (opcode & 0x0F00) >> 8;
                const nn: u8 = @truncate(opcode & 0x00FF);
                // Nice unpack
                self.V[x], _ = @addWithOverflow(self.V[x], nn);

                // self.V[x] += nn;
            },
            0x8000 => {
                try self.opcode8nnn(opcode);
            },
            0x9000 => {
                const x = (opcode & 0x0F00) >> 8;
                const y = (opcode & 0x00F0) >> 4;
                if (self.V[x] != self.V[y]) {
                    self.pc += 2;
                }
            },
            0xA000 => {
                self.I = opcode & 0x0FFF;
            },
            0xB000 => {
                self.pc = self.V[0] + (opcode & 0x0FFF);
            },
            0xC000 => {
                const x = (opcode & 0x0F00) >> 8;
                const nn: u8 = @truncate(opcode & 0x00FF);
                self.V[x] = std.crypto.random.int(u8) & nn;
            },
            0xD000 => {
                const x = ((opcode & 0x0F00) >> 8);
                const y = ((opcode & 0x00F0) >> 4);
                const n = (opcode & 0x000F);

                const Vx = self.V[x] % VIDEO_WIDTH;
                const Vy = self.V[y] % VIDEO_HEIGHT;
                self.V[0xF] = 0;

                for (0..n) |r| {
                    const sprite = self.memory[self.I + r];
                    for (0..8) |c| {
                        const sprite_pixel = (@as(u8, 0x80) >> @truncate(c)) & sprite;
                        if (((Vy + r) * VIDEO_WIDTH) + (Vx + c) >= self.gfx.len) {
                            return error.WhyAreYouOutOfRange;
                        }
                        const screen_pixel = self.gfx[((Vy + r) * VIDEO_WIDTH) + (Vx + c)];

                        if (sprite_pixel != 0) {
                            if (screen_pixel != 0) {
                                self.V[0xF] = 1;
                            }
                            self.gfx[((Vy + r) * VIDEO_WIDTH) + (Vx + c)] ^= 0xFF;
                        }
                    }
                }
                self.draw_flag = true;
            },
            0xE000 => {
                try self.opcodeEnnn(opcode);
            },
            0xF000 => {
                try self.opcodeFnnn(opcode);
            },
            else => {
                return error.EyyoWhatIsThis;
            },
        }
    }

    // Program stuffs
    fn opcode0nnn(self: *Chip8, opcode: u16) !void {
        switch (opcode & 0xFFFF) {
            0x00E0 => {
                @memset(&self.gfx, 0x00);
            },
            0x00EE => {
                self.sp -= 1;
                self.pc = self.stack[self.sp];
            },
            else => {
                return error.EyyoWhatIsThis;
            },
        }
    }

    // Mathematic operations, kind of, numbers
    // 30 minutes later me: Register math, that's what it is
    fn opcode8nnn(self: *Chip8, opcode: u16) !void {
        const x = (opcode & 0x0F00) >> 8;
        const y = (opcode & 0x00F0) >> 4;
        switch (opcode & 0x000F) {
            0x0000 => {
                self.V[x] = self.V[y];
            },
            0x0001 => {
                self.V[x] |= self.V[y];
            },
            0x0002 => {
                self.V[x] &= self.V[y];
            },
            0x0003 => {
                self.V[x] ^= self.V[y];
            },
            0x0004 => {
                self.V[x], self.V[0xF] = @addWithOverflow(self.V[x], self.V[y]);
            },
            0x0005 => {
                if (self.V[x] > self.V[y]) {
                    self.V[0xF] = 1;
                } else {
                    self.V[0xF] = 0;
                }
                self.V[x], _ = @subWithOverflow(self.V[x], self.V[y]);
            },
            0x0006 => {
                self.V[0xF] = @truncate(self.V[x] & 0x0001);
                self.V[x] >>= 1;
            },
            0x0007 => {
                if (self.V[y] > self.V[x]) {
                    self.V[0xF] = 1;
                } else {
                    self.V[0xF] = 0;
                }
                self.V[x], _ = @subWithOverflow(self.V[y], self.V[x]);
            },
            0x000E => {
                self.V[0xF] = @truncate((self.V[x] & 0x80) >> 7);
                self.V[x] <<= 1;
            },
            else => {
                return error.EyyoWhatIsThis;
            },
        }
    }

    // Key ops
    // You know, apparently the cpu doesn't give a rat a-- about what a key is
    // I guess the main program has to handle that.
    // Yo, is that what a driver is?
    fn opcodeEnnn(self: *Chip8, opcode: u16) !void {
        const x = (opcode & 0x0F00) >> 8;
        switch (opcode & 0x00FF) {
            0x009E => {
                if (self.key[self.V[x]] != 0) {
                    self.pc += 2;
                }
            },
            0x00A1 => {
                if (self.key[self.V[x]] == 0) {
                    self.pc += 2;
                }
            },
            else => {
                return error.EyyoWhatIsThis;
            },
        }
    }

    fn opcodeFnnn(self: *Chip8, opcode: u16) !void {
        const x = (opcode & 0x0F00) >> 8;
        switch (opcode & 0x00FF) {
            0x0007 => {
                self.V[x] = self.delay_timer;
            },
            0x000A => {
                for (0..16) |k| {
                    if (self.key[k] != 0) {
                        self.V[x] = @truncate(k);
                        return;
                    }
                }
                self.pc -= 2;
            },
            0x0015 => {
                self.delay_timer = self.V[x];
            },
            0x0018 => {
                self.sound_timer = self.V[x];
            },
            0x001E => {
                self.I, _ = @addWithOverflow(self.I, self.V[x]);
            },
            0x0029 => {
                self.I = FONTSET_START_ADDRESS + (self.V[x] * 5);
            },
            0x0033 => {
                self.memory[self.I] = self.V[x] / 100;
                self.memory[self.I + 1] = (self.V[x] % 100) / 10;
                self.memory[self.I + 2] = self.V[x] % 10;
            },
            0x0055 => {
                for (0..x + 1) |offset| {
                    self.memory[self.I + offset] = self.V[offset];
                }
            },
            0x0065 => {
                for (0..x + 1) |offset| {
                    self.V[offset] = self.memory[self.I + offset];
                }
            },
            else => {
                return error.EyyoWhatIsThis;
            },
        }
    }

    pub fn loadRom(self: *Chip8, allocator: std.mem.Allocator, file_name: []const u8) !void {
        const file = try std.fs.cwd().readFileAlloc(allocator, file_name, std.math.maxInt(usize));

        // std.debug.print("\n{any}\n", .{file});
        for (file, 0..) |op, i| {
            self.memory[START_ADDRESS + i] = op;
        }
    }

    pub fn emulateCycle(self: *Chip8) !void {
        const opcode = (@as(u16, self.memory[self.pc]) << 8) | self.memory[self.pc + 1];

        try self.runOpcode(opcode);

        if (self.delay_timer > 0) {
            self.delay_timer -= 1;
        }

        if (self.sound_timer > 0) {
            self.sound_timer -= 1;
        }
    }
};

test "init chip8" {
    const chip8 = Chip8.initialise();

    try testing.expect(chip8.pc == 512);
}

test "opcode 00E0" {
    var chip8 = Chip8.initialise();
    chip8.gfx[0] = 0x80;

    try chip8.runOpcode(0x00E0);
    try testing.expect(chip8.gfx[0] == 0);
    try testing.expect(chip8.pc == START_ADDRESS + 2);
}

test "opcode 00EE" {
    var chip8 = Chip8.initialise();
    chip8.sp = 4;
    chip8.stack[3] = 0x0012;

    try chip8.runOpcode(0x00EE);
    try testing.expect(chip8.pc == 0x0012);
}

test "opcode 1NNN" {
    var chip8 = Chip8.initialise();

    try chip8.runOpcode(0x1123);
    try testing.expect(chip8.pc == 0x0123);
}

test "opcode 2NNN" {
    var chip8 = Chip8.initialise();

    try chip8.runOpcode(0x2123);
    try testing.expect(chip8.pc == 0x0123);
    try testing.expect(chip8.sp == 1);
    try testing.expect(chip8.stack[0] == START_ADDRESS + 2);
}

test "opcode 3XNN" {
    var chip8 = Chip8.initialise();
    chip8.V[4] = 0xF4;

    try chip8.runOpcode(0x34FF);
    try testing.expect(chip8.pc == START_ADDRESS + 2);
    try chip8.runOpcode(0x34F4);
    try testing.expect(chip8.pc == START_ADDRESS + 2 + 4);
    try chip8.runOpcode(0x3FF4);
    try testing.expect(chip8.pc == START_ADDRESS + 2 + 4 + 2);
}

test "opcode 4XNN" {
    var chip8 = Chip8.initialise();
    chip8.V[4] = 0xF4;

    try chip8.runOpcode(0x44FF);
    try testing.expect(chip8.pc == START_ADDRESS + 4);
    try chip8.runOpcode(0x44F4);
    try testing.expect(chip8.pc == START_ADDRESS + 4 + 2);
    try chip8.runOpcode(0x4FF4);
    try testing.expect(chip8.pc == START_ADDRESS + 4 + 2 + 4);
}

test "opcode 5XY0" {
    var chip8 = Chip8.initialise();
    chip8.V[4] = 0xF4;
    chip8.V[7] = 0xF2;

    try chip8.runOpcode(0x5470);
    try testing.expect(chip8.pc == START_ADDRESS + 2);
    chip8.V[4] = 0xF2;
    try chip8.runOpcode(0x5470);
    try testing.expect(chip8.pc == START_ADDRESS + 2 + 4);
}

test "opcode 6XNN" {
    var chip8 = Chip8.initialise();
    chip8.V[4] = 0xF4;

    try chip8.runOpcode(0x644F);
    try testing.expect(chip8.V[4] == 0x4F);
    try testing.expect(chip8.pc == START_ADDRESS + 2);
}

test "opcode 7XNN" {
    var chip8 = Chip8.initialise();
    chip8.V[4] = 0x11;

    try chip8.runOpcode(0x7422);
    try testing.expect(chip8.V[4] == 0x11 + 0x22);
    try testing.expect(chip8.pc == START_ADDRESS + 2);

    chip8.V[4] = 0x01;

    try chip8.runOpcode(0x74FF);
    try testing.expect(chip8.V[4] == 0x00);
    try testing.expect(chip8.pc == START_ADDRESS + 2 + 2);
}

test "opcode 8XY0" {
    var chip8 = Chip8.initialise();
    chip8.V[3] = 0x22;
    chip8.V[4] = 0x11;

    try chip8.runOpcode(0x8340);
    try testing.expect(chip8.V[3] == 0x11);
    try testing.expect(chip8.V[4] == 0x11);
}

test "opcode 8XY1" {
    var chip8 = Chip8.initialise();
    chip8.V[3] = 0x22;
    chip8.V[4] = 0x11;

    try chip8.runOpcode(0x8341);
    try testing.expect(chip8.V[3] == 0x22 | 0x11);
    try testing.expect(chip8.V[4] == 0x11);
}

test "opcode 8XY2" {
    var chip8 = Chip8.initialise();
    chip8.V[3] = 0x22;
    chip8.V[4] = 0x11;

    try chip8.runOpcode(0x8342);
    try testing.expect(chip8.V[3] == 0x22 & 0x11);
    try testing.expect(chip8.V[4] == 0x11);
}

test "opcode 8XY3" {
    var chip8 = Chip8.initialise();
    chip8.V[3] = 0x22;
    chip8.V[4] = 0x11;

    try chip8.runOpcode(0x8343);
    try testing.expect(chip8.V[3] == 0x22 ^ 0x11);
    try testing.expect(chip8.V[4] == 0x11);
}

test "opcode 8XY4" {
    var chip8 = Chip8.initialise();
    chip8.V[3] = 0x22;
    chip8.V[4] = 0x11;

    try chip8.runOpcode(0x8344);
    try testing.expect(chip8.V[3] == 0x22 + 0x11);
    try testing.expect(chip8.V[4] == 0x11);
    try testing.expect(chip8.V[0xF] == 0x0);

    chip8.V[4] = 0xFF;
    try chip8.runOpcode(0x8344);

    try testing.expect(chip8.V[3] == 0x22 + 0x11 - 1);
    try testing.expect(chip8.V[4] == 0xFF);
    try testing.expect(chip8.V[0xF] == 0x1);
}

test "opcode 8XY5" {
    var chip8 = Chip8.initialise();
    chip8.V[3] = 0x22;
    chip8.V[4] = 0x11;

    try chip8.runOpcode(0x8345);
    try testing.expect(chip8.V[3] == 0x22 - 0x11);
    try testing.expect(chip8.V[4] == 0x11);
    try testing.expect(chip8.V[0xF] == 0x1);

    chip8.V[4] = 0xFF;
    try chip8.runOpcode(0x8345);

    try testing.expect(chip8.V[3] == 0x22 - 0x11 + 1);
    try testing.expect(chip8.V[4] == 0xFF);
    try testing.expect(chip8.V[0xF] == 0x0);
}

test "opcode 8XY6" {
    var chip8 = Chip8.initialise();
    chip8.V[3] = 0x23;

    try chip8.runOpcode(0x8346);
    try testing.expect(chip8.V[3] == 0x22 >> 1);
    try testing.expect(chip8.V[0xF] == 0x1);
}

test "opcode 8XY7" {
    var chip8 = Chip8.initialise();
    chip8.V[3] = 0x11;
    chip8.V[4] = 0x22;

    try chip8.runOpcode(0x8347);
    try testing.expect(chip8.V[3] == 0x22 - 0x11);
    try testing.expect(chip8.V[4] == 0x22);
    try testing.expect(chip8.V[0xF] == 0x1);

    chip8.V[3] = 0xFF;
    try chip8.runOpcode(0x8347);

    try testing.expect(chip8.V[3] == 0x22 + 1);
    try testing.expect(chip8.V[4] == 0x22);
    try testing.expect(chip8.V[0xF] == 0x0);
}

test "opcode 8XYE" {
    var chip8 = Chip8.initialise();
    chip8.V[3] = 0x70;

    try chip8.runOpcode(0x834E);
    try testing.expect(chip8.V[3] == 0xE0);
    try testing.expect(chip8.V[0xF] == 0x0);
}

test "opcode 9XY0" {
    var chip8 = Chip8.initialise();
    chip8.V[4] = 0xF4;
    chip8.V[7] = 0xF2;

    try chip8.runOpcode(0x9470);
    try testing.expect(chip8.pc == START_ADDRESS + 4);
    chip8.V[4] = 0xF2;
    try chip8.runOpcode(0x9470);
    try testing.expect(chip8.pc == START_ADDRESS + 4 + 2);
}

test "opcode ANNN" {
    var chip8 = Chip8.initialise();

    try chip8.runOpcode(0xA123);
    try testing.expect(chip8.I == 0x0123);
    try testing.expect(chip8.pc == START_ADDRESS + 2);
}

test "opcode BNNN" {
    var chip8 = Chip8.initialise();
    chip8.V[0] = 0x11;

    try chip8.runOpcode(0xB123);
    try testing.expect(chip8.pc == 0x0123 + 0x0011);
}

test "opcode CXNN" {
    // Actually can fail due to randomness, so, damn
    // Anyway..
    // var chip8 = Chip8.initialise();
    //
    // chip8.run_opcode(0xC123);
    // try testing.expect(chip8.V[1] != 0x23);
}

test "opcode DXYN" {
    var chip8 = Chip8.initialise();

    chip8.V[1] = 1;
    chip8.V[2] = 1;
    chip8.gfx[65] = 0xFF;

    try chip8.runOpcode(0xD123);

    try testing.expect(chip8.gfx[65] == 0xFF);
    try testing.expect(chip8.V[0xF] == 0);

    chip8.memory[chip8.I] = 0xC0;

    try chip8.runOpcode(0xD123);
    try testing.expect(chip8.gfx[65] == 0);
    try testing.expect(chip8.gfx[66] == 0xFF);
    try testing.expect(chip8.V[0xF] == 1);
}

test "opcode EX9E" {
    var chip8 = Chip8.initialise();

    try chip8.runOpcode(0xE19E);
    try testing.expect(chip8.pc == START_ADDRESS + 2);

    chip8.key[0] = 0xFF;
    try chip8.runOpcode(0xE19E);
    try testing.expect(chip8.pc == START_ADDRESS + 2 + 4);
}

test "opcode EXA1" {
    var chip8 = Chip8.initialise();

    try chip8.runOpcode(0xE1A1);
    try testing.expect(chip8.pc == START_ADDRESS + 4);

    chip8.key[0] = 0xFF;
    try chip8.runOpcode(0xE1A1);
    try testing.expect(chip8.pc == START_ADDRESS + 4 + 2);
}

test "opcode FX07" {
    var chip8 = Chip8.initialise();

    chip8.V[1] = 128;
    chip8.delay_timer = 200;
    try chip8.runOpcode(0xF107);

    try testing.expect(chip8.V[1] == 200);
}

test "opcode FX0A" {
    var chip8 = Chip8.initialise();

    try chip8.runOpcode(0xF10A);

    try testing.expect(chip8.pc == START_ADDRESS);

    chip8.key[9] = 0xFF;
    try chip8.runOpcode(0xF10A);
    try testing.expect(chip8.V[1] == 9);
    try testing.expect(chip8.pc == START_ADDRESS + 2);
}

test "opcode FX15" {
    var chip8 = Chip8.initialise();

    chip8.V[1] = 128;
    chip8.delay_timer = 200;
    try chip8.runOpcode(0xF115);

    try testing.expect(chip8.V[1] == 128);
    try testing.expect(chip8.delay_timer == 128);
}

test "opcode FX18" {
    var chip8 = Chip8.initialise();

    chip8.V[1] = 128;
    chip8.sound_timer = 200;
    try chip8.runOpcode(0xF118);

    try testing.expect(chip8.V[1] == 128);
    try testing.expect(chip8.sound_timer == 128);
}

test "opcode FX1E" {
    var chip8 = Chip8.initialise();

    chip8.V[1] = 128;
    chip8.I = 200;
    try chip8.runOpcode(0xF11E);

    try testing.expect(chip8.I == 328);
}

test "opcode FX29" {
    var chip8 = Chip8.initialise();

    chip8.V[1] = 12;
    chip8.I = 200;
    try chip8.runOpcode(0xF129);

    try testing.expect(chip8.I == (FONTSET_START_ADDRESS + (12 * 5)));
}

test "opcode FX33" {
    var chip8 = Chip8.initialise();

    chip8.V[1] = 128;
    try chip8.runOpcode(0xF133);

    try testing.expect(chip8.memory[chip8.I] == 1);
    try testing.expect(chip8.memory[chip8.I + 1] == 2);
    try testing.expect(chip8.memory[chip8.I + 2] == 8);
}

test "opcode FX55" {
    var chip8 = Chip8.initialise();

    chip8.V[1] = 12;
    chip8.V[2] = 13;
    chip8.V[8] = 14;
    chip8.V[9] = 15;
    try chip8.runOpcode(0xF855);

    try testing.expect(chip8.memory[chip8.I] == 0);
    try testing.expect(chip8.memory[chip8.I + 1] == 12);
    try testing.expect(chip8.memory[chip8.I + 2] == 13);
    try testing.expect(chip8.memory[chip8.I + 8] == 14);
    try testing.expect(chip8.memory[chip8.I + 9] == 0);
}

test "opcode FX65" {
    var chip8 = Chip8.initialise();

    chip8.V[1] = 12;
    chip8.V[2] = 13;
    chip8.V[8] = 14;
    chip8.V[9] = 15;
    try chip8.runOpcode(0xF865);

    try testing.expect(chip8.V[0] == 0);
    try testing.expect(chip8.V[1] == 0);
    try testing.expect(chip8.V[2] == 0);
    try testing.expect(chip8.V[8] == 0);
    try testing.expect(chip8.V[9] == 15);
}

test "loadRom" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const file_name: []const u8 = "rom/test_opcode.ch8";
    var chip8 = Chip8.initialise();
    try chip8.loadRom(allocator, file_name);

    try testing.expect(chip8.memory[START_ADDRESS + 477] == 220);
}

test "emulateCycle" {
    var chip8 = Chip8.initialise();

    try testing.expectError(error.EyyoWhatIsThis, chip8.emulateCycle());
    try testing.expect(chip8.pc == START_ADDRESS + 2);

    chip8.memory[chip8.pc] = 0x11;
    chip8.memory[chip8.pc + 1] = 0x23;
    chip8.sound_timer = 3;

    try chip8.emulateCycle();
    try testing.expect(chip8.pc == 0x0123);
    try testing.expect(chip8.sound_timer == 2);
}

// Obligatory comment to make it stop scrolling down, HOLY!
// Can't a dude keep a cosmetic empty line, damn
