# bush

### Authors

- Jakub Czajka <czajkub@student.agh.edu.pl>
- Jakub Czyż <jczyz@student.agh.edu.pl>


## Bash Upgraded SHell


The **Goal** of the languague is improving the existing bash shell by removing arcane syntax conventions and simplifying syntax.
This is done in several ways:
- variable names start with a `$`, e.g. `$a = 10`
- function definitions must *explicitly* start with keyword `function`
- improved control flow: C-style `if` conditionals, `for`, `while` loops
  
This is done to give bash a slightly more modern feel rather than outdated syntax not seen anywhere else (e.g. `[[  ]]` tests)

### Technical details:
- **Language Type:** Interpreted language
- **Implementation Language:** Zig
- **Parser Generator** used: [Tree-sitter](https://tree-sitter.github.io/tree-sitter/)


## Grammar

- [Language Tokens](docs/TOKENS.md)
- [Grammar Rules](docs/GRAMMAR.md)


## Development

### Prerequisites

- [Zig](https://ziglang.org/) (tested with 0.16.0, notoriously very unstable language :P)
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



## Example program

```
$a = 20
$b = 10

function sum2($a, $b) {
    return $a + $b;
}

$sum = sum2($a, $b)

if ($sum > 25) {
    echo "Sum is greater than 25"
}

```



