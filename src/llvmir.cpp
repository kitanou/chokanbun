#include "llvmir.h"
#include "typecheck.h"
#include <iostream>
#include <sstream>
#include <cstring>
#include <cctype>
#include <cstdint>
#include <limits>

namespace chokanbun {

// LLVM unquoted identifiers are limited to [-a-zA-Z$._0-9]. Anything else
// (e.g. CJK) must be emitted as @"..." . The ELF symbol keeps the raw bytes.
static bool irNeedsQuote(const std::string& s) {
    if (s.empty()) return true;
    for (unsigned char c : s) {
        if (!(std::isalnum(c) || c == '_' || c == '.' || c == '$')) return true;
    }
    return false;
}

static std::string irName(const std::string& s) {
    if (irNeedsQuote(s)) return "@\"" + s + "\"";
    return "@" + s;
}

// The ELF symbol for a function: 記號「...」 if present, else "main" for 核主,
// otherwise the language-level name.
static std::string fnSymbol(const FunctionDecl& fn) {
    if (!fn.symbolName.empty()) return fn.symbolName;
    if (fn.name == "核主") return "main";
    return fn.name;
}

// LLVM 23 dropped the redundant type on the right-hand operand of binary
// instructions (e.g. `add i64 %a, 1`). Strip the type from a value string.
static std::string valueOnly(const std::string& v) {
    auto p = v.find(' ');
    return p == std::string::npos ? v : v.substr(p + 1);
}

// Integer-constant helpers. A constant is kept as its low `bits` bits; signed
// formatting/division sign-extends it from the declared integer width.
static uint64_t intMask(unsigned bits) {
    return bits >= 64 ? ~uint64_t(0) : ((uint64_t(1) << bits) - 1);
}

static unsigned intBits(const TypePtr& t) {
    if (!t || !t->isInteger()) return 64;
    unsigned bits = static_cast<unsigned>(t->sizeBytes() * 8);
    return bits == 0 ? 64 : bits;
}

static uint64_t truncBits(uint64_t v, const TypePtr& t) {
    return v & intMask(intBits(t));
}

static int64_t signExtendBits(uint64_t v, unsigned bits) {
    v &= intMask(bits);
    if (bits >= 64) return static_cast<int64_t>(v);
    uint64_t sign = uint64_t(1) << (bits - 1);
    return static_cast<int64_t>((v ^ sign) - sign);
}

static std::string escapeIrBytes(const std::string& s) {
    std::string out;
    for (unsigned char c : s) {
        if (c == '"' || c == '\\') {
            out += '\\';
            out += static_cast<char>(c);
        } else if (c >= 0x20 && c < 0x7f) {
            out += static_cast<char>(c);
        } else {
            static const char* hex = "0123456789ABCDEF";
            out += '\\';
            out += hex[(c >> 4) & 0xF];
            out += hex[c & 0xF];
        }
    }
    return out;
}

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

TypePtr LLVMIRGen::typeOfExpr(const ExprPtr& e) const {
    if (!tc_ || !e) return nullptr;
    return tc_->exprType(*e);
}

std::string LLVMIRGen::intLiteral(const ExprPtr& e, const TypePtr& t) {
    std::string ty = (t && t->isInteger()) ? llvmType(t) : "i64";
    std::string v = std::to_string(e->intValue);
    if (e->isNegative) v = "-" + v;
    return ty + " " + v;
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

    std::string name = fnSymbol(fn);

    // Linkage: public (external) for 公開/main, internal otherwise
    std::string linkage = "internal";
    if (fn.isPublic || name == "main")
        linkage = "dso_local";

    std::string define = "define ";
    if (fn.isNoreturn) define += "noreturn ";
    define += linkage + " " + retType + " " + irName(name) + "(";
    emit(define);
    for (size_t i = 0; i < fn.params.size(); i++) {
        if (i > 0) ir_ += ", ";
        ir_ += llvmType(fn.params[i].type) + " %arg" + std::to_string(i);
    }
    ir_ += ")";
    if (fn.isNaked) ir_ += " naked noinline nounwind";
    if (!fn.section.empty()) {
        ir_ += " section \"" + fn.section + "\"";
    }
    if (fn.alignment) ir_ += " align " + std::to_string(fn.alignment);
    ir_ += " {\n";

    // Entry block
    emit("entry:");
    currentBlock_ = "entry";

    // Allocate locals for parameters (params are passed as %argN).
    // 裸の関数は棧を使わないので、引数は退避しない (レジスタのまま組譯が読む)。
    for (size_t i = 0; i < fn.params.size() && !fn.isNaked; i++) {
        auto& p = fn.params[i];
        std::string alloca = freshName("p");
        emit("%" + alloca + " = alloca " + llvmType(p.type) + ", align 8");
        emit("store " + llvmType(p.type) + " %arg" + std::to_string(i) + ", ptr %" + alloca);
        params_[p.name] = {p.type, alloca};
    }

    entryInsertPos_ = ir_.size();
    entryAllocas_.clear();

    // Generate body
    TypePtr savedReturn = currentReturnType_;
    currentReturnType_ = fn.returnType;
    genBody(fn.body);
    currentReturnType_ = savedReturn;

    // If function doesn't end with a terminator, add one
    if (!endsWithTerminator()) {
        if (fn.isNaked) {
            emit("unreachable");
        } else if (fn.returnType->kind == Type::Kind::Void) {
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
    ir_.insert(entryInsertPos_, entryAllocas_);
    entryAllocas_.clear();
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
    entryAllocas_ += "%" + alloca + " = alloca " + llvmType(s->varType) + ", align 8\n";
    // Initialize
    std::string val = genExpr(s->init);
    // `val` already carries its LLVM type (e.g. "i64 5").
    emit("store " + val + ", ptr %" + alloca);
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
                emit("store " + val + ", ptr %" + pit->second.second);
                return;
            }
        }
        if (it != locals_.end()) {
            emit("store " + val + ", ptr %" + it->second.second);
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

    std::string symbol = fnSymbol(*fn);
    if (fn->returnType->kind == Type::Kind::Void) {
        emit("call void " + irName(symbol) + "(" + callArgs + ")");
    } else {
        std::string ret = freshName("r");
        emit("%" + ret + " = call " + llvmType(fn->returnType) + " " + irName(symbol) + "(" + callArgs + ")");
    }
}

void LLVMIRGen::genIf(const StmtPtr& s) {
    std::string cond = genExpr(s->cond);
    // cond is i1
    std::string thenLabel = "if.then." + std::to_string(blockCounter_);
    std::string elseLabel = "if.else." + std::to_string(blockCounter_);
    std::string mergeLabel = "if.merge." + std::to_string(blockCounter_);
    blockCounter_++;

    emit("br " + cond + ", label %" + thenLabel + ", label %" + elseLabel);
    emit(thenLabel + ":");
    currentBlock_ = thenLabel;
    genBody(s->thenBlock);
    emit("br label %" + mergeLabel);

    emit(elseLabel + ":");
    currentBlock_ = elseLabel;
    if (s->hasElse) {
        genBody(s->elseBlock);
    }
    emit("br label %" + mergeLabel);

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
    emit("br " + cond + ", label %" + bodyLabel + ", label %" + endLabel);
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
        case Expr::Kind::Asm: return genAsm(e);
        case Expr::Kind::Machine: return genMachine(e);
        case Expr::Kind::StrLen: return genStrLen(e);
        case Expr::Kind::FieldAccess: return genFieldAccess(e);
        case Expr::Kind::ElemAccess: return genElemAccess(e);
    }
    return "i8 0";
}

std::string LLVMIRGen::genIntegerLit(const ExprPtr& e) {
    // Width/type comes from the type checker (literals are coerced to the
    // expected integer type); fall back to i64 when unknown.
    return intLiteral(e, typeOfExpr(e));
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
    TypePtr lt = typeOfExpr(e->left);
    TypePtr rt = typeOfExpr(e->right);
    bool lLit = e->left && e->left->kind == Expr::Kind::IntegerLit;
    bool rLit = e->right && e->right->kind == Expr::Kind::IntegerLit;

    // Materialize the operands with a common integer type, letting an untyped
    // literal adopt the other operand's type.
    std::string left, right;
    if (lLit && rt && rt->isInteger()) {
        right = genExpr(e->right);
        left = intLiteral(e->left, rt);
        lt = rt;
    } else if (rLit && lt && lt->isInteger()) {
        left = genExpr(e->left);
        right = intLiteral(e->right, lt);
        rt = lt;
    } else {
        left = genExpr(e->left);
        right = genExpr(e->right);
    }

    bool isSigned = lt && lt->isSigned();

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
        emit("%" + result + " = " + op + " " + left + ", " + valueOnly(right));
        return "i1 %" + result;
    }

    // For logical and/or, we need short-circuit evaluation
    if (op == "and" && e->opText == "且") {
        // Simplified: just do bitwise and for now
        std::string result = freshName("and");
        emit("%" + result + " = and " + left + ", " + valueOnly(right));
        return left.substr(0, left.find(' ')) + " %" + result;
    }
    if (op == "or" && e->opText == "或") {
        std::string result = freshName("or");
        emit("%" + result + " = or " + left + ", " + valueOnly(right));
        return left.substr(0, left.find(' ')) + " %" + result;
    }

    std::string result = freshName("r");
    std::string type = left.substr(0, left.find(' '));
    emit("%" + result + " = " + op + " " + left + ", " + valueOnly(right));
    return type + " %" + result;
}

std::string LLVMIRGen::genUnaryOp(const ExprPtr& e) {
    std::string operand = genExpr(e->operand);
    if (e->unaryOp == "負") {
        std::string result = freshName("neg");
        // LLVM has no `neg` instruction. Negation is 0 - operand.
        std::string type = operand.substr(0, operand.find(' '));
        emit("%" + result + " = sub " + type + " 0, " + valueOnly(operand));
        return type + " %" + result;
    }
    if (e->unaryOp == "非") {
        std::string result = freshName("not");
        emit("%" + result + " = xor " + operand + ", true");
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

    std::string symbol = fnSymbol(*fn);
    std::string ret = freshName("call");
    if (fn->returnType->kind == Type::Kind::Void) {
        emit("call void " + irName(symbol) + "(" + callArgs + ")");
        return "void ";
    } else {
        emit("%" + ret + " = call " + llvmType(fn->returnType) + " " + irName(symbol) + "(" + callArgs + ")");
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
    // 取址(術名) - address of a function / linker symbol, as 無符六四
    if (e->addend->kind == Expr::Kind::Ident) {
        auto fit = functions_.find(e->addend->identName);
        if (fit != functions_.end()) {
            std::string result = freshName("faddr");
            emit("%" + result + " = ptrtoint ptr " + irName(fnSymbol(*fit->second)) + " to i64");
            return "i64 %" + result;
        }
    }
    // 取址(『...』) - address of string literal (spec §9)
    if (e->addend->kind == Expr::Kind::StringLit) {
        return genStringLit(e->addend);
    }
    error(e->line, e->col, "E0006", "cannot take address of non-lvalue");
    return "ptr null";
}

std::string LLVMIRGen::genDeref(const ExprPtr& e) {
    std::string ptr = genExpr(e->pointee);
    TypePtr pt = typeOfExpr(e->pointee);
    TypePtr elemT = (pt && pt->kind == Type::Kind::Pointer && pt->pointee) ? pt->pointee : Type::I64();
    std::string elemLLVM = llvmType(elemT);
    std::string result = freshName("deref");
    emit("%" + result + " = load " + elemLLVM + ", " + ptr);
    return elemLLVM + " %" + result;
}

std::string LLVMIRGen::genCast(const ExprPtr& e) {
    std::string from = genExpr(e->castFrom);
    TypePtr fromT = typeOfExpr(e->castFrom);
    TypePtr toT = e->castTo;
    if (!toT) return from;

    std::string toType = llvmType(toT);
    std::string fromType = from.substr(0, from.find(' '));

    // No-op if the LLVM repr is unchanged (covers ptr<->ptr with opaque ptrs).
    if (fromType == toType) return from;

    std::string result = freshName("cast");

    if (fromT && fromT->isInteger() && toT->isInteger()) {
        uint64_t fs = fromT->sizeBytes();
        uint64_t ts = toT->sizeBytes();
        if (fs == ts) {
            return from; // same width, just reinterpret the type
        }
        if (fs < ts) {
            std::string ext = fromT->isSigned() ? "sext" : "zext";
            emit("%" + result + " = " + ext + " " + from + " to " + toType);
        } else {
            emit("%" + result + " = trunc " + from + " to " + toType);
        }
    } else if (fromT && fromT->isInteger() && toT->kind == Type::Kind::Pointer) {
        emit("%" + result + " = inttoptr " + from + " to " + toType);
    } else if (fromT && fromT->kind == Type::Kind::Pointer && toT->isInteger()) {
        emit("%" + result + " = ptrtoint " + from + " to " + toType);
    } else if (fromType == "i1" && toT->isInteger()) {
        emit("%" + result + " = zext " + from + " to " + toType);
    } else {
        emit("%" + result + " = bitcast " + from + " to " + toType);
    }
    return toType + " %" + result;
}

std::string LLVMIRGen::genVolatileRead(const ExprPtr& e) {
    std::string ptr = genExpr(e->volPtr);
    std::string type = llvmType(e->volType);
    std::string result = freshName("vol");
    emit("%" + result + " = load volatile " + type + ", " + ptr);
    return type + " %" + result;
}

std::string LLVMIRGen::genVolatileWrite(const ExprPtr& e) {
    std::string ptr = genExpr(e->volPtr);
    std::string val = genExpr(e->volVal);
    emit("store volatile " + val + ", " + ptr);
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

// LLVM IR の文字列定数用の逃がし ("..." の中身)。
static std::string irEscape(const std::string& s) {
    static const char* hex = "0123456789ABCDEF";
    std::string out;
    for (unsigned char c : s) {
        if (c < 0x20 || c == '"' || c == '\\' || c >= 0x7F) {
            out += '\\';
            out += hex[c >> 4];
            out += hex[c & 15];
        } else {
            out += static_cast<char>(c);
        }
    }
    return out;
}

std::string LLVMIRGen::genAsm(const ExprPtr& e) {
    // 組譯〈T〉(『文』, 『制約』, 引...) -> call asm sideeffect
    std::string args;
    for (size_t i = 0; i < e->args.size(); i++) {
        if (i > 0) args += ", ";
        args += genExpr(e->args[i]);
    }
    std::string text = "asm sideeffect \"" + irEscape(e->asmText) + "\", \"" +
        irEscape(e->asmConstraints) + "\"(" + args + ")";
    if (!e->asmType || e->asmType->kind == Type::Kind::Void) {
        emit("call void " + text);
        return "void ";
    }
    std::string ty = llvmType(e->asmType);
    std::string result = freshName("asm");
    emit("%" + result + " = call " + ty + " " + text);
    return ty + " %" + result;
}

// 例外の框の退避 (save) / 復帰 (!save) の命令列。x0..x30 は +0..+240、
// el1irq は +248 に NZCV、el0 はさらに ELR_EL1 +256・SPSR_EL1 +264・SP_EL0 +272 (docs/abi-aarch64.md)。
// 退避の途中で x2 を作業用に使う (x0..x30 を保存した後なので壊してよい)。
static std::string frameAsm(const std::string& kind, bool save) {
    bool el0 = kind == "el0";
    bool nzcv = el0 || kind == "el1irq";
    int size = el0 ? 288 : 256;
    std::string s;
    auto line = [&](const std::string& t) { s += t + "\n"; };
    auto sysSave = [&](const char* reg, int off) {
        line(std::string("mrs x2, ") + reg);
        line("str x2, [sp, #" + std::to_string(off) + "]");
    };
    auto sysLoad = [&](const char* reg, int off) {
        line("ldr x2, [sp, #" + std::to_string(off) + "]");
        line(std::string("msr ") + reg + ", x2");
    };
    if (save) {
        line("sub sp, sp, #" + std::to_string(size));
        for (int r = 0; r < 30; r += 2)
            line("stp x" + std::to_string(r) + ", x" + std::to_string(r + 1) +
                 ", [sp, #" + std::to_string(r * 8) + "]");
        line("str x30, [sp, #240]");
        if (nzcv) sysSave("nzcv", 248);
        if (el0) {
            sysSave("elr_el1", 256);
            sysSave("spsr_el1", 264);
            sysSave("sp_el0", 272);
        }
    } else {
        if (nzcv) sysLoad("nzcv", 248);
        if (el0) {
            sysLoad("elr_el1", 256);
            sysLoad("spsr_el1", 264);
            sysLoad("sp_el0", 272);
        }
        line("ldr x30, [sp, #240]");
        for (int r = 28; r >= 0; r -= 2)
            line("ldp x" + std::to_string(r) + ", x" + std::to_string(r + 1) +
                 ", [sp, #" + std::to_string(r * 8) + "]");
        line("add sp, sp, #" + std::to_string(size));
    }
    if (!s.empty()) s.pop_back();
    return s;
}

std::string LLVMIRGen::genMachine(const ExprPtr& e) {
    // 型付き機械命令 -> コンパイラが生成した inline asm。ソースには asm 文を書かない。
    auto callVoid = [&](const std::string& text, const std::string& constraints,
                        const std::string& operands = "") {
        emit("call void asm sideeffect \"" + irEscape(text) + "\", \"" +
             irEscape(constraints) + "\"(" + operands + ")");
        return std::string("void ");
    };
    auto callI64 = [&](const std::string& text, const std::string& constraints,
                       const std::string& operands = "") {
        std::string result = freshName("mach");
        emit("%" + result + " = call i64 asm sideeffect \"" + irEscape(text) + "\", \"" +
             irEscape(constraints) + "\"(" + operands + ")");
        return "i64 %" + result;
    };

    switch (e->machineOp) {
        case Expr::MachineOp::SysRegRead:
            return callI64("mrs $0, " + e->asmText, "=r");

        case Expr::MachineOp::SysRegWrite: {
            if (e->args.empty()) return "void ";
            if (e->asmText == "daifset" || e->asmText == "daifclr") {
                uint64_t imm = e->args[0]->intValue & 0xF;
                return callVoid("msr " + e->asmText + ", #" + std::to_string(imm), "~{memory}");
            }
            std::string val = genExpr(e->args[0]);
            return callVoid("msr " + e->asmText + ", $0", "r,~{memory}", val);
        }

        case Expr::MachineOp::MemBarrier:
            return callVoid("dsb " + e->asmText, "~{memory}");

        case Expr::MachineOp::InstrBarrier:
            return callVoid("isb", "~{memory}");

        case Expr::MachineOp::TlbInvalidate:
            return callVoid("tlbi " + e->asmText, "~{memory}");

        case Expr::MachineOp::DataCacheClean: {
            if (e->args.empty()) return "void ";
            std::string addr = genExpr(e->args[0]);
            return callVoid("dc cvau, $0", "r,~{memory}", addr);
        }

        case Expr::MachineOp::InstrCacheClean:
            return callVoid("ic iallu", "~{memory}");

        case Expr::MachineOp::WaitEvent:
            return callVoid("wfi", "~{memory}");

        case Expr::MachineOp::Syscall: {
            // 漢令 ABI v0.1: x0..x5 = 引数, x8 = 番号, 戻り値 x0。
            if (e->args.empty()) return "i64 0";
            // 引数はソースの左から右の順に評価する (番号が先、次に 引0..引5)。
            std::vector<std::string> vals;
            vals.reserve(e->args.size());
            for (auto& a : e->args) vals.push_back(genExpr(a));
            std::string operands;
            for (int i = 0; i < 6; i++) {
                if (i > 0) operands += ", ";
                operands += (i + 1 < static_cast<int>(vals.size())) ? vals[i + 1] : "i64 0";
            }
            operands += ", " + vals[0];
            return callI64("svc #0",
                "={x0},{x0},{x1},{x2},{x3},{x4},{x5},{x8},~{memory}", operands);
        }

        case Expr::MachineOp::FrameSave:
            return callVoid(frameAsm(e->asmText, true), "~{memory}");

        case Expr::MachineOp::FrameRestore:
            return callVoid(frameAsm(e->asmText, false), "~{memory}");

        case Expr::MachineOp::ExceptionReturn:
            return callVoid("eret", "~{memory}");

        case Expr::MachineOp::CallSym:
        case Expr::MachineOp::FrameSwitch:
        case Expr::MachineOp::FramePark: {
            size_t c = e->asmText.find(',');
            std::string a = e->asmText.substr(0, c), b = e->asmText.substr(c + 1);
            std::string text;
            if (e->machineOp == Expr::MachineOp::CallSym) {
                // 引種: x0/x1 に渡す値。esr_elr_ret は戻り値 x0 を ELR_EL1 へ書き戻す。
                if (b == "sp") text += "mov x0, sp\n";
                if (b == "esr_sp") text += "mrs x0, esr_el1\nmov x1, sp\n";
                if (b == "esr_elr_ret") text += "mrs x0, esr_el1\nmrs x1, elr_el1\n";
                text += "bl " + a;
                if (b == "esr_elr_ret") text += "\nmsr elr_el1, x0";
            } else if (e->machineOp == Expr::MachineOp::FrameSwitch) {
                text = "cbz x0, " + a + "\nmov sp, x0\nb " + b;
            } else {
                text = "1:\nbl " + a + "\ncbz x0, 2f\nmov sp, x0\nb " + b + "\n2:\nwfi\nb 1b";
            }
            return callVoid(text, "~{memory}");
        }

        case Expr::MachineOp::StackSet: {
            const std::string& s = e->asmText;
            if (s[0] >= '0' && s[0] <= '9')
                return callVoid("mov x16, #" + s + "\nmov sp, x16", "~{memory}");
            return callVoid("adrp x16, " + s + "\nadd x16, x16, :lo12:" + s + "\nmov sp, x16", "~{memory}");
        }

        case Expr::MachineOp::SvcHalt: {
            std::string text;
            if (e->args.size() > 1) text += "mov x0, #" + std::to_string(e->args[1]->intValue) + "\n";
            text += "mov x8, #" + std::to_string(e->args[0]->intValue) + "\nsvc #0\n1:\nb 1b";
            return callVoid(text, "~{memory}");
        }

        case Expr::MachineOp::HaltLoop:
            return callVoid("1:\nwfi\nb 1b", "~{memory}");

        case Expr::MachineOp::DropToEL1:
            // CurrentEL が 1 ならそのまま。2 なら EL1 (AArch64) へ eret で降りる: HCR_EL2.RW=1、タイマーを EL1 に開放、
            // SPSR_EL2 = EL1h・DAIF マスク、ELR_EL2 = 直後。x0 (DTB) は触らない (作業は x16)。それ以外 (EL3 など) は止まる。
            return callVoid("mrs x16, CurrentEL\nlsr x16, x16, #2\ncmp x16, #1\nb.eq 1f\ncmp x16, #2\nb.ne 3f\n"
                            "movz x16, #0x8000, lsl #16\nmsr hcr_el2, x16\nmov x16, #3\nmsr cnthctl_el2, x16\nmsr cntvoff_el2, xzr\n"
                            "mov x16, #0x3c5\nmsr spsr_el2, x16\nadr x16, 1f\nmsr elr_el2, x16\neret\n3:\nwfe\nb 3b\n1:", "~{memory},~{x16}");

        case Expr::MachineOp::EnterUser:
            // enter_el0(入址 x0, 棧頭 x1, 引 x2, 核棧頭 x3): EL0t・DAIF 全マスクで eret。
            return callVoid("mov sp, x3\nmsr elr_el1, x0\nmsr sp_el0, x1\nmov x4, #0x3C0\nmsr spsr_el1, x4\nmov x0, x2\neret", "~{memory}");

        case Expr::MachineOp::VectorTable: {
            // 16 項 × 0x80。項 5 = 現 EL・SPx の IRQ、項 8 = 下位 EL の同期、項 9 = 下位 EL の IRQ、他は既定。
            std::vector<std::string> sym;
            size_t from = 0;
            for (;;) {
                size_t c = e->asmText.find(',', from);
                sym.push_back(e->asmText.substr(from, c == std::string::npos ? c : c - from));
                if (c == std::string::npos) break;
                from = c + 1;
            }
            if (sym.size() != 4) return "void ";
            std::string text;
            for (int i = 0; i < 16; i++) {
                const std::string& target = i == 5 ? sym[1] : i == 8 ? sym[2] : i == 9 ? sym[3] : sym[0];
                if (i > 0) text += "\n";
                text += ".p2align 7\nb " + target;
            }
            return callVoid(text, "~{memory}");
        }

        case Expr::MachineOp::Breakpoint: {
            uint64_t imm = e->args.empty() ? 0 : (e->args[0]->intValue & 0xFFFF);
            return callVoid("brk #" + std::to_string(imm), "~{memory}");
        }
    }
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
    // Simplified: v0.1 does not yet compute real struct offsets.
    std::string base = genExpr(e->base);
    std::string result = freshName("field");
    emit("%" + result + " = getelementptr i8, " + base + ", i64 0");
    return "ptr %" + result;
}

std::string LLVMIRGen::genElemAccess(const ExprPtr& e) {
    // 項(base, index): array/pointer indexing. Loads element `index`.
    TypePtr baseT = typeOfExpr(e->base);
    TypePtr elemT;
    if (baseT && baseT->kind == Type::Kind::Pointer && baseT->pointee) {
        elemT = baseT->pointee;
    } else if (baseT && baseT->kind == Type::Kind::Array && baseT->element) {
        elemT = baseT->element;
    }
    if (!elemT) elemT = Type::I8();

    std::string elemLLVM = llvmType(elemT);
    std::string base = genExpr(e->base);
    std::string index = genExpr(e->index);
    std::string gep = freshName("elemptr");
    emit("%" + gep + " = getelementptr " + elemLLVM + ", " + base + ", " + index);
    std::string result = freshName("elem");
    emit("%" + result + " = load " + elemLLVM + ", ptr %" + gep);
    return elemLLVM + " %" + result;
}

void LLVMIRGen::genExternal(const FunctionDecl& fn) {
    std::string name = fnSymbol(fn);
    std::string s = "declare dso_local " + llvmType(fn.returnType) + " " + irName(name) + "(";
    for (size_t i = 0; i < fn.params.size(); i++) {
        if (i > 0) s += ", ";
        s += llvmType(fn.params[i].type);
    }
    s += ")";
    emit(s);
}

void LLVMIRGen::genAlias(const AliasDecl& a) {
    // 別名 is resolved during type checking; nothing to emit.
    (void)a;
}

void LLVMIRGen::genConstant(const ConstantDecl& c) {
    // Fold integer, boolean, and null constant expressions at compile time so
    // `常` can be used from any function without emitting an initializer.
    uint64_t bits = 0;
    std::string lit;
    if (c.value && evalConst(c.value, bits)) {
        lit = constLiteral(c.type, bits);
    } else {
        if (c.value) {
            error(c.line, c.col, "E0001",
                "constant " + c.name + " is not an integer, boolean, or null constant expression");
        }
        lit = constLiteral(c.type, 0);
    }
    constants_[c.name] = {c.type, lit};
}

bool LLVMIRGen::evalConst(const ExprPtr& e, uint64_t& out, int depth) const {
    if (!e || depth > 128) return false;

    switch (e->kind) {
        case Expr::Kind::IntegerLit: {
            uint64_t v = e->intValue;
            if (e->isNegative) v = 0 - v;
            out = truncBits(v, typeOfExpr(e));
            return true;
        }
        case Expr::Kind::BoolLit:
            out = e->boolValue ? 1 : 0;
            return true;
        case Expr::Kind::NullLit:
            out = 0;
            return true;
        case Expr::Kind::Ident: {
            auto it = constDecls_.find(e->identName);
            if (it == constDecls_.end() || !it->second || !it->second->value) return false;
            return evalConst(it->second->value, out, depth + 1);
        }
        case Expr::Kind::UnaryOp: {
            uint64_t v = 0;
            if (!evalConst(e->operand, v, depth + 1)) return false;
            TypePtr t = typeOfExpr(e);
            if (e->unaryOp == "負") {
                out = truncBits(0 - v, t);
                return true;
            }
            if (e->unaryOp == "位非") {
                out = truncBits(~v, t);
                return true;
            }
            if (e->unaryOp == "非") {
                out = (v == 0) ? 1 : 0;
                return true;
            }
            return false;
        }
        case Expr::Kind::BinOp: {
            uint64_t a = 0, b = 0;
            if (!evalConst(e->left, a, depth + 1)) return false;
            if (!evalConst(e->right, b, depth + 1)) return false;

            const std::string& op = e->opText;
            TypePtr t = typeOfExpr(e);
            TypePtr ot = typeOfExpr(e->left);
            unsigned bits = intBits(ot);

            if (op == "且" || op == "或") {
                bool av = a != 0, bv = b != 0;
                out = (op == "且") ? (av && bv) : (av || bv);
                return true;
            }

            if (op == "等於" || op == "不等" || op == "小於" ||
                op == "小等" || op == "大於" || op == "大等") {
                a = truncBits(a, ot);
                b = truncBits(b, ot);
                bool c = false;
                if (op == "等於") c = a == b;
                else if (op == "不等") c = a != b;
                else if (ot && ot->isSigned()) {
                    int64_t sa = signExtendBits(a, bits);
                    int64_t sb = signExtendBits(b, bits);
                    if (op == "小於") c = sa < sb;
                    else if (op == "小等") c = sa <= sb;
                    else if (op == "大於") c = sa > sb;
                    else c = sa >= sb;
                } else {
                    if (op == "小於") c = a < b;
                    else if (op == "小等") c = a <= b;
                    else if (op == "大於") c = a > b;
                    else c = a >= b;
                }
                out = c ? 1 : 0;
                return true;
            }

            uint64_t r = 0;
            if (op == "加") r = a + b;
            else if (op == "減") r = a - b;
            else if (op == "乘") r = a * b;
            else if (op == "位與") r = a & b;
            else if (op == "位異") r = a ^ b;
            else if (op == "位或") r = a | b;
            else if (op == "除" || op == "餘") {
                if (b == 0) return false;
                if (ot && ot->isSigned()) {
                    int64_t sa = signExtendBits(a, bits);
                    int64_t sb = signExtendBits(b, bits);
                    if (sb == -1 && sa == std::numeric_limits<int64_t>::min()) return false;
                    r = (op == "除") ? static_cast<uint64_t>(sa / sb)
                                     : static_cast<uint64_t>(sa % sb);
                } else {
                    r = (op == "除") ? (a / b) : (a % b);
                }
            } else if (op == "左移" || op == "右移") {
                unsigned n = static_cast<unsigned>(b);
                if (n >= bits) return false;
                if (op == "左移") r = a << n;
                else if (ot && ot->isSigned()) {
                    r = static_cast<uint64_t>(signExtendBits(a, bits) >> n);
                } else {
                    r = a >> n;
                }
            } else {
                return false;
            }
            out = truncBits(r, t);
            return true;
        }
        case Expr::Kind::Cast: {
            uint64_t v = 0;
            if (!evalConst(e->castFrom, v, depth + 1)) return false;
            if (e->castTo && e->castTo->isInteger()) {
                out = truncBits(v, e->castTo);
                return true;
            }
            return false;
        }
        case Expr::Kind::StrLen: {
            const Expr* target = e->index.get();
            if (target && target->kind == Expr::Kind::AddrOf && target->addend) {
                target = target->addend.get();
            }
            if (target && target->kind == Expr::Kind::StringLit) {
                out = target->strValue.size();
                return true;
            }
            return false;
        }
        default:
            return false;
    }
}

std::string LLVMIRGen::constLiteral(const TypePtr& t, uint64_t bits) const {
    if (t) {
        if (t->kind == Type::Kind::Bool) return bits ? "true" : "false";
        if (t->kind == Type::Kind::Pointer) return "null";
        if (t->isInteger()) {
            unsigned width = intBits(t);
            bits &= intMask(width);
            if (t->isSigned()) return std::to_string(signExtendBits(bits, width));
            return std::to_string(bits);
        }
    }
    return std::to_string(bits);
}

void LLVMIRGen::genStruct(const StructDecl& s) {
    // Struct types are emitted inline at each use site in v0.1.
    (void)s;
}

std::string LLVMIRGen::generate(const Module& mod, const TypeChecker& tc) {
    tc_ = &tc;

    // Pass 0: register declarations so calls/fields can be resolved.
    for (auto& d : mod.decls) {
        switch (d.kind) {
            case Decl::Kind::Function:
            case Decl::Kind::External:
                if (d.function) functions_[d.function->name] = d.function;
                break;
            case Decl::Kind::Struct:
                if (d.structDecl) structs_[d.structDecl->name] = d.structDecl;
                break;
            case Decl::Kind::Alias:
                if (d.alias) aliases_[d.alias->name] = d.alias;
                break;
            default:
                break;
        }
    }

    // Register constants before folding so a constant may refer to a later one.
    constDecls_.clear();
    for (auto& d : mod.decls) {
        if (d.kind == Decl::Kind::Constant && d.constant) {
            constDecls_[d.constant->name] = d.constant.get();
        }
    }

    // Pass 1: fold constants (usable from any function).
    for (auto& d : mod.decls) {
        if (d.kind == Decl::Kind::Constant && d.constant) genConstant(*d.constant);
    }

    // Pass 2: emit external declarations first, then definitions.
    bool anyDecl = false;
    for (auto& d : mod.decls) {
        if ((d.kind == Decl::Kind::Function || d.kind == Decl::Kind::External) &&
            d.function && d.function->isExternal) {
            genExternal(*d.function);
            anyDecl = true;
        }
    }
    if (anyDecl) emitBlank();

    for (auto& d : mod.decls) {
        switch (d.kind) {
            case Decl::Kind::Function:
                if (d.function && !d.function->isExternal) genFunction(*d.function);
                break;
            case Decl::Kind::Alias:
                if (d.alias) genAlias(*d.alias);
                break;
            case Decl::Kind::Struct:
                if (d.structDecl) genStruct(*d.structDecl);
                break;
            default:
                break;
        }
    }

    // Pass 3: emit collected string literal storage.
    if (!stringData_.empty()) {
        for (auto& sd : stringData_) {
            emit("@" + sd.first + " = private unnamed_addr constant [" +
                 std::to_string(sd.second.size()) + " x i8] c\"" +
                 escapeIrBytes(sd.second) + "\", align 1");
        }
        emitBlank();
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
