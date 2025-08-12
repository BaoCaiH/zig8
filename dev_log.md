# Dev log
More of a pain diary, to be honest.

## Saviours
These are the best teachers in the world, imo

- https://multigesture.net/articles/how-to-write-an-emulator-chip-8-interpreter/
- https://code.austinmorlan.com/austin/2019-chip8-emulator/src/branch/master/Source/Chip8.cpp
- https://github.com/corax89/chip8-test-rom
- https://github.com/mattmikolay/chip-8/wiki/Mastering-CHIP%E2%80%908#chip-8-instructions
- https://en.wikipedia.org/wiki/CHIP-8
- http://devernay.free.fr/hacks/chip8/C8TECH10.HTM

## Logs
Why is it top down instead of bottom up?
Because it's a diary, not a changelog, duh.

### 2025-07-08
They said don't start a new project with both new language and new concept.
Well, zig is new, emulator is new, everything is overwhelming.
Sounds a hell lot like a huge mistake.
Let's see.

Strategy now is just, initialise the cpu, memory, and stuffs, I guess.
Took a while but at least it's built.
Test is there, very primitive, but it means it worked.
HO!

### 2025-07-24
So, freaking opcode.
Yo, idk why the sh\*t the opcode has to be denoted like `0NNN` or `3XNN`.
What had the people back then had to go through?
Why can't they just be `0---` then detailed what those 3 any bytes mean.
Like yo, I can't even keep the memory from 5s ago in my head, how am I suppose to scroll down from the opcode list and still remember what `NNN` means.
Also, why denote 3 different things with the same character with different lengths, why not `LLL`, `MM`, `N`.
Did we run out of characters or some sh\*t?

Anyway, took a while but I figured all the simple op out.
Holyhell!

### 2025-07-25
Alright, better day today.
Implemented aalll opcode starting with 0 through B.
Yeah that sentence made sense.

### 2025-07-26
All opcode done.
I think that's the easy part though.
How to output pixel and sound, no idea.

### 2025-08-04
Full working week and a game jam later, I'm back.
And I have no idea how any of the SDL things work.
Copy the lord's SDL demo (somehow it's there) to learn how the thing kind of work first.

Alright will try to keep aspect ratio while resizing.
Also, SDL documentation is horrible.
Sure it's useful to know which version added it.
Oh? But what does this `data1` field mean? It's event dependent? Oh? List it down then? No? Excuse me?
And people said SDL is easy to use, not for a beginner.
Which is not good, in case there's still ambiguity.

Alright, fixed aspect ratio resizable window is done, baby.
Good progress day, yet again.

### 2025-08-05
Didn't do much today.
Handled some inputs.
Maybe start main game loop tmr.

### 2025-08-09
Yo!
So, it's kinda work.
Idk why it's out of memory range for like 1 cycle.
Why 1 cycle?
I have no idea.
But it worked.
Kind of.
The blinky is beautiful.

### 2025-08-10
Okay, added also time delay for cpu cycle and rom arg.

### 2025-08-12
Tried very much to build for wasm.
Failed miserably.
This is not worth it, not like I want to build for the web very much.
So let's just wrap it up.
I learned what I need for emulator.

