# bush

Bash Upgraded SHell

- **Goal:** improve the existing bash shell by removing arcane syntax conventions and simplifying syntax
- **Language:** Zig
- **Parser Generator:** Tree-sitter

## Authors

- Jakub Czajka <czajkub@student.agh.edu.pl>
- Jakub Czyż <jczyz@student.agh.edu.pl>

## Example program

```
// Operator precedence
$counter = 1 || 2 && 3 == 4 + 5 * -(6 + 7)

// function declaration
function add($a, $b) {
    return $a + $b
}

// loop
while $counter < 10 {
    // piped command with redirects
    cat test | cat > res.txt | cat &> res2.txt

    // function call
    $counter = $counter + $(add 1 2)
}

$a = 10
$b = 20
$c = $a + $b * 2

$is_equal = $a == 10
$is_greater = $b > $a

$sum = add($a, $b)

$EXPORT_TEST = 12345

echo $EXPORT_TEST

```

## Development

### Prerequisites

- [Zig](https://ziglang.org/) (tested with 0.15.2, notoriously very unstable :P)
- [Node.js & npm](https://nodejs.org/)
- [Tree-sitter CLI](https://tree-sitter.github.io/tree-sitter/creating-parsers#installation)
- `libtree-sitter` (system library)

### Generate Parser

To generate the C parser from `grammar.js`, use the Tree-sitter CLI. You can run it via `npm` (if dependencies are installed) or directly:

```bash
# Using npm script
npm run gen

# Using npx (uses the tree-sitter-cli package)
npx tree-sitter-cli generate -o tree-sitter-config

# Using global tree-sitter CLI
tree-sitter generate -o tree-sitter-config
```

The `-o tree-sitter-config` flag is required to keep the generated code separated from the Zig source.

### Build & Run

To build the library and run the example application:

```bash
# using npm script
npm run bush test.bush

# using zig directly (-- is for passing arguments)
zig build run -- test.bush
```

### Run Tests

```bash
zig build test
```

## Documentation

- [Language Tokens](docs/TOKENS.md)
- [Grammar Rules](docs/GRAMMAR.md)
