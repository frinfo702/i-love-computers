# ⚡ zigrep

```
╔══════════════════════════════════════════════╗
║   ⚡  Z I G R E P  ⚡                        ║
║   blazing-fast file search                   ║
╚══════════════════════════════════════════════╝
```

Zigで書かれた、視覚的に楽しいファイル検索CLIツール。

## Features

- **超高速**: Zigのゼロコスト抽象化による高速な再帰検索
- **カラフルなUI**: Unicodeボックス・ライン文字とANSIカラーで視覚的に鮮やか
- **マッチハイライト**: 一致箇所を色付きでインラインハイライト
- **286KB** のシングルバイナリ

## Build

```sh
zig build -Doptimize=ReleaseFast
./zig-out/bin/zigrep --help
```

## Usage

```
zigrep [OPTIONS] <PATTERN> [PATH...]
```

### Options

| Flag                       | Description                         |
| -------------------------- | ----------------------------------- |
| `-i, --ignore-case`        | Case-insensitive matching           |
| `-r, --recursive`          | Recurse into directories (default)  |
| `-n, --line-number`        | Show line numbers (default)         |
| `-c, --count`              | Print match count per file          |
| `-l, --files-with-matches` | Print only filenames                |
| `-v, --invert-match`       | Invert match                        |
| `-w, --word-regexp`        | Match whole words only              |
| `-C<N>`                    | Show N context lines around matches |
| `--no-color`               | Disable color output                |
| `--max-depth=N`            | Max directory recursion depth       |
| `-h, --help`               | Show help                           |

### Examples

```sh
# Search for 'fn' in src/
zigrep fn src/

# Case-insensitive search
zigrep -i TODO .

# Show 2 context lines
zigrep -C2 main src/main.zig

# List only matching filenames
zigrep -l error .

# Whole-word match
zigrep -w fn src/
```

## Visual Output

```
╭─ Searching ❯ main
│  Path: src/
╰──────────────────────────────────────────

┌─ src/main.zig  [1 ✦]
│
│     4 │ pub fn main() !void {

╭─────────────────────────────────────────────╮
│  ⚡ Search complete                         │
│  ✦ Matches   : 1                            │
│  ◈ Files hit : 1 / 1                        │
│  ⏱ Time      : 0ms 123µs                    │
│  ◎ Data      : 0 KB                         │
╰─────────────────────────────────────────────╯
```
