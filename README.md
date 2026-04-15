# bush

Bash Upgraded SHell

- **Goal:** improve the existing bash shell by removing arcane syntax conventions and simplifying syntax
- **Language:** Zig
- **Parser Generator:** Tree-sitter

## Authors

- Jakub Czajka <czajkub@student.agh.edu.pl>
- Jakub Czyż <jczyz@student.agh.edu.pl>

## Generate parser

1. Install [Tree-sitter CLI](https://github.com/tree-sitter/tree-sitter/blob/master/crates/cli/README.md)
2. Run `tree-sitter generate grammar.js`

## Documentation

- [Language Tokens](docs/TOKENS.md)
- [Grammar Rules](docs/GRAMMAR.md)
