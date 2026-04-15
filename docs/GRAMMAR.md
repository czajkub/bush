# Grammar Rules

The syntactic grammar of `bush` is represented below by its complete Tree-sitter definition:

```javascript
const PREC = {
  unary: 6,
  multiplicative: 5,
  additive: 4,
  comparative: 3,
  and: 2,
  or: 1,
};

const multiplicativeOperators = ["*", "/"];
const additiveOperators = ["+", "-"];
const comparativeOperators = ["==", "!=", "<", "<=", ">", ">="];

const terminator = choice("\n", ";", "\0");

export default grammar({
  name: "bush",

  rules: {
    source_file: ($) =>
      repeat(seq(choice($._declaration, $._statement), terminator)),

    _declaration: ($) => choice($.function_definition),

    function_definition: ($) =>
      seq(
        "function",
        field("name", $.command_name),
        "(",
        field(
          "parameters",
          optional(
            seq($.variable_identifier, repeat(seq(",", $.variable_identifier))),
          ),
        ),
        ")",
        "{",
        repeat(seq($._statement, terminator)),
        "}",
      ),

    _statement: ($) =>
      choice(
        $.assignment,
        $._command,
        $.if_statement,
        $.while_statement,
        $.return_statement,
      ),

    assignment: ($) =>
      seq(
        field("variable", $.variable_identifier),
        "=",
        field("expression", $._expression),
      ),

    if_statement: ($) =>
      seq(
        "if",
        field("condition", $._expression),
        "{",
        field("body", repeat(seq($._statement, terminator))),
        "}",
      ),

    while_statement: ($) =>
      seq(
        "while",
        field("condition", $._expression),
        "{",
        field("body", repeat(seq($._statement, terminator))),
        "}",
      ),

    return_statement: ($) => seq("return", field("expression", $._expression)),

    _command: ($) => choice($.simple_command, $.piped_command),

    piped_command: ($) =>
      prec.left(
        seq(field("left", $._command), "|", field("right", $._command)),
      ),

    simple_command: ($) =>
      seq(
        field("name", $.command_name),
        field("args", repeat($._command_argument)),
        field("redirect", optional($.redirect)),
      ),

    redirect: ($) =>
      seq(
        field("operator", choice(">", ">>", "&>", "2>")),
        field("file", $._command_argument),
      ),

    command_name: ($) => /[a-zA-Z_./][a-zA-Z0-9_.\/-]*/,
    _command_argument: ($) =>
      choice($.simple_argument, $.expression_argument, $.command_expression),

    simple_argument: ($) => /[a-zA-Z0-9_.-]+/,
    expression_argument: ($) => seq("${", $._expression, "}"),

    _expression: ($) =>
      choice(
        $.number_literal,
        $.string_literal,
        $.variable_identifier,
        $.command_expression,
        $.binary_expression,
        $.unary_expression,
        $._parenthesized_expression,
      ),
    _parenthesized_expression: ($) => seq("(", $._expression, ")"),

    unary_expression: ($) =>
      prec(
        PREC.unary,
        seq(
          field("operator", choice("+", "-", "!", "^", "*", "&", "<-")),
          field("operand", $._expression),
        ),
      ),

    binary_expression: ($) => {
      /**
       * @type [number, RuleOrLiteral][]
       */
      const table = [
        [PREC.multiplicative, choice(...multiplicativeOperators)],
        [PREC.additive, choice(...additiveOperators)],
        [PREC.comparative, choice(...comparativeOperators)],
        [PREC.and, "&&"],
        [PREC.or, "||"],
      ];

      return choice(
        ...table.map(([precedence, operator]) =>
          prec.left(
            precedence,
            seq(
              field("left", $._expression),
              field("operator", operator),
              field("right", $._expression),
            ),
          ),
        ),
      );
    },

    command_expression: ($) => seq("$(", $._command, ")"),

    variable_identifier: ($) => /\$[a-zA-Z_]+/,
    number_literal: ($) => /\d+/,
    string_literal: ($) => seq('"', /[^"]*/, '"'),

    _comment: (_) =>
      token(
        choice(seq("//", /.*/), seq("/*", /[^*]*\*+([^/*][^*]*\*+)*/, "/")),
      ),
  },
  extras: ($) => [/\s/, $._comment, terminator],
});
```
