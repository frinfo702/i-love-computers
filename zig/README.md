# Zig Overview

## run single file

```bash
zig run hello.zig
```

## build

```bash
zig build-exe hello.zig
./hello
```

# make optimized build

```zsh
zig build-exe hello.zig -O ReleaseFast
zig run hello.zig -O Debug
```

## project

### initialize project

```bash
mkdir myapp
cd myapp
zig init # 0.12+
```

### fundamental commands in a project

```bash
zig build
zig build run
zig build test
```
