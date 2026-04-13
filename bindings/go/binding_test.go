package tree_sitter_bush_test

import (
	"testing"

	tree_sitter "github.com/tree-sitter/go-tree-sitter"
	tree_sitter_bush "github.com/czajkub/bush/bindings/go"
)

func TestCanLoadGrammar(t *testing.T) {
	language := tree_sitter.NewLanguage(tree_sitter_bush.Language())
	if language == nil {
		t.Errorf("Error loading Bush grammar")
	}
}
