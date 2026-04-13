/// <reference types="tree-sitter-cli/dsl" />
// @ts-check

module.exports = grammar({
  name: "bashlike",

  rules: {
    // A program is a list of statements
    source_file: ($) => repeat($._statement),

    _statement: ($) =>
      choice($.command, $.if_statement, $.while_statement, $.assignment),

    assignment: ($) => seq($.variable, "=", $._expression),

    if_statement: ($) =>
      seq("if", $._expression, "{", repeat($._statement), "}"),

    while_statement: ($) =>
      seq("while", $._expression, "{", repeat($._statement), "}"),

    function_definition: ($) =>
      seq(
        "function",
        "(",
        repeat($.variable),
        ")",
        "{",
        repeat($._statement),
        "}",
      ),

    // ==========================================
    // "COMMAND MODE" (The context)
    // ==========================================
    command: ($) => seq($.command_name, repeat($.argument)),
    command_name: ($) => /[a-zA-Z]+/,
    argument: ($) => /[a-zA-Z0-9_.-]+/,

    // ==========================================
    // "_expression MODE" (The context)
    // ==========================================
    _expression: ($) => choice($.number, $.variable, $.binary_expression),

    binary_expression: ($) =>
      prec.left(
        seq($._expression, choice("+", "-", "*", "/", "<", ">"), $._expression),
      ),

    variable: ($) => seq("$", /[a-zA-Z_]+/),
    number: ($) => /\d+/,
  },
});
