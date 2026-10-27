#pragma once
#include "ast.h"
#include "lexer.h"
#include <string>
#include <vector>
#include <map>
#include <set>
#include <memory>

namespace chokanbun {

class TypeChecker {
public:
    explicit TypeChecker(const Module& mod);

    // Run type checking on all declarations. Returns true if errors were found.
    bool check();

    // Query expression type (valid after check())
    const TypePtr& exprType(const Expr& e) const;
    // Query lvalue type (the type of the lvalue itself)
    const TypePtr& lvalueType(const Expr& e) const;

    const std::vector<Diagnostic>& diagnostics() const { return diags_; }
    bool hasErrors() const { return hasErrors_; }

private:
    // Expression type checking
    TypePtr checkExpr(const Expr& e);
    TypePtr checkIdent(const Expr& e);
    TypePtr checkBinOp(const Expr& e);
    TypePtr checkUnaryOp(const Expr& e);
    TypePtr checkCall(const Expr& e);
    TypePtr checkAddrOf(const Expr& e);
    TypePtr checkDeref(const Expr& e);
    TypePtr checkCast(const Expr& e);
    TypePtr checkVolatileRead(const Expr& e);
    TypePtr checkVolatileWrite(const Expr& e);
    TypePtr checkFence(const Expr& e);
    TypePtr checkAsm(const Expr& e);
    TypePtr checkMachine(const Expr& e);
    TypePtr checkStrLen(const Expr& e);
    TypePtr checkFieldAccess(const Expr& e);
    TypePtr checkElemAccess(const Expr& e);

    // Statement checking
    void checkStmt(const Stmt& s);
    void checkLocalDecl(const Stmt& s);
    void checkAssign(const Stmt& s);
    void checkCallStmt(const Stmt& s);
    void checkIf(const Stmt& s);
    void checkWhile(const Stmt& s);
    void checkReturn(const Stmt& s);
    void checkUnsafeBlock(const Stmt& s);
    void checkExprStmt(const Stmt& s);

    // Declaration checking
    void checkFunction(const FunctionDecl& fn);
    bool alwaysReturns(const std::vector<StmtPtr>& block) const;
    void checkExternal(const FunctionDecl& fn);
    void checkConstant(const ConstantDecl& c);
    void checkStruct(const StructDecl& s);

    // Helpers
    void error(uint32_t line, uint32_t col, const std::string& code, const std::string& msg);
    void errorAt(const Expr& e, const std::string& code, const std::string& msg);
    void errorAt(const Stmt& s, const std::string& code, const std::string& msg);

    // Literal coercion: an untyped integer literal adopts the expected integer
    // type, and 空 adopts the expected pointer type. Returns true if applied.
    bool coerceLiteral(const ExprPtr& value, const TypePtr& target);

    // 初期化式を検査中の変数名 (自己参照による未初期化読み出しの検出用)
    std::string initializingName_;

    // Scope management
    struct Scope {
        std::map<std::string, TypePtr> vars;
    };

    void enterScope();
    void exitScope();
    TypePtr* lookupVar(const std::string& name);
    void declareVar(const std::string& name, TypePtr type);
    bool isDeclared(const std::string& name) const;
    bool isInitialized(const std::string& name) const;
    void markInitialized(const std::string& name);

    // Function lookup
    FunctionDecl* findFunction(const std::string& name) const;
    ConstantDecl* findConstant(const std::string& name) const;
    StructDecl* findStruct(const std::string& name) const;

    // Unsafe context tracking
    int unsafeDepth_ = 0;

    // Return type of the function currently being checked (for 歸 coercion)
    TypePtr currentReturnType_;

    // Module
    const Module& mod_;

    // Diagnostics
    std::vector<Diagnostic> diags_;
    bool hasErrors_ = false;

    // Type info (keyed by expression pointer)
    std::map<const Expr*, TypePtr> exprTypes_;
    std::map<const Expr*, TypePtr> lvalueTypes_;

    // Scope stack
    std::vector<Scope> scopes_;

    // Struct layout cache (struct name → vector of field offsets + types)
    struct StructLayout {
        std::vector<std::pair<uint64_t, TypePtr>> fields; // offset, type
        uint64_t totalSize = 0;
    };
    std::map<std::string, StructLayout> structLayouts_;

    // Initialize struct layouts from module
    void buildStructLayouts();
};

} // namespace chokanbun
