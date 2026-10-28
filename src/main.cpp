#include "lexer.h"
#include "parser.h"
#include "astdump.h"
#include "typecheck.h"
#include "llvmir.h"
#include <iostream>
#include <fstream>
#include <sstream>
#include <string>
#include <sys/stat.h>
#include <sys/types.h>

using namespace chokanbun;

static bool readFile(const std::string& path, std::string& out) {
    std::ifstream f(path, std::ios::binary);
    if (!f) return false;
    std::ostringstream ss;
    ss << f.rdbuf();
    out = ss.str();
    return true;
}

static bool writeFile(const std::string& path, const std::string& content) {
    std::ofstream f(path, std::ios::binary);
    if (!f) return false;
    f << content;
    return f.good();
}

static void printDiagnostics(const std::vector<Diagnostic>& diags) {
    for (auto& d : diags) {
        std::cerr << d.format() << "\n";
    }
}

int main(int argc, char* argv[]) {
    if (argc < 2) {
        std::cerr << "usage: chokanbun <source> [options]\n";
        std::cerr << "  -o <file>    output file\n";
        std::cerr << "  -ir          output LLVM IR\n";
        std::cerr << "  -ast         output AST (debug)\n";
        std::cerr << "  -tokens      output tokens (debug)\n";
        std::cerr << "  -check       type check only (diagnostics on stderr)\n";
        return 1;
    }

    std::string sourcePath = argv[1];
    std::string outputPath;
    bool emitIR = false;
    bool emitAST = false;
    bool emitTokens = false;
    bool checkOnly = false;

    for (int i = 2; i < argc; i++) {
        std::string arg = argv[i];
        if (arg == "-o" && i + 1 < argc) {
            outputPath = argv[++i];
        } else if (arg == "-ir") {
            emitIR = true;
        } else if (arg == "-ast") {
            emitAST = true;
        } else if (arg == "-tokens") {
            emitTokens = true;
        } else if (arg == "-check") {
            checkOnly = true;
        } else {
            std::cerr << "unknown option: " << arg << "\n";
            return 1;
        }
    }

    // LLVM IR is currently the only backend, so -ir is accepted but the
    // default output is always textual IR.
    (void)emitIR;

    // Read source
    std::string source;
    if (!readFile(sourcePath, source)) {
        std::cerr << "error: cannot read " << sourcePath << "\n";
        return 1;
    }

    // Lex
    Lexer lexer(source);
    auto tokens = lexer.tokenize();

    if (!lexer.diagnostics().empty()) {
        printDiagnostics(lexer.diagnostics());
        return 1;
    }

    if (emitTokens) {
        for (auto& t : tokens) {
            std::cout << t.line << ":" << t.col << " " << t.kindName() << " " << t.text << "\n";
        }
        return 0;
    }

    // Parse
    Parser parser(tokens);
    Module mod = parser.parseModule();

    if (parser.hasErrors()) {
        printDiagnostics(parser.diagnostics());
        return 1;
    }

    if (emitAST) {
        std::cout << dumpModule(mod);
        return 0;
    }

    // Type check
    TypeChecker typechecker(mod);
    typechecker.check();

    if (typechecker.hasErrors()) {
        printDiagnostics(typechecker.diagnostics());
        return 1;
    }

    if (checkOnly) return 0;

    // Generate LLVM IR
    LLVMIRGen irgen;
    std::string ir = irgen.generate(mod, typechecker);

    if (irgen.hasErrors()) {
        printDiagnostics(irgen.diagnostics());
        return 1;
    }

    // Output
    if (outputPath.empty()) {
        // Default: replace extension
        outputPath = sourcePath;
        size_t dot = outputPath.find_last_of('.');
        if (dot != std::string::npos) {
            outputPath = outputPath.substr(0, dot);
        }
        outputPath += ".ll";
    }

    if (!writeFile(outputPath, ir)) {
        std::cerr << "error: cannot write " << outputPath << "\n";
        return 1;
    }

    std::cerr << "wrote " << outputPath << "\n";
    return 0;
}
