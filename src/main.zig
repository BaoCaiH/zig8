const std = @import("std");

const cpu_lib = @import("cpu_lib");
const c = @cImport({
    @cInclude("SDL3/SDL.h");
});

const time = std.time;
const print = std.debug.print;
const assert = std.debug.assert;

pub fn main() !void {
    // Set up render system and register input callbacks
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = std.process.argsAlloc(allocator) catch |err| {
        print("Some error occurred when cli started: {}\n", .{err});
        return error.NoArgumentsWerePassed;
    };
    defer std.process.argsFree(allocator, args);
    if (args.len > 2) {
        print("Too many arguments were passed\n", .{});
        return error.TooManyArgumentsWerePassed;
    }

    var file_name: []const u8 = "rom/test_opcode.ch8";
    if (args.len < 2) {
        print("No rom were passed, displaying test_opcode rom\n", .{});
    } else {
        file_name = args[1];
    }

    // Initialise and load rom
    var chip8 = cpu_lib.Chip8.initialise();
    try chip8.loadRom(allocator, file_name);
    print("ROM loaded\n", .{});
    print("Pixel size {}\n", .{@sizeOf(u8)});

    // Initialise graphic and inputs
    if (!c.SDL_Init(c.SDL_INIT_VIDEO)) {
        c.SDL_Log("Unable to initialise SDL: %s", c.SDL_GetError());
        return error.SDLInitialisationFailed;
    }
    defer c.SDL_Quit();

    // // Both works but I'll keep the c pointer cast thing, for learning
    // const window = c.SDL_CreateWindow("chip8", 640, 320, c.SDL_WINDOW_OPENGL | c.SDL_WINDOW_RESIZABLE) orelse {
    //     c.SDL_Log("Unable to create window: %s", c.SDL_GetError());
    //     return error.SDLWindowCreationFailed;
    // };
    // defer c.SDL_DestroyWindow(window);
    //
    // const renderer = c.SDL_CreateRenderer(window, null) orelse {
    //     c.SDL_Log("Unable to create renderer: %s", c.SDL_GetError());
    //     return error.SDLRendererCreationFailed;
    // };
    // defer c.SDL_DestroyRenderer(renderer);

    var window: ?*c.SDL_Window = undefined;
    var renderer: ?*c.SDL_Renderer = undefined;
    if (!c.SDL_CreateWindowAndRenderer(
        "chip8",
        640,
        320,
        c.SDL_WINDOW_OPENGL | c.SDL_WINDOW_RESIZABLE,
        @as([*c]?*c.SDL_Window, &window),
        @as([*c]?*c.SDL_Renderer, &renderer),
    )) {
        c.SDL_Log("Unable to create window and renderer: %s", c.SDL_GetError());
        return error.SDLWindowAndRendererCreationFailed;
    }
    defer c.SDL_DestroyWindow(window);
    defer c.SDL_DestroyRenderer(renderer);

    const zig_bmp = @embedFile("zig.bmp");
    const io = c.SDL_IOFromConstMem(zig_bmp, zig_bmp.len) orelse {
        c.SDL_Log("Unable to load Zig bitmap: %s", c.SDL_GetError());
        return error.SDLLoadBitmapFailed;
    };
    defer assert(c.SDL_CloseIO(io));

    var quit = false;
    const aspect: f32 = 640 / 320;
    var drawable_width: f32 = 640;
    var drawable_height: f32 = 320;
    var draw_width: f32 = drawable_width;
    var draw_height: f32 = drawable_width / aspect;
    var dest_rect: c.SDL_FRect = undefined;

    const texture: *c.SDL_Texture = c.SDL_CreateTexture(
        renderer,
        c.SDL_PIXELFORMAT_RGB332,
        c.SDL_TEXTUREACCESS_TARGET,
        cpu_lib.VIDEO_WIDTH,
        cpu_lib.VIDEO_HEIGHT,
    );
    defer c.SDL_DestroyTexture(texture);
    _ = c.SDL_SetTextureScaleMode(texture, c.SDL_SCALEMODE_NEAREST);

    var cycle: u64 = 0;
    var last_stamp: f64 = @floatFromInt(time.milliTimestamp());
    var current_stamp: f64 = 0;
    var dt: f64 = 0;
    while (!quit) {
        current_stamp = @floatFromInt(time.milliTimestamp());
        dt = current_stamp - last_stamp;
        if (dt <= (1 / 960)) {
            continue;
        }
        last_stamp = @floatFromInt(time.milliTimestamp());
        cycle += 1;
        // One cycle
        chip8.emulateCycle() catch |err| {
            print("Failed on cycle {} with error: {}\n", .{ cycle, err });
        };

        // Get texure and draw
        _ = c.SDL_UpdateTexture(
            texture,
            null,
            &chip8.gfx,
            cpu_lib.VIDEO_WIDTH,
        );
        if (chip8.draw_flag) {
            _ = c.SDL_RenderClear(renderer);
            _ = c.SDL_RenderTexture(renderer, texture, null, &dest_rect);
            _ = c.SDL_RenderPresent(renderer);

            chip8.draw_flag = false;
        }

        // Handle input
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event)) {
            switch (event.type) {
                c.SDL_EVENT_QUIT => {
                    quit = true;
                },
                c.SDL_EVENT_KEY_DOWN => {
                    handle_input(event.key.key, &chip8, &quit, 0xFF);
                },
                c.SDL_EVENT_KEY_UP => {
                    handle_input(event.key.key, &chip8, &quit, 0);
                },
                c.SDL_EVENT_WINDOW_RESIZED => {
                    drawable_width = @floatFromInt(event.display.data1);
                    drawable_height = @floatFromInt(event.display.data2);
                    if (drawable_height * aspect <= drawable_width) {
                        draw_width = draw_height * aspect;
                        draw_height = drawable_height;
                    } else {
                        draw_width = drawable_width;
                        draw_height = drawable_width / aspect;
                    }
                },
                else => {},
            }
        }

        if (drawable_width == draw_width) {
            dest_rect = c.SDL_FRect{
                .x = 0,
                .y = (drawable_height - draw_height) / 2,
                .w = draw_width,
                .h = draw_height,
            };
        }
    }
}

fn handle_input(sdl_key: c.SDL_Keycode, chip8: *cpu_lib.Chip8, quit: *bool, action: u8) void {
    switch (sdl_key) {
        c.SDLK_ESCAPE => {
            quit.* = true;
        },
        c.SDLK_X => {
            chip8.key[0] = action;
        },
        c.SDLK_1 => {
            chip8.key[1] = action;
        },
        c.SDLK_2 => {
            chip8.key[2] = action;
        },
        c.SDLK_3 => {
            chip8.key[3] = action;
        },
        c.SDLK_Q => {
            chip8.key[4] = action;
        },
        c.SDLK_W => {
            chip8.key[5] = action;
        },
        c.SDLK_E => {
            chip8.key[6] = action;
        },
        c.SDLK_A => {
            chip8.key[7] = action;
        },
        c.SDLK_S => {
            chip8.key[8] = action;
        },
        c.SDLK_D => {
            chip8.key[9] = action;
        },
        c.SDLK_Z => {
            chip8.key[0xA] = action;
        },
        c.SDLK_C => {
            chip8.key[0xB] = action;
        },
        c.SDLK_4 => {
            chip8.key[0xC] = action;
        },
        c.SDLK_R => {
            chip8.key[0xD] = action;
        },
        c.SDLK_F => {
            chip8.key[0xE] = action;
        },
        c.SDLK_V => {
            chip8.key[0xF] = action;
        },
        else => {},
    }
}
