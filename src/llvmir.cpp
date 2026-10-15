#include "llvmir.h"
#include <iostream>
#include <sstream>
#include <cstring>

namespace chokanbun {

LLVMIRGen::LLVMIRGen() {
    ir_ = "; ModuleID = 'chokanbun'\n";
    ir_ += "target triple = \"aarch64-none-elf\"\n";
    ir_ += "target datalayout = \"e-m:e-i64:64-i128:128-n32:64-S128\"\n\n";
}

LLVMIRGen::~LLVMIRGen() = default;

void LLVMIRGen::emit(const std::string& line) {
    ir_ += line + "\n";
}

void LLVMIRGen::emitBlank() {
    ir_ += "\n";
}

std::string LLVMIRGen::freshName(const std::string& base) {
    return base + std::to_string(counter_++);
}

void LLVMIRGen::error(uint32_t line, uint32_t col, const std::string& code, const std::string& msg) {
    diags_.emplace_back(Diagnostic::Level::Error, line, col, code, msg);
}

std::string LLVMIRGen::llvmType(const TypePtr& t) {
    if (!t) return "void";
    switch (t->kind) {
        case Type::Kind::Bool: return "i1";
        case Type::Kind::I8: return "i8";
        case Type::Kind::I16: return "i16";
        case Type::Kind::I32: return "i32";
        case Type::Kind::I64: return "i64";
        case Type::Kind::U8: return "i8";
        case Type::Kind::U16: return "i16";
        case Type::Kind::U32: return "i32";
        case Type::Kind::U64: return "i64";
        case Type::Kind::Void: return "void";
        case Type::Kind::Pointer: return "ptr";
        case Type::Kind::Array: {
            // Arrays in LLVM are represented as [N x elem]
            return "[" + std::to_string(t->length) + " x " + llvmType(t->element) + "]";
        }
        case Type::Kind::Struct: {
            // Forward-declare or use named struct
            auto it = structs_.find(t->name);
            if (it != structs_.end() && !it->second->fields.empty()) {
                std::string s = "{ ";
                for (size_t i = 0; i < it->second->fields.size(); i++) {
                    if (i > 0) s += ", ";
                    s += llvmType(it->second->fields[i].type);
                }
                s += " }";
                return s;
            }
            return " %" + t->name; // forward reference
        }
        case Type::Kind::String: {
            // String literals are stored as byte arrays
            return "[" + std::to_string(t->length) + " x i8]";
        }
    }
    return "void";
}

std::string LLVMIRGen::llvmTypeRef(const TypePtr& t) {
    // For use in value declarations (e.g., %x = alloca ...)
    if (!t) return "i8";
    switch (t->kind) {
        case Type::Kind::Pointer: return "ptr";
        case Type::Kind::Array:
        case Type::Kind::String:
        case Type::Kind::Struct:
            return "ptr"; // alloca returns a pointer
        default:
            return llvmType(t);
    }
}

void LLVMIRGen::genFunction(const FunctionDecl& fn) {
    // Define function
    std::string retType = llvmType(fn.returnType);

    // Section attribute
    if (!fn.section.empty()) {
        // We'll add section as a module-level attribute later
    }

    std::string name = fn.name;
    if (!fn.symbolName.empty()) {
        name = fn.symbolName;
    }

    // Linkage: public (external) for 公開/main, internal otherwise
    std::string linkage = "internal";
    if (fn.isPublic || fn.name == "核主" || fn.symbolName == "main")
        linkage = "external";

    std::string define = "define ";
    if (fn.isNoreturn) define += "noreturn ";
    define += linkage + " " + retType + " @" + name + "(";
    emit(define);
    for (size_t i = 0; i < fn.params.size(); i++) {
        if (i > 0) ir_ += ", ";
        ir_ += llvmType(fn.params[i].type) + " %" + fn.params[i].name;
    }
    ir_ += ")";
    if (!fn.section.empty()) {
        ir_ += " section \"" + fn.section + "\"";
    }
    ir_ += " {\n";

    // Entry block
    emit("entry:");
    currentBlock_ = "entry";

    // Allocate locals for parameters
    for (auto& p : fn.params) {
        std::string alloca = freshName("p");
        emit("%" + alloca + " = alloca " + llvmType(p.type) + ", align 8");
        emit("store " + llvmType(p.type) + " %" + p.name + ", ptr %" + alloca);
        params_[p.name] = {p.type, alloca};
    }

    // Generate body
    genBody(fn.body);

    // If function doesn't end with a terminator, add one
    if (!endsWithTerminator()) {
        if (fn.returnType->kind == Type::Kind::Void) {
            emit("ret void");
        } else {
            emit("unreachable");
        }
    }
    // Trim trailing blank line before closing brace
    while (!ir_.empty() && ir_.back() == '\n') {
        ir_.pop_back();
        if (!ir_.empty() && ir_.back() == '\n') {
            ir_.pop_back();
            break;
        }
    }
    if (!ir_.empty()) ir_ += "\n";
    emit("}");
    emitBlank();

    // Clear local state
    locals_.clear();
    params_.clear();
}

void LLVMIRGen::genParams(const FunctionDecl& fn) {
    // Parameters are handled in genFunction
    (void)fn;
}

void LLVMIRGen::genBody(const std::vector<StmtPtr>& stmts) {
    for (auto& s : stmts) {
        genStmt(s);
    }
}

void LLVMIRGen::genStmt(const StmtPtr& s) {
    if (!s) return;
    switch (s->kind) {
        case Stmt::Kind::LocalDecl: genLocal(s); break;
        case Stmt::Kind::Assign: genAssign(s); break;
        case Stmt::Kind::CallStmt: genCallStmt(s); break;
        case Stmt::Kind::IfStmt: genIf(s); break;
        case Stmt::Kind::WhileStmt: genWhile(s); break;
        case Stmt::Kind::ReturnStmt: genReturn(s); break;
        case Stmt::Kind::UnsafeBlock: genUnsafe(s); break;
        case Stmt::Kind::ExprStmt: genExprStmt(s); break;
    }
}

void LLVMIRGen::genLocal(const StmtPtr& s) {
    std::string alloca = freshName("x");
    emit("%" + alloca + " = alloca " + llvmType(s->varType) + ", align 8");
    // Initialize
    std::string val = genExpr(s->init);
    std::string storeType = llvmType(s->varType);
    // If val is a different type (e.g., integer literal for a typed variable), we need a cast
    emit("store " + storeType + " " + val + ", ptr %" + alloca);
    locals_[s->varName] = {s->varType, alloca};
}

void LLVMIRGen::genAssign(const StmtPtr& s) {
    std::string val = genExpr(s->value);
    // Generate the lvalue as a pointer
    // For simplicity, we handle ident and deref
    if (s->target->kind == Expr::Kind::Ident) {
        auto it = locals_.find(s->target->identName);
        if (it == locals_.end()) {
            auto pit = params_.find(s->target->identName);
            if (pit != params_.end()) {
                emit("store " + llvmType(pit->second.first) + " " + val + ", ptr %" + pit->second.second);
                return;
            }
        }
        if (it != locals_.end()) {
            emit("store " + llvmType(it->second.first) + " " + val + ", ptr %" + it->second.second);
            return;
        }
    }
    // Fallback: treat as generic store
    emit("; TODO: assign to " + s->target->identName);
}

void LLVMIRGen::genCallStmt(const StmtPtr& s) {
    // 行「name」以(args)
    auto it = functions_.find(s->callee);
    if (it == functions_.end()) {
        error(s->line, s->col, "E0010", "unknown function: " + s->callee);
        return;
    }
    auto fn = it->second;

    std::string callArgs;
    for (size_t i = 0; i < s->args.size(); i++) {
        if (i > 0) callArgs += ", ";
        callArgs += genExpr(s->args[i]);
    }

    std::string symbol = fn->symbolName.empty() ? fn->name : fn->symbolName;
    if (fn->returnType->kind == Type::Kind::Void) {
        emit("call void @" + symbol + "(" + callArgs + ")");
    } else {
        std::string ret = freshName("r");
        emit("%" + ret + " = call " + llvmType(fn->returnType) + " @" + symbol + "(" + callArgs + ")");
    }
}

void LLVMIRGen::genIf(const StmtPtr& s) {
    std::string cond = genExpr(s->cond);
    // cond is i1
    std::string thenLabel = "if.then." + std::to_string(blockCounter_);
    std::string elseLabel = "if.else." + std::to_string(blockCounter_);
    std::string mergeLabel = "if.merge." + std::to_string(blockCounter_);
    blockCounter_++;

    emit("br i1 " + cond + ", label %" + thenLabel + ", label %" + elseLabel);
    emit(thenLabel + ":");
    currentBlock_ = thenLabel;
    genBody(s->thenBlock);
    emit("br label %" + mergeLabel);

    if (s->hasElse) {
        emit(elseLabel + ":");
        currentBlock_ = elseLabel;
        genBody(s->elseBlock);
        emit("br label %" + mergeLabel);
    }

    emit(mergeLabel + ":");
    currentBlock_ = mergeLabel;
}

void LLVMIRGen::genWhile(const StmtPtr& s) {
    std::string condLabel = "while.cond." + std::to_string(blockCounter_);
    std::string bodyLabel = "while.body." + std::to_string(blockCounter_);
    std::string endLabel = "while.end." + std::to_string(blockCounter_);
    blockCounter_++;

    emit("br label %" + condLabel);
    emit(condLabel + ":");
    currentBlock_ = condLabel;
    std::string cond = genExpr(s->cond);
    emit("br i1 " + cond + ", label %" + bodyLabel + ", label %" + endLabel);
    emit(bodyLabel + ":");
    currentBlock_ = bodyLabel;
    genBody(s->body);
    emit("br label %" + condLabel);
    emit(endLabel + ":");
    currentBlock_ = endLabel;
}

void LLVMIRGen::genReturn(const StmtPtr& s) {
    if (s->hasRetVal && s->retVal) {
        std::string val = genExpr(s->retVal);
        // Get the return type from context
        // For now, just emit ret
        emit("ret " + val);
    } else {
        emit("ret void");
    }
}

void LLVMIRGen::genUnsafe(const StmtPtr& s) {
    // Unsafe block: just generate the statements
    // (In a full implementation, we'd track unsafe context for type checking)
    genBody(s->unsafeBody);
}

void LLVMIRGen::genExprStmt(const StmtPtr& s) {
    if (s->expr) {
        genExpr(s->expr);
    }
}

std::string LLVMIRGen::genExpr(const ExprPtr& e) {
    if (!e) return "i8 0";
    switch (e->kind) {
        case Expr::Kind::IntegerLit: return genIntegerLit(e);
        case Expr::Kind::BoolLit: return genBoolLit(e);
        case Expr::Kind::StringLit: return genStringLit(e);
        case Expr::Kind::NullLit: return genNullLit(e);
        case Expr::Kind::Ident: return genIdent(e);
        case Expr::Kind::BinOp: return genBinOp(e);
        case Expr::Kind::UnaryOp: return genUnaryOp(e);
        case Expr::Kind::Call: return genCall(e);
        case Expr::Kind::AddrOf: return genAddrOf(e);
        case Expr::Kind::Deref: return genDeref(e);
        case Expr::Kind::Cast: return genCast(e);
        case Expr::Kind::VolatileRead: return genVolatileRead(e);
        case Expr::Kind::VolatileWrite: return genVolatileWrite(e);
        case Expr::Kind::Fence: return genFence(e);
        case Expr::Kind::StrLen: return genStrLen(e);
        case Expr::Kind::FieldAccess: return genFieldAccess(e);
        case Expr::Kind::ElemAccess: return genElemAccess(e);
    }
    return "i8 0";
}

std::string LLVMIRGen::genIntegerLit(const ExprPtr& e) {
    // The type is determined by context; for now, assume i64
    // In a full implementation, we'd have type information on the expression
    if (e->isNegative) {
        return "i64 -" + std::to_string(e->intValue);
    }
    return "i64 " + std::to_string(e->intValue);
}

std::string LLVMIRGen::genBoolLit(const ExprPtr& e) {
    return e->boolValue ? "i1 true" : "i1 false";
}

std::string LLVMIRGen::genStringLit(const ExprPtr& e) {
    // String literals are stored as global byte arrays
    // Deduplicate: check if we've already emitted this string
    auto it = strings_.find(e->strValue);
    if (it != strings_.end()) {
        return "ptr @" + it->second.second;
    }

    std::string name = "str." + std::to_string(stringCounter_++);
    stringData_.push_back({name, e->strValue});
    strings_[e->strValue] = {TypePtr(), name};

    return "ptr @" + name;
}

std::string LLVMIRGen::genNullLit(const ExprPtr& e) {
    (void)e;
    return "ptr null";
}

std::string LLVMIRGen::genIdent(const ExprPtr& e) {
    // Look up in locals, params, globals, constants
    auto it = locals_.find(e->identName);
    if (it != locals_.end()) {
        // Load from alloca
        std::string val = freshName("v");
        emit("%" + val + " = load " + llvmType(it->second.first) + ", ptr %" + it->second.second);
        return llvmType(it->second.first) + " %" + val;
    }
    it = params_.find(e->identName);
    if (it != params_.end()) {
        std::string val = freshName("v");
        emit("%" + val + " = load " + llvmType(it->second.first) + ", ptr %" + it->second.second);
        return llvmType(it->second.first) + " %" + val;
    }
    it = constants_.find(e->identName);
    if (it != constants_.end()) {
        return llvmType(it->second.first) + " " + it->second.second;
    }
    // Unknown identifier - error
    error(e->line, e->col, "E0003", "undeclared identifier: " + e->identName);
    return "i64 0";
}

std::string LLVMIRGen::genBinOp(const ExprPtr& e) {
    std::string left = genExpr(e->left);
    std::string right = genExpr(e->right);

    // Determine the type from the left operand
    std::string leftType = left.substr(0, left.find(' '));
    bool isSigned = false;
    // Check if the left operand's type is signed
    if (leftType == "i8" || leftType == "i16" || leftType == "i32" || leftType == "i64") {
        // We need to know if it's signed or unsigned; default to signed for now
        // A full type checker would provide this
        isSigned = true;
    }

    std::string op;
    if (e->opText == "加") op = "add";
    else if (e->opText == "減") op = "sub";
    else if (e->opText == "乘") op = "mul";
    else if (e->opText == "除") op = isSigned ? "sdiv" : "udiv";
    else if (e->opText == "餘") op = isSigned ? "srem" : "urem";
    else if (e->opText == "左移") op = "shl";
    else if (e->opText == "右移") op = isSigned ? "ashr" : "lshr";
    else if (e->opText == "小於") op = isSigned ? "icmp slt" : "icmp ult";
    else if (e->opText == "小等") op = isSigned ? "icmp sle" : "icmp ule";
    else if (e->opText == "大於") op = isSigned ? "icmp sgt" : "icmp ugt";
    else if (e->opText == "大等") op = isSigned ? "icmp sge" : "icmp uge";
    else if (e->opText == "等於") op = "icmp eq";
    else if (e->opText == "不等") op = "icmp ne";
    else if (e->opText == "位與") op = "and";
    else if (e->opText == "位異") op = "xor";
    else if (e->opText == "位或") op = "or";
    else if (e->opText == "且") op = "and"; // logical and (short-circuit)
    else if (e->opText == "或") op = "or";  // logical or (short-circuit)
    else {
        error(e->line, e->col, "E0005", "unknown operator: " + e->opText);
        return "i64 0";
    }

    // For comparison operators, the result is i1
    if (op.find("icmp") == 0) {
        std::string result = freshName("cmp");
        emit("%" + result + " = " + op + " " + left + ", " + right);
        return "i1 %" + result;
    }

    // For logical and/or, we need short-circuit evaluation
    if (op == "and" && e->opText == "且") {
        // Simplified: just do bitwise and for now
        std::string result = freshName("and");
        emit("%" + result + " = and " + left + ", " + right);
        return left.substr(0, left.find(' ')) + " %" + result;
    }
    if (op == "or" && e->opText == "或") {
        std::string result = freshName("or");
        emit("%" + result + " = or " + left + ", " + right);
        return left.substr(0, left.find(' ')) + " %" + result;
    }

    std::string result = freshName("r");
    std::string type = left.substr(0, left.find(' '));
    emit("%" + result + " = " + op + " " + left + ", " + right);
    return type + " %" + result;
}

std::string LLVMIRGen::genUnaryOp(const ExprPtr& e) {
    std::string operand = genExpr(e->operand);
    if (e->unaryOp == "負") {
        std::string result = freshName("neg");
        // Determine if signed or unsigned
        // For now, use neg (which works for both in LLVM)
        emit("%" + result + " = neg " + operand);
        return operand.substr(0, operand.find(' ')) + " %" + result;
    }
    if (e->unaryOp == "非") {
        std::string result = freshName("not");
        emit("%" + result + " = xor i1 " + operand + ", true");
        return "i1 %" + result;
    }
    if (e->unaryOp == "位非") {
        std::string result = freshName("bnot");
        emit("%" + result + " = xor " + operand + ", -1");
        return operand.substr(0, operand.find(' ')) + " %" + result;
    }
    error(e->line, e->col, "E0005", "unknown unary operator: " + e->unaryOp);
    return "i64 0";
}

std::string LLVMIRGen::genCall(const ExprPtr& e) {
    auto it = functions_.find(e->callee);
    if (it == functions_.end()) {
        error(e->line, e->col, "E0010", "unknown function: " + e->callee);
        return "i64 0";
    }
    auto fn = it->second;

    std::string callArgs;
    for (size_t i = 0; i < e->args.size() && i < fn->params.size(); i++) {
        if (i > 0) callArgs += ", ";
        callArgs += genExpr(e->args[i]);
    }

    std::string symbol = fn->symbolName.empty() ? fn->name : fn->symbolName;
    std::string ret = freshName("call");
    if (fn->returnType->kind == Type::Kind::Void) {
        emit("call void @" + symbol + "(" + callArgs + ")");
        return "void ";
    } else {
        emit("%" + ret + " = call " + llvmType(fn->returnType) + " @" + symbol + "(" + callArgs + ")");
        return llvmType(fn->returnType) + " %" + ret;
    }
}

std::string LLVMIRGen::genAddrOf(const ExprPtr& e) {
    // 取址(lvalue) - returns a pointer to the lvalue
    if (e->addend->kind == Expr::Kind::Ident) {
        auto it = locals_.find(e->addend->identName);
        if (it != locals_.end()) {
            return "ptr %" + it->second.second;
        }
        it = params_.find(e->addend->identName);
        if (it != params_.end()) {
            return "ptr %" + it->second.second;
        }
    }
    // 取址(『...』) - address of string literal (spec §9)
    if (e->addend->kind == Expr::Kind::StringLit) {
        std::string name = genStringLit(e->addend);
        return "ptr @" + name;
    }
    error(e->line, e->col, "E0006", "cannot take address of non-lvalue");
    return "ptr null";
}

std::string LLVMIRGen::genDeref(const ExprPtr& e) {
    std::string ptr = genExpr(e->pointee);
    std::string result = freshName("deref");
    // We need the pointee type; for now, assume i64
    // In a full implementation, we'd get this from type checking
    emit("%" + result + " = load i64, ptr " + ptr);
    return "i64 %" + result;
}

std::string LLVMIRGen::genCast(const ExprPtr& e) {
    std::string from = genExpr(e->castFrom);
    std::string toType = llvmType(e->castTo);
    std::string fromType = from.substr(0, from.find(' '));

    std::string result = freshName("cast");
    // Determine cast kind
    if (fromType == "i8" && toType == "i64") {
        // sign extend or zext
        emit("%" + result + " = zext i8 " + from + " to i64");
    } else if (fromType == "i16" && toType == "i64") {
        emit("%" + result + " = zext i16 " + from + " to i64");
    } else if (fromType == "i32" && toType == "i64") {
        emit("%" + result + " = zext i32 " + from + " to i64");
    } else if (fromType == "i64" && toType == "i32") {
        emit("%" + result + " = trunc i64 " + from + " to i32");
    } else if (fromType == "i64" && toType == "i16") {
        emit("%" + result + " = trunc i64 " + from + " to i16");
    } else if (fromType == "i64" && toType == "i8") {
        emit("%" + result + " = trunc i64 " + from + " to i8");
    } else if (fromType == "i1" && toType == "i64") {
        emit("%" + result + " = zext i1 " + from + " to i64");
    } else if (fromType == "i64" && toType == "i1") {
        emit("%" + result + " = icmp ne i64 " + from + ", 0");
    } else {
        // Default: just emit as-is (may be wrong)
        emit("%" + result + " = bitcast " + from + " to " + toType);
    }
    return toType + " %" + result;
}

std::string LLVMIRGen::genVolatileRead(const ExprPtr& e) {
    std::string ptr = genExpr(e->volPtr);
    std::string type = llvmType(e->volType);
    std::string result = freshName("vol");
    emit("%" + result + " = load volatile " + type + ", ptr " + ptr);
    return type + " %" + result;
}

std::string LLVMIRGen::genVolatileWrite(const ExprPtr& e) {
    std::string ptr = genExpr(e->volPtr);
    std::string val = genExpr(e->volVal);
    std::string type = llvmType(e->volType);
    emit("store volatile " + type + " " + val + ", ptr " + ptr);
    return "void ";
}

std::string LLVMIRGen::genFence(const ExprPtr& e) {
    // 障壁〈kind〉()
    std::string order;
    if (e->fenceKind == "シーケンス") order = "seq_cst";
    else if (e->fenceKind == "_acquire") order = "acquire";
    else if (e->fenceKind == "リリース") order = "release";
    else if (e->fenceKind == "読み書き") order = "acq_rel";
    else order = "seq_cst";
    emit("fence " + order);
    return "void ";
}

std::string LLVMIRGen::genStrLen(const ExprPtr& e) {
    // 長度(expr) - for strings, returns the length as a compile-time constant
    // Handles: 長度(『...』), 長度(取址(『...』)), 長度(ptr to string)
    const Expr* target = e->index.get();
    if (!target) {
        error(e->line, e->col, "E0007", "長度 requires an argument");
        return "i64 0";
    }
    // Unwrap 取址
    if (target->kind == Expr::Kind::AddrOf && target->addend) {
        target = target->addend.get();
    }
    if (target->kind == Expr::Kind::StringLit) {
        return "i64 " + std::to_string(target->strValue.size());
    }
    error(e->line, e->col, "E0007", "長度 requires a string literal");
    return "i64 0";
}

std::string LLVMIRGen::genFieldAccess(const ExprPtr& e) {
    // 欄(base, 「field」)
    // For now, we'll generate a GEP
    std::string base = genExpr(e->base);
    std::string result = freshName("field");
    // This is a simplification; proper struct layout is needed
    emit("%" + result + " = getelementptr i8, ptr " + base + ", i64 0");
    return "i64 %" + result;
}

std::string LLVMIRGen::genElemAccess(const ExprPtr& e) {
    // 項(base, index)
    std::string base = genExpr(e->base);
    std::string index = genExpr(e->index);
    std::string result = freshName("elem");
    emit("%" + result + " = getelementptr i8, ptr " + base + ", i64 " + index);
    return "i64 %" + result;
}

std::string LLVMIRGen::generate(const Module& mod) {
    // First pass: collect all declarations
    for (auto& d : mod.decls) {
        switch (d.kind) {
            case Decl::Kind::Function:
                if (d.function) {
                    bool isPublic = d.function->isPublic;
                    bool isMain = (d.function->symbolName == "main" || d.function->name == "核主");
                    if (isPublic || isMain) {
                        // emit declaration
                    }
                }
                break;
            default:
                break;
        }
    }
    // Second pass: emit definitions
    for (auto& d : mod.decls) {
        switch (d.kind) {
            case Decl::Kind::Function:
                // 外術曰 declarations are emitted as declare, not define
                if (d.function && d.function->isExternal) genExternal(*d.function);
                else if (d.function) genFunction(*d.function);
                break;
            case Decl::Kind::Alias:
                if (d.alias) genAlias(*d.alias);
                break;
            case Decl::Kind::Constant:
                if (d.constant) genConstant(*d.constant);
                break;
            case Decl::Kind::Struct:
                if (d.structDecl) genStruct(*d.structDecl);
                break;
        }
    }
    return ir_;
}

bool LLVMIRGen::endsWithTerminator() const {
    if (ir_.empty()) return false;
    // Find last non-empty line
    std::string s = ir_;
    auto pos = s.size();
    while (pos > 0 && s[pos-1] == '\n') pos--;
    if (pos == 0) return false;
    auto start = s.rfind('\n', pos - 1) + 1;
    std::string line = s.substr(start, pos - start);
    // Check for terminator instructions
    if (line.find("ret ") == 0 || line.find("br ") == 0 ||
        line.find("unreachable") == 0 || line.find("switch ") == 0) {
        return true;
    }
    return false;
}

} // namespace chokanbun
