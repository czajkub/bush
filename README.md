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
```

## Generate parser

1. Install [Tree-sitter CLI](https://github.com/tree-sitter/tree-sitter/blob/master/crates/cli/README.md)
2. Run `tree-sitter generate grammar.js`

## Documentation

- [Language Tokens](docs/TOKENS.md)
- [Grammar Rules](docs/GRAMMAR.md)
