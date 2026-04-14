# Bush Language Tokens

This document outlines the lexical tokens of the `bush` language, based on its tree-sitter grammar definition.

## Keywords

| Token Name | Syntax | Description |
| :--- | :--- | :--- |
| `function` | `"function"` | Declares a function |
| `if` | `"if"` | Conditional if statement |
| `while` | `"while"` | While loop statement |
| `return` | `"return"` | Returns a value from a function |

## Identifiers and Literals

| Token Name | Regex / Syntax | Description |
| :--- | :--- | :--- |
| `variable_identifier` | `/\$[a-zA-Z_]+/` | Variable identifier, prefix with `$` (e.g., `$var`) |
| `command_name` | `/[a-zA-Z_./][a-zA-Z0-9_.\/-]*/` | Command executable name |
| `simple_argument` | `/[a-zA-Z0-9_.-]+/` | Simple command argument |
| `number_literal`| `/\d+/` | Numeric sequence |
| `string_literal`| `"..."` (`/"[^"]*"/`) | Double-quoted string literal |

## Operators

| Token Name | Operators | Description |
| :--- | :--- | :--- |
| Assignment | `=` | Assigns an expression to a variable |
| Multiplicative | `*`, `/` | Binary multiplication and division |
| Additive | `+`, `-` | Binary addition and subtraction |
| Comparative | `==`, `!=`, `<`, `<=`, `>`, `>=` | Comparison operations |
| Logical | `&&`, `||` | Logical AND, Logical OR |
| Unary | `+`, `-`, `!`, `^`, `*`, `&`, `<-` | Unary prefix operators |

## Shell and Command Specifics

| Token Name | Syntax | Description |
| :--- | :--- | :--- |
| Pipe | `|` | Pipes output of one command to another |
| Redirect | `>`, `>>`, `&>`, `2>` | Redirects command output |
| Expression Arg | `${...}` | Embedded expression in command argument |
| Command Expr | `$(...)` | Command substitution / execution |

## Punctuation and Comments

| Token Name | Syntax | Description |
| :--- | :--- | :--- |
| Terminator | `\n`, `;`, `\0` | Statement terminators |
| Parentheses | `(`, `)` | Grouping expressions, parameter lists |
| Braces | `{`, `}` | Blocks of statements |
| Comma | `,` | Separator for function parameters |
| Line Comment | `// ...` | Single-line comment |
| Block Comment | `/* ... */` | Multi-line comment |
