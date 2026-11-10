# zig_utils

Extra helper functions for Zig that extend the standard library.

## Requirements

Zig v`0.18.0-dev`.

## Install

For stable (v0.0.1):

```bash
zig fetch --save https://github.com/zig-foundry/zig_utils/archive/refs/tags/v0.0.1.tar.gz
```

For latest (dev / main):

```bash
zig fetch --save https://github.com/zig-foundry/zig_utils/archive/refs/heads/main.tar.gz
```

Or with git ref:

```bash
zig fetch --save git+https://github.com/zig-foundry/zig_utils#v0.0.1
zig fetch --save git+https://github.com/zig-foundry/zig_utils#main
```

This adds the dependency to your `build.zig.zon`.

## Usage

In your `build.zig`:

```zig
const zig_utils = b.dependency("zig_utils", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("zig_utils", zig_utils.module("zig_utils"));
```

Then in your code:

```zig
const zig_utils = @import("zig_utils");

// example
var set = try zig_utils.SetList(i32).init(gpa);
defer set.deinit();
```

Check the `examples/` directory for more.

## Modules

Currently `zig_utils` has these modules:

1. `zig_utils.debug`
2. `zig_utils.SetList` or `zig_utils.Set` (both *Set* and *SetList* are same just name alias.)
3. `zig_utils.slices` (**Working on it**)
4. `zig_utils.Deque` (**Working on it**)
5. `zig_utils.StaticList` (**Wroking on it**)
6. `zig_utils.SmallList` (**Working on it**)
7. `zig_utils.MapList` (**Working on it**)
8. `zig_utils.SlotMap` (**Working on it**)
9. `zig_utils.BTreeSet` (**Working on it**)
10. `zig_utils.BiMap` (**Working on it**)
11. `zig_utils.​OrderedMap` (**Wroking on it**)
12. `zig_utils.strings` (**Working on it**)
13. `zig_utils.fmt_exe` (**Working on it**)
14. `zig_utils.Lazy` (**Working on it**)
15. `zig_utils.Once` (**Working on it**)
16. `zig_utils.BitFlags` (**Working on it**)

## Commands

Run tests:

```bash
zig build test
```

Check compilation:

```bash
zig build check
```

Build docs:

```bash
zig build docs
```

## License

This project uses the [MIT License](LICENSE).
