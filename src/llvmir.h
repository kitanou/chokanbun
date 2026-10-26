#pragma once
#include "ast.h"
#include "lexer.h"
#include <string>
#include <vector>
#include <map>

namespace chokanbun {

class TypeChecker;

class LLVMIRGen {
public:
    LLVMIRGen();
    ~LLVMIRGen();

    // Generate LLVM IR text for a module. The type checker supplies the
    // resolved type of every expression (used for width/signedness).
    std::string generate(const Module& mod, const TypeChecker& tc);

    const std::vector<Diagnostic>& diagnostics() const { return diags_; }
    bool hasErrors() const { return !diags_.empty(); }

private:
    // Type mapping
    std::string llvmType(const TypePtr& t);
    std::string llvmTypeRef(const TypePtr& t); // for pointers in declarations

    // Function generation
    void genFunction(const FunctionDecl& fn);
    void genExternal(const FunctionDecl& fn);
    void genAlias(const AliasDecl& a);
    void genConstant(const ConstantDecl& c);
    void genStruct(const StructDecl& s);
    void genParams(const FunctionDecl& fn);
    void genBody(const std::vector<StmtPtr>& stmts);
    void genStmt(const StmtPtr& s);
    void genLocal(const StmtPtr& s);
    void genAssign(const StmtPtr& s);
    void genCallStmt(const StmtPtr& s);
    void genIf(const StmtPtr& s);
    void genWhile(const StmtPtr& s);
    void genReturn(const StmtPtr& s);
    void genUnsafe(const StmtPtr& s);
    void genExprStmt(const StmtPtr& s);

    // Expression generation - returns the LLVM SSA value name
    std::string genExpr(const ExprPtr& e);
    std::string genIntegerLit(const ExprPtr& e);
    std::string genBoolLit(const ExprPtr& e);
    std::string genStringLit(const ExprPtr& e);
    std::string genNullLit(const ExprPtr& e);
    std::string genIdent(const ExprPtr& e);
    std::string genBinOp(const ExprPtr& e);
    std::string genUnaryOp(const ExprPtr& e);
    std::string genCall(const ExprPtr& e);
    std::string genAddrOf(const ExprPtr& e);
    std::string genDeref(const ExprPtr& e);
    std::string genCast(const ExprPtr& e);
    std::string genVolatileRead(const ExprPtr& e);
    std::string genVolatileWrite(const ExprPtr& e);
    std::string genFence(const ExprPtr& e);
    std::string genAsm(const ExprPtr& e);
    std::string genStrLen(const ExprPtr& e);
    std::string genFieldAccess(const ExprPtr& e);
    std::string genElemAccess(const ExprPtr& e);

    // Helpers
    bool endsWithTerminator() const;
    std::string freshName(const std::string& base);
    void emit(const std::string& line);
    void emitBlank();
    void error(uint32_t line, uint32_t col, const std::string& code, const std::string& msg);

    // Resolved type of an expression, from the type checker (may be null).
    TypePtr typeOfExpr(const ExprPtr& e) const;
    // Materialize an integer literal with the given LLVM type.
    std::string intLiteral(const ExprPtr& e, const TypePtr& t);
    // Fold an integer/bool/null constant expression. Returns false when the
    // expression is not a compile-time constant (or is unsupported).
    bool evalConst(const ExprPtr& e, uint64_t& out, int depth = 0) const;
    // Format a folded constant for the LLVM IR value in `constants_`.
    std::string constLiteral(const TypePtr& t, uint64_t bits) const;

    // State
    std::string ir_;
    std::vector<Diagnostic> diags_;
    int counter_ = 0;
    const TypeChecker* tc_ = nullptr;
    TypePtr currentReturnType_;
    // Local allocas are hoisted to the entry block so loops do not grow the stack.
    size_t entryInsertPos_ = 0;
    std::string entryAllocas_;

    // Current function context
    std::map<std::string, std::pair<TypePtr, std::string>> locals_; // name -> (type, ssa)
    std::map<std::string, std::pair<TypePtr, std::string>> params_; // name -> (type, ssa)
    std::map<std::string, std::pair<TypePtr, std::string>> globals_; // name -> (type, ssa)
    std::map<std::string, std::pair<TypePtr, std::string>> constants_;
    // All constant declarations, for forward references while folding.
    std::map<std::string, const ConstantDecl*> constDecls_;
    std::map<std::string, std::pair<TypePtr, std::string>> strings_; // string literal -> (type, ssa)
    std::map<std::string, std::pair<TypePtr, std::string>> structFields_; // "struct.field" -> (type, offset info)

    // Function declarations (for call resolution)
    std::map<std::string, std::shared_ptr<FunctionDecl>> functions_;
    std::map<std::string, std::shared_ptr<StructDecl>> structs_;
    std::map<std::string, std::shared_ptr<AliasDecl>> aliases_;

    // Control flow
    std::vector<std::string> ifLabels_;
    std::vector<std::string> whileLabels_;
    std::string currentBlock_ = "entry";
    int blockCounter_ = 0;

    // String literal storage
    std::vector<std::pair<std::string, std::string>> stringData_; // (name, content)
    int stringCounter_ = 0;
};

} // namespace chokanbun
