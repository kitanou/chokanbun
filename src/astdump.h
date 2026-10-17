#pragma once
#include "ast.h"
#include <string>

namespace chokanbun {

// Deterministic S-expression dump of a parsed module. Used by `-ast` and by the
// parser golden tests (tests/lang/ok/*.ast).
std::string dumpModule(const Module& mod);

} // namespace chokanbun
