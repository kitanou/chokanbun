#pragma once
#include "ast.h"
#include "lexer.h"
#include <string>
#include <vector>
#include <map>

namespace chokanbun {

class LLVMIRGen {
public:
    LLVMIRGen();
    ~LLVMIRGen();

    // Generate LLVM IR text for a module
    std::string generate(const Module& mod);

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
    std::string genStrLen(const ExprPtr& e);
    std::string genFieldAccess(const ExprPtr& e);
    std::string genElemAccess(const ExprPtr& e);

    // Helpers
    bool endsWithTerminator() const;
    std::string freshName(const std::string& base);
    void emit(const std::string& line);
    void emitBlank();
    void error(uint32_t line, uint32_t col, const std::string& code, const std::string& msg);

    // State
    std::string ir_;
    std::vector<Diagnostic> diags_;
    int counter_ = 0;

    // Current function context
    std::map<std::string, std::pair<TypePtr, std::string>> locals_; // name -> (type, ssa)
    std::map<std::string, std::pair<TypePtr, std::string>> params_; // name -> (type, ssa)
    std::map<std::string, std::pair<TypePtr, std::string>> globals_; // name -> (type, ssa)
    std::map<std::string, std::pair<TypePtr, std::string>> constants_;
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
