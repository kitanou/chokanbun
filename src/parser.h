#pragma once
#include "lexer.h"
#include "ast.h"
#include <vector>
#include <string>

namespace chokanbun {

class Parser {
public:
    explicit Parser(std::vector<Token> tokens);

    Module parseModule();

    const std::vector<Diagnostic>& diagnostics() const { return diags_; }
    bool hasErrors() const { return hasErrors_; }

private:
    // Token helpers
    bool atEnd() const;
    const Token& current() const;
    const Token& peek() const;
    Token advance();
    bool check(TokKind kind) const;
    bool match(TokKind kind);
    bool matchAny(std::initializer_list<TokKind> kinds);
    Token expect(TokKind kind, const std::string& what);
    void error(const Token& tok, const std::string& code, const std::string& msg);
    void errorAt(uint32_t line, uint32_t col, const std::string& code, const std::string& msg);

    // Declarations
    Decl parseDeclaration();
    std::shared_ptr<FunctionDecl> parseFunction();
    std::shared_ptr<FunctionDecl> parseFunctionAfterKeyword(bool isExternal);
    std::shared_ptr<FunctionDecl> parseExternal();
    std::shared_ptr<AliasDecl> parseAlias();
    std::shared_ptr<ConstantDecl> parseConstant();
    std::shared_ptr<StructDecl> parseStruct();

    // Types
    TypePtr parseType();

    // Statements
    StmtPtr parseStatement();
    std::vector<StmtPtr> parseBlock();
    StmtPtr parseLocal();
    StmtPtr parseAssign();
    StmtPtr parseCallStmt();
    StmtPtr parseIf();
    StmtPtr parseWhile();
    StmtPtr parseReturn();
    StmtPtr parseUnsafe();

    // Expressions (precedence climbing)
    ExprPtr parseExpr();
    ExprPtr parseOrExpr();
    ExprPtr parseAndExpr();
    ExprPtr parseBitOrExpr();
    ExprPtr parseBitXorExpr();
    ExprPtr parseBitAndExpr();
    ExprPtr parseEqualityExpr();
    ExprPtr parseRelationalExpr();
    ExprPtr parseShiftExpr();
    ExprPtr parseAdditiveExpr();
    ExprPtr parseMultiplicativeExpr();
    ExprPtr parseUnaryExpr();
    ExprPtr parsePrimary();

    // LValues
    ExprPtr parseLvalue();

    // Attributes (before function decl)


    std::vector<Token> tokens_;
    size_t pos_ = 0;
    std::vector<Diagnostic> diags_;
    bool hasErrors_ = false;
};

} // namespace chokanbun
