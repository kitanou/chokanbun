#include "typecheck.h"
#include <iostream>
#include <functional>

namespace chokanbun {

TypeChecker::TypeChecker(const Module& mod) : mod_(mod) {
    buildStructLayouts();
}

void TypeChecker::buildStructLayouts() {
    for (auto& d : mod_.decls) {
        if (d.kind == Decl::Kind::Struct) {
            StructLayout layout;
            uint64_t offset = 0;
            for (auto& f : d.structDecl->fields) {
                if (!f.type) continue;
                uint64_t size = f.type->sizeBytes();
                if (size == 0) {
                    // Unknown size (nested struct not yet laid out); skip
                    continue;
                }
                layout.fields.push_back({offset, f.type});
                offset += size;
            }
            layout.totalSize = offset;
            structLayouts_[d.structDecl->name] = layout;
        }
    }
}

void TypeChecker::error(uint32_t line, uint32_t col, const std::string& code, const std::string& msg) {
    diags_.emplace_back(Diagnostic::Level::Error, line, col, code, msg);
    hasErrors_ = true;
}

void TypeChecker::errorAt(const Expr& e, const std::string& code, const std::string& msg) {
    error(e.line, e.col, code, msg);
}

void TypeChecker::errorAt(const Stmt& s, const std::string& code, const std::string& msg) {
    error(s.line, s.col, code, msg);
}

// An untyped integer literal conforms to any integer type, and 空 conforms to
// any pointer type. Record the resolved type so code generation emits the
// literal with the right width.
bool TypeChecker::coerceLiteral(const ExprPtr& value, const TypePtr& target) {
    if (!value || !target) return false;
    if (value->kind == Expr::Kind::IntegerLit && target->isInteger()) {
        // 数値リテラルは使用文脈の整数型に適合しなければエラー (言語仕様 §2)
        uint64_t bits = target->sizeBytes() * 8;
        uint64_t maxv = target->isSigned()
            ? ((uint64_t(1) << (bits - 1)) - 1)
            : (bits >= 64 ? UINT64_MAX : ((uint64_t(1) << bits) - 1));
        if (value->intValue > maxv) {
            error(value->line, value->col, "E0010",
                "integer literal " + std::to_string(value->intValue) +
                " is out of range for " + target->toString());
        }
        exprTypes_[value.get()] = target;
        return true;
    }
    if (value->kind == Expr::Kind::NullLit && target->kind == Type::Kind::Pointer) {
        exprTypes_[value.get()] = target;
        return true;
    }
    return false;
}

void TypeChecker::enterScope() {
    scopes_.emplace_back();
}

void TypeChecker::exitScope() {
    if (!scopes_.empty()) scopes_.pop_back();
}

TypePtr* TypeChecker::lookupVar(const std::string& name) {
    for (auto it = scopes_.rbegin(); it != scopes_.rend(); ++it) {
        auto found = it->vars.find(name);
        if (found != it->vars.end()) return &found->second;
    }
    return nullptr;
}

void TypeChecker::declareVar(const std::string& name, TypePtr type) {
    if (scopes_.empty()) scopes_.emplace_back();
    scopes_.back().vars[name] = std::move(type);
}

bool TypeChecker::isDeclared(const std::string& name) const {
    for (auto it = scopes_.rbegin(); it != scopes_.rend(); ++it) {
        if (it->vars.count(name)) return true;
    }
    return false;
}

bool TypeChecker::isInitialized(const std::string& name) const {
    return isDeclared(name);
}

void TypeChecker::markInitialized(const std::string& name) {
    // In v0.1, all declared variables are considered initialized
    // (the spec requires rejection of uninitialized reads, but for v0.1
    //  we treat all variables as initialized after declaration)
    (void)name;
}

FunctionDecl* TypeChecker::findFunction(const std::string& name) const {
    for (auto& d : mod_.decls) {
        if (d.kind == Decl::Kind::Function && d.function->name == name)
            return d.function.get();
        if (d.kind == Decl::Kind::External && d.function->name == name)
            return d.function.get();
    }
    return nullptr;
}

ConstantDecl* TypeChecker::findConstant(const std::string& name) const {
    for (auto& d : mod_.decls) {
        if (d.kind == Decl::Kind::Constant && d.constant->name == name)
            return d.constant.get();
    }
    return nullptr;
}

StructDecl* TypeChecker::findStruct(const std::string& name) const {
    for (auto& d : mod_.decls) {
        if (d.kind == Decl::Kind::Struct && d.structDecl->name == name)
            return d.structDecl.get();
    }
    return nullptr;
}

bool TypeChecker::check() {
    // Check all declarations
    for (auto& d : mod_.decls) {
        switch (d.kind) {
            case Decl::Kind::Function:
                checkFunction(*d.function);
                break;
            case Decl::Kind::External:
                checkExternal(*d.function);
                break;
            case Decl::Kind::Constant:
                checkConstant(*d.constant);
                break;
            case Decl::Kind::Struct:
                checkStruct(*d.structDecl);
                break;
            case Decl::Kind::Alias:
                // Alias declarations don't need type checking in v0.1
                break;
        }
    }
    return hasErrors_;
}

// ========== Expression type checking ==========

const TypePtr& TypeChecker::exprType(const Expr& e) const {
    static const TypePtr nullType = Type::Void();
    auto it = exprTypes_.find(&e);
    if (it != exprTypes_.end()) return it->second;
    return nullType;
}

const TypePtr& TypeChecker::lvalueType(const Expr& e) const {
    static const TypePtr nullType = Type::Void();
    auto it = lvalueTypes_.find(&e);
    if (it != lvalueTypes_.end()) return it->second;
    return nullType;
}

TypePtr TypeChecker::checkExpr(const Expr& e) {
    switch (e.kind) {
        case Expr::Kind::IntegerLit: {
            // Default to i64 (the spec's default integer type)
            auto t = Type::I64();
            exprTypes_[&e] = t;
            return t;
        }
        case Expr::Kind::BoolLit: {
            auto t = Type::Bool();
            exprTypes_[&e] = t;
            return t;
        }
        case Expr::Kind::StringLit: {
            auto t = Type::String(e.strValue.size());
            exprTypes_[&e] = t;
            return t;
        }
        case Expr::Kind::NullLit: {
            // 空 is a null pointer; type is pointer to void (untyped)
            auto t = Type::Pointer(Type::Void());
            exprTypes_[&e] = t;
            return t;
        }
        case Expr::Kind::Ident:
            return checkIdent(e);
        case Expr::Kind::BinOp:
            return checkBinOp(e);
        case Expr::Kind::UnaryOp:
            return checkUnaryOp(e);
        case Expr::Kind::Call:
            return checkCall(e);
        case Expr::Kind::AddrOf:
            return checkAddrOf(e);
        case Expr::Kind::Deref:
            return checkDeref(e);
        case Expr::Kind::Cast:
            return checkCast(e);
        case Expr::Kind::VolatileRead:
            return checkVolatileRead(e);
        case Expr::Kind::VolatileWrite:
            return checkVolatileWrite(e);
        case Expr::Kind::Fence:
            return checkFence(e);
        case Expr::Kind::Asm:
            return checkAsm(e);
        case Expr::Kind::Machine:
            return checkMachine(e);
        case Expr::Kind::StrLen:
            return checkStrLen(e);
        case Expr::Kind::FieldAccess:
            return checkFieldAccess(e);
        case Expr::Kind::ElemAccess:
            return checkElemAccess(e);
    }
    auto t = Type::Void();
    exprTypes_[&e] = t;
    return t;
}

TypePtr TypeChecker::checkIdent(const Expr& e) {
    // Check if it's a constant
    ConstantDecl* c = findConstant(e.identName);
    if (c) {
        if (c->value) {
            TypePtr vt = checkExpr(*c->value);
            // Check type compatibility with declared type; an untyped integer
            // literal in the initializer adopts the declared type.
            if (c->type && vt && !vt->isSameAs(*c->type)) {
                if (!coerceLiteral(c->value, c->type)) {
                    errorAt(e, "E0004", "constant " + e.identName +
                        " value type " + vt->toString() +
                        " does not match declared type " + c->type->toString());
                }
            }
            exprTypes_[&e] = c->type ? c->type : vt;
            return c->type ? c->type : vt;
        }
        auto t = c->type ? c->type : Type::Void();
        exprTypes_[&e] = t;
        return t;
    }

    // Check if it's a local variable
    TypePtr* varType = lookupVar(e.identName);
    if (varType) {
        if (!isInitialized(e.identName)) {
            errorAt(e, "E0005", "uninitialized read of variable " + e.identName);
        }
        exprTypes_[&e] = *varType;
        return *varType;
    }

    // Check if it's a function name (used as a value, e.g. function pointer)
    FunctionDecl* fn = findFunction(e.identName);
    if (fn) {
        // In v0.1, function names used as values are pointers to functions
        // For simplicity, treat as void pointer
        auto t = Type::Pointer(Type::Void());
        exprTypes_[&e] = t;
        return t;
    }

    if (!initializingName_.empty() && e.identName == initializingName_) {
        // 設は必ず初期値を持つので、未初期化の読み出しは自己参照でのみ生じる
        errorAt(e, "E0005", "uninitialized read of variable " + e.identName +
            " in its own initializer");
    } else {
        errorAt(e, "E0003", "undeclared identifier " + e.identName);
    }
    auto t = Type::Void();
    exprTypes_[&e] = t;
    return t;
}

TypePtr TypeChecker::checkBinOp(const Expr& e) {
    TypePtr lt = checkExpr(*e.left);
    TypePtr rt = checkExpr(*e.right);

    if (!lt || !rt) {
        auto t = Type::Void();
        exprTypes_[&e] = t;
        return t;
    }

    // An untyped integer literal adopts the other operand's integer type, so
    // e.g. `u64変数 加 1` and `u64変数 小於 0` type-check.
    if (lt->isInteger() && rt->isInteger() && !lt->isSameAs(*rt)) {
        if (coerceLiteral(e.left, rt)) {
            lt = rt;
        } else if (coerceLiteral(e.right, lt)) {
            rt = lt;
        }
    }

    // Arithmetic operators: both operands must be the same integer type
    if (e.opText == "加" || e.opText == "減" || e.opText == "乘" ||
        e.opText == "除" || e.opText == "餘" ||
        e.opText == "左移" || e.opText == "右移" ||
        e.opText == "位與" || e.opText == "位異" || e.opText == "位或") {

        if (!lt->isInteger() || !rt->isInteger()) {
            errorAt(e, "E0001", "arithmetic operator requires integer operands, got " +
                lt->toString() + " and " + rt->toString());
            auto t = Type::Void();
            exprTypes_[&e] = t;
            return t;
        }

        if (!lt->isSameAs(*rt)) {
            errorAt(e, "E0001", "type mismatch: " + lt->toString() +
                " and " + rt->toString());
            auto t = Type::Void();
            exprTypes_[&e] = t;
            return t;
        }

        exprTypes_[&e] = lt;
        return lt;
    }

    // Comparison operators: both must be the same integer type, result is Bool
    if (e.opText == "小於" || e.opText == "小等" || e.opText == "大於" ||
        e.opText == "大等" || e.opText == "等於" || e.opText == "不等") {

        if (!lt->isInteger() || !rt->isInteger()) {
            errorAt(e, "E0001", "comparison operator requires integer operands, got " +
                lt->toString() + " and " + rt->toString());
            auto t = Type::Void();
            exprTypes_[&e] = t;
            return t;
        }

        if (!lt->isSameAs(*rt)) {
            errorAt(e, "E0001", "type mismatch in comparison: " + lt->toString() +
                " and " + rt->toString());
            auto t = Type::Void();
            exprTypes_[&e] = t;
            return t;
        }

        auto t = Type::Bool();
        exprTypes_[&e] = t;
        return t;
    }

    // Logical AND / OR: both must be Bool
    if (e.opText == "且" || e.opText == "或") {
        if (lt->kind != Type::Kind::Bool) {
            errorAt(e, "E0001", "logical operand must be 真偽, got " + lt->toString());
        }
        if (rt->kind != Type::Kind::Bool) {
            errorAt(e, "E0001", "logical operand must be 真偽, got " + rt->toString());
        }
        auto t = Type::Bool();
        exprTypes_[&e] = t;
        return t;
    }

    // Unknown operator
    errorAt(e, "E0001", "unknown binary operator " + e.opText);
    auto t = Type::Void();
    exprTypes_[&e] = t;
    return t;
}

TypePtr TypeChecker::checkUnaryOp(const Expr& e) {
    if (!e.operand) {
        auto t = Type::Void();
        exprTypes_[&e] = t;
        return t;
    }

    TypePtr ot = checkExpr(*e.operand);
    if (!ot) {
        auto t = Type::Void();
        exprTypes_[&e] = t;
        return t;
    }

    if (e.unaryOp == "負") {
        // Negation: must be signed integer
        if (!ot->isInteger() || !ot->isSigned()) {
            errorAt(e, "E0001", "negation requires signed integer, got " + ot->toString());
            auto t = Type::Void();
            exprTypes_[&e] = t;
            return t;
        }
        exprTypes_[&e] = ot;
        return ot;
    }

    if (e.unaryOp == "非") {
        // Logical NOT: must be Bool
        if (ot->kind != Type::Kind::Bool) {
            errorAt(e, "E0001", "logical NOT requires 真偽, got " + ot->toString());
            auto t = Type::Void();
            exprTypes_[&e] = t;
            return t;
        }
        auto t = Type::Bool();
        exprTypes_[&e] = t;
        return t;
    }

    if (e.unaryOp == "位非") {
        // Bitwise NOT: must be integer
        if (!ot->isInteger()) {
            errorAt(e, "E0001", "bitwise NOT requires integer, got " + ot->toString());
            auto t = Type::Void();
            exprTypes_[&e] = t;
            return t;
        }
        exprTypes_[&e] = ot;
        return ot;
    }

    errorAt(e, "E0001", "unknown unary operator " + e.unaryOp);
    auto t = Type::Void();
    exprTypes_[&e] = t;
    return t;
}

TypePtr TypeChecker::checkCall(const Expr& e) {
    FunctionDecl* fn = findFunction(e.callee);
    if (!fn) {
        errorAt(e, "E0003", "undeclared function " + e.callee);
        auto t = Type::Void();
        exprTypes_[&e] = t;
        return t;
    }

    // Check argument count
    if (fn->isExternal || !fn->body.empty()) {
        if (e.args.size() != fn->params.size()) {
            errorAt(e, "E0006", "call to " + e.callee +
                " expects " + std::to_string(fn->params.size()) +
                " argument(s), got " + std::to_string(e.args.size()));
        }
    }

    // Check argument types
    for (size_t i = 0; i < e.args.size() && i < fn->params.size(); i++) {
        TypePtr at = checkExpr(*e.args[i]);
        TypePtr pt = fn->params[i].type;
        if (at && pt && !at->isSameAs(*pt)) {
            if (!coerceLiteral(e.args[i], pt)) {
                errorAt(e, "E0001", "argument " + std::to_string(i + 1) +
                    " of " + e.callee + ": expected " + pt->toString() +
                    ", got " + at->toString());
            }
        }
    }

    exprTypes_[&e] = fn->returnType;
    return fn->returnType;
}

TypePtr TypeChecker::checkAddrOf(const Expr& e) {
    if (!e.addend) {
        auto t = Type::Void();
        exprTypes_[&e] = t;
        return t;
    }

    // 取址(術名): 関数 (外術のリンカ記号を含む) のアドレスを 無符六四 で返す。
    if (e.addend->kind == Expr::Kind::Ident && !lookupVar(e.addend->identName) &&
        !findConstant(e.addend->identName) && findFunction(e.addend->identName)) {
        auto t = Type::U64();
        exprTypes_[&e] = t;
        return t;
    }

    TypePtr base = checkExpr(*e.addend);
    if (!base) {
        auto t = Type::Void();
        exprTypes_[&e] = t;
        return t;
    }

    // 取址 of a string literal is a safe operation (spec §9)
    // 取址 of a pointer is a safe operation (取址 of a pointer value)
    // 取址 of a local variable is a safe operation
    // 取址 of a dereference is a safe operation (re-obtaining the pointer)

    // A string literal is a byte array; its address is 指標〈無符八〉.
    TypePtr pointeeType = base;
    if (base->kind == Type::Kind::String) {
        pointeeType = Type::U8();
    } else if (base->kind == Type::Kind::Array && base->element) {
        pointeeType = base->element;
    }

    auto t = Type::Pointer(pointeeType);
    exprTypes_[&e] = t;
    return t;
}

TypePtr TypeChecker::checkDeref(const Expr& e) {
    if (!e.pointee) {
        auto t = Type::Void();
        exprTypes_[&e] = t;
        return t;
    }

    // Raw pointer dereference requires 險 context (spec §6)
    if (unsafeDepth_ == 0) {
        errorAt(e, "E0002", "raw pointer dereference requires 險 block");
    }

    TypePtr pt = checkExpr(*e.pointee);
    if (!pt || pt->kind != Type::Kind::Pointer) {
        errorAt(e, "E0001", "dereference requires pointer, got " +
            (pt ? pt->toString() : "unknown"));
        auto t = Type::Void();
        exprTypes_[&e] = t;
        return t;
    }

    exprTypes_[&e] = pt->pointee;
    return pt->pointee;
}

TypePtr TypeChecker::checkCast(const Expr& e) {
    if (!e.castFrom) {
        auto t = Type::Void();
        exprTypes_[&e] = t;
        return t;
    }

    TypePtr from = checkExpr(*e.castFrom);
    TypePtr to = e.castTo;

    if (!from || !to) {
        auto t = Type::Void();
        exprTypes_[&e] = t;
        return t;
    }

    // int⇄ptr casts require 險 context (spec §6)
    bool isIntPtrCast =
        (from->isInteger() && to->kind == Type::Kind::Pointer) ||
        (from->kind == Type::Kind::Pointer && to->isInteger());

    if (isIntPtrCast && unsafeDepth_ == 0) {
        errorAt(e, "E0002", "integer-pointer cast requires 險 block");
    }

    // Pointer to pointer: check that the source is a pointer
    if (to->kind == Type::Kind::Pointer && from->kind != Type::Kind::Pointer) {
        // int to pointer is handled above; string to pointer is OK
        if (from->kind != Type::Kind::String && !from->isInteger()) {
            errorAt(e, "E0001", "cannot cast " + from->toString() +
                " to " + to->toString());
        }
    }

    exprTypes_[&e] = to;
    return to;
}

TypePtr TypeChecker::checkVolatileRead(const Expr& e) {
    // MMIO read requires 險 context (spec §6)
    if (unsafeDepth_ == 0) {
        errorAt(e, "E0002", "volatile read requires 險 block");
    }

    if (!e.volPtr) {
        auto t = Type::Void();
        exprTypes_[&e] = t;
        return t;
    }

    TypePtr pt = checkExpr(*e.volPtr);
    if (!pt || pt->kind != Type::Kind::Pointer) {
        errorAt(e, "E0001", "volatile read requires pointer, got " +
            (pt ? pt->toString() : "unknown"));
        auto t = Type::Void();
        exprTypes_[&e] = t;
        return t;
    }

    exprTypes_[&e] = e.volType ? e.volType : pt->pointee;
    return e.volType ? e.volType : pt->pointee;
}

TypePtr TypeChecker::checkVolatileWrite(const Expr& e) {
    // MMIO write requires 險 context (spec §6)
    if (unsafeDepth_ == 0) {
        errorAt(e, "E0002", "volatile write requires 險 block");
    }

    if (!e.volPtr || !e.volVal) {
        auto t = Type::Void();
        exprTypes_[&e] = t;
        return t;
    }

    TypePtr pt = checkExpr(*e.volPtr);
    TypePtr vt = checkExpr(*e.volVal);

    if (!pt || pt->kind != Type::Kind::Pointer) {
        errorAt(e, "E0001", "volatile write requires pointer, got " +
            (pt ? pt->toString() : "unknown"));
    }

    if (vt && e.volType && !vt->isSameAs(*e.volType)) {
        // An untyped integer literal adopts the volatile access type.
        if (!coerceLiteral(e.volVal, e.volType)) {
            errorAt(e, "E0001", "volatile write value type " + vt->toString() +
                " does not match " + e.volType->toString());
        }
    }

    auto t = Type::Void();
    exprTypes_[&e] = t;
    return t;
}

TypePtr TypeChecker::checkFence(const Expr& e) {
    // Memory barrier requires 險 context (spec §6)
    if (unsafeDepth_ == 0) {
        errorAt(e, "E0002", "memory barrier requires 險 block");
    }

    auto t = Type::Void();
    exprTypes_[&e] = t;
    return t;
}

TypePtr TypeChecker::checkAsm(const Expr& e) {
    // inline asm requires 險 context (spec §6)
    if (unsafeDepth_ == 0) {
        errorAt(e, "E0002", "inline assembly requires 險 block");
    }
    for (auto& a : e.args) {
        TypePtr at = checkExpr(*a);
        if (at && !(at->isInteger() || at->kind == Type::Kind::Pointer || at->kind == Type::Kind::Bool)) {
            errorAt(*a, "E0001", "組譯 operand must be an integer or pointer, got " + at->toString());
        }
    }
    auto t = e.asmType ? e.asmType : Type::Void();
    exprTypes_[&e] = t;
    return t;
}

TypePtr TypeChecker::checkMachine(const Expr& e) {
    // 型付き機械命令はすべて低水準操作なので 險 の中だけで使える (spec §6)。
    if (unsafeDepth_ == 0) {
        errorAt(e, "E0002", "machine instruction requires 險 block");
    }

    auto ret = [&](TypePtr t) {
        exprTypes_[&e] = t;
        return t;
    };
    auto checkValue = [&](const ExprPtr& a, const char* what) -> TypePtr {
        if (!a) return nullptr;
        TypePtr t = checkExpr(*a);
        if (t && !(t->isInteger() || t->kind == Type::Kind::Pointer || t->kind == Type::Kind::Bool)) {
            errorAt(*a, "E0001", std::string(what) + " must be an integer, got " + t->toString());
        }
        return t;
    };

    switch (e.machineOp) {
        case Expr::MachineOp::SysRegRead:
            return ret(Type::U64());

        case Expr::MachineOp::SysRegWrite: {
            if (e.args.size() != 1) {
                errorAt(e, "E0001", "系統寫 takes exactly one operand");
                return ret(Type::Void());
            }
            TypePtr vt = checkValue(e.args[0], "系統寫 operand");
            if (e.asmText == "daifset" || e.asmText == "daifclr") {
                // msr daifset/daifclr, #imm4 は即値のみ。
                if (e.args[0]->kind != Expr::Kind::IntegerLit) {
                    errorAt(*e.args[0], "E0001", e.asmText + " requires an integer literal");
                } else if (e.args[0]->intValue > 15) {
                    errorAt(*e.args[0], "E0001", e.asmText + " immediate must be 0..15");
                }
            } else if (vt && vt->isInteger()) {
                coerceLiteral(e.args[0], Type::U64());
            }
            return ret(Type::Void());
        }

        case Expr::MachineOp::MemBarrier:
        case Expr::MachineOp::InstrBarrier:
        case Expr::MachineOp::TlbInvalidate:
        case Expr::MachineOp::InstrCacheClean:
        case Expr::MachineOp::WaitEvent:
        case Expr::MachineOp::FrameSave:
        case Expr::MachineOp::FrameRestore:
        case Expr::MachineOp::ExceptionReturn:
            return ret(Type::Void());

        case Expr::MachineOp::DataCacheClean: {
            if (e.args.size() != 1) {
                errorAt(e, "E0001", "資清 takes exactly one address");
                return ret(Type::Void());
            }
            TypePtr at = checkValue(e.args[0], "資清 address");
            if (at && at->isInteger()) coerceLiteral(e.args[0], Type::U64());
            return ret(Type::Void());
        }

        case Expr::MachineOp::Syscall: {
            if (e.args.empty() || e.args.size() > 7) {
                errorAt(e, "E0001", "漢令 takes a call number and up to 6 arguments");
            }
            for (auto& a : e.args) {
                TypePtr at = checkValue(a, "漢令 operand");
                if (at && at->isInteger()) coerceLiteral(a, Type::U64());
            }
            return ret(Type::U64());
        }

        case Expr::MachineOp::Breakpoint: {
            if (e.args.size() != 1) {
                errorAt(e, "E0001", "異常令 takes exactly one immediate");
                return ret(Type::Void());
            }
            checkValue(e.args[0], "異常令 immediate");
            if (e.args[0]->kind != Expr::Kind::IntegerLit) {
                errorAt(*e.args[0], "E0001", "異常令 requires an integer literal immediate");
            } else if (e.args[0]->intValue > 0xFFFF) {
                errorAt(*e.args[0], "E0001", "異常令 immediate must be 0..65535");
            }
            return ret(Type::Void());
        }
    }
    return ret(Type::Void());
}

TypePtr TypeChecker::checkStrLen(const Expr& e) {
    if (!e.index) {
        auto t = Type::Void();
        exprTypes_[&e] = t;
        return t;
    }

    TypePtr base = checkExpr(*e.index);
    if (!base) {
        auto t = Type::Void();
        exprTypes_[&e] = t;
        return t;
    }

    // 長度 of a string literal is a safe operation (spec §9)
    // 長度 of a pointer is a safe operation
    // The result is always 無符六四 (u64)

    auto t = Type::U64();
    exprTypes_[&e] = t;
    return t;
}

TypePtr TypeChecker::checkFieldAccess(const Expr& e) {
    if (!e.base) {
        auto t = Type::Void();
        exprTypes_[&e] = t;
        return t;
    }

    TypePtr base = checkExpr(*e.base);
    if (!base) {
        auto t = Type::Void();
        exprTypes_[&e] = t;
        return t;
    }

    // The base must be a struct or a pointer to struct
    TypePtr structType = base;
    if (base->kind == Type::Kind::Pointer && base->pointee) {
        structType = base->pointee;
    }

    if (structType->kind != Type::Kind::Struct) {
        errorAt(e, "E0001", "field access requires struct, got " +
            structType->toString());
        auto t = Type::Void();
        exprTypes_[&e] = t;
        return t;
    }

    StructDecl* sd = findStruct(structType->name);
    if (!sd) {
        errorAt(e, "E0003", "undeclared struct " + structType->name);
        auto t = Type::Void();
        exprTypes_[&e] = t;
        return t;
    }

    for (auto& f : sd->fields) {
        if (f.name == e.fieldName) {
            // Field access on a struct value is safe; on a pointer, it's a dereference
            // For simplicity in v0.1, treat field access on pointer as safe
            // (the spec allows 欄 access on struct values and pointers)
            exprTypes_[&e] = f.type;
            return f.type;
        }
    }

    errorAt(e, "E0003", "struct " + structType->name +
        " has no field " + e.fieldName);
    auto t = Type::Void();
    exprTypes_[&e] = t;
    return t;
}

TypePtr TypeChecker::checkElemAccess(const Expr& e) {
    if (!e.base || !e.index) {
        auto t = Type::Void();
        exprTypes_[&e] = t;
        return t;
    }

    TypePtr base = checkExpr(*e.base);
    TypePtr idx = checkExpr(*e.index);

    if (!base || !idx) {
        auto t = Type::Void();
        exprTypes_[&e] = t;
        return t;
    }

    // Raw pointer indexing: 項(ptr, i) reads element i. Unsafe, so it must be
    // inside a 險 block.
    if (base->kind == Type::Kind::Pointer && base->pointee) {
        if (unsafeDepth_ == 0) {
            errorAt(e, "E0002", "pointer element access requires 險 block");
        }
        if (!idx->isInteger()) {
            errorAt(e, "E0001", "pointer index must be integer, got " + idx->toString());
        }
        exprTypes_[&e] = base->pointee;
        return base->pointee;
    }

    if (base->kind != Type::Kind::Array) {
        errorAt(e, "E0001", "element access requires array or pointer, got " +
            base->toString());
        auto t = Type::Void();
        exprTypes_[&e] = t;
        return t;
    }

    TypePtr arrType = base;

    // Index must be an integer
    if (!idx->isInteger()) {
        errorAt(e, "E0001", "array index must be integer, got " + idx->toString());
        auto t = Type::Void();
        exprTypes_[&e] = t;
        return t;
    }

    // Check bounds if the index is a constant
    if (e.index->kind == Expr::Kind::IntegerLit) {
        if (e.index->intValue >= arrType->length) {
            errorAt(e, "E0007", "array index " + std::to_string(e.index->intValue) +
                " out of bounds (size " + std::to_string(arrType->length) + ")");
        }
    }

    exprTypes_[&e] = arrType->element;
    return arrType->element;
}

// ========== Statement checking ==========

void TypeChecker::checkStmt(const Stmt& s) {
    switch (s.kind) {
        case Stmt::Kind::LocalDecl:
            checkLocalDecl(s);
            break;
        case Stmt::Kind::Assign:
            checkAssign(s);
            break;
        case Stmt::Kind::CallStmt:
            checkCallStmt(s);
            break;
        case Stmt::Kind::IfStmt:
            checkIf(s);
            break;
        case Stmt::Kind::WhileStmt:
            checkWhile(s);
            break;
        case Stmt::Kind::ReturnStmt:
            checkReturn(s);
            break;
        case Stmt::Kind::UnsafeBlock:
            checkUnsafeBlock(s);
            break;
        case Stmt::Kind::ExprStmt:
            checkExprStmt(s);
            break;
    }
}

void TypeChecker::checkLocalDecl(const Stmt& s) {
    // Check initializer
    if (s.init) {
        std::string savedInit = initializingName_;
        initializingName_ = s.varName;
        TypePtr it = checkExpr(*s.init);
        initializingName_ = savedInit;
        if (s.varType && it && !it->isSameAs(*s.varType)) {
            if (coerceLiteral(s.init, s.varType)) {
                it = s.varType;
            } else {
                errorAt(s, "E0001", "initialization type " + it->toString() +
                    " does not match declared type " + s.varType->toString());
            }
        }
    }

    // Check for redeclaration
    if (isDeclared(s.varName)) {
        errorAt(s, "E0003", "redeclaration of variable " + s.varName);
    }

    declareVar(s.varName, s.varType);
}

void TypeChecker::checkAssign(const Stmt& s) {
    if (!s.target || !s.value) {
        return;
    }

    TypePtr tt = checkExpr(*s.target);
    TypePtr vt = checkExpr(*s.value);

    if (!tt || !vt) return;

    // The target must be an lvalue
    // In v0.1, we accept any expression as an assignment target,
    // but the types must match

    if (!tt->isSameAs(*vt)) {
        if (!coerceLiteral(s.value, tt)) {
            errorAt(s, "E0001", "assignment type mismatch: target is " +
                tt->toString() + ", value is " + vt->toString());
        }
    }

    // If the target is a dereference, it requires 險
    if (s.target->kind == Expr::Kind::Deref && unsafeDepth_ == 0) {
        errorAt(s, "E0002", "pointer assignment requires 險 block");
    }
}

void TypeChecker::checkCallStmt(const Stmt& s) {
    FunctionDecl* fn = findFunction(s.callee);
    if (!fn) {
        errorAt(s, "E0003", "undeclared function " + s.callee);
        return;
    }

    if (s.args.size() != fn->params.size()) {
        errorAt(s, "E0006", "call to " + s.callee +
            " expects " + std::to_string(fn->params.size()) +
            " argument(s), got " + std::to_string(s.args.size()));
    }

    for (size_t i = 0; i < s.args.size() && i < fn->params.size(); i++) {
        TypePtr at = checkExpr(*s.args[i]);
        TypePtr pt = fn->params[i].type;
        if (at && pt && !at->isSameAs(*pt)) {
            if (!coerceLiteral(s.args[i], pt)) {
                errorAt(s, "E0001", "argument " + std::to_string(i + 1) +
                    " of " + s.callee + ": expected " + pt->toString() +
                    ", got " + at->toString());
            }
        }
    }
}

void TypeChecker::checkIf(const Stmt& s) {
    if (s.cond) {
        TypePtr ct = checkExpr(*s.cond);
        if (ct && ct->kind != Type::Kind::Bool) {
            errorAt(s, "E0001", "if condition must be 真偽, got " + ct->toString());
        }
    }

    enterScope();
    for (auto& st : s.thenBlock) checkStmt(*st);
    exitScope();

    if (s.hasElse) {
        enterScope();
        for (auto& st : s.elseBlock) checkStmt(*st);
        exitScope();
    }
}

void TypeChecker::checkWhile(const Stmt& s) {
    if (s.cond) {
        TypePtr ct = checkExpr(*s.cond);
        if (ct && ct->kind != Type::Kind::Bool) {
            errorAt(s, "E0001", "while condition must be 真偽, got " + ct->toString());
        }
    }

    enterScope();
    for (auto& st : s.body) checkStmt(*st);
    exitScope();
}

void TypeChecker::checkReturn(const Stmt& s) {
    if (!s.hasRetVal || !s.retVal) {
        return;
    }

    // Check against the current function's return type.
    TypePtr rt = checkExpr(*s.retVal);
    if (!rt) return;
    if (currentReturnType_ && !currentReturnType_->isSameAs(*rt)) {
        if (!coerceLiteral(s.retVal, currentReturnType_)) {
            errorAt(s, "E0001", "return type " + rt->toString() +
                " does not match function return type " +
                currentReturnType_->toString());
        }
    }
}

void TypeChecker::checkUnsafeBlock(const Stmt& s) {
    unsafeDepth_++;
    enterScope();
    for (auto& st : s.unsafeBody) checkStmt(*st);
    exitScope();
    unsafeDepth_--;
}

void TypeChecker::checkExprStmt(const Stmt& s) {
    if (s.expr) {
        checkExpr(*s.expr);
    }
}

// ========== Declaration checking ==========

void TypeChecker::checkFunction(const FunctionDecl& fn) {
    // 裸: 本体は 險 の中の 組譯 だけ。引数・局所変数・通常の文は持てない。
    if (fn.isNaked) {
        if (fn.returnType && fn.returnType->kind != Type::Kind::Void)
            error(fn.line, fn.col, "E0012", "naked function " + fn.name + " must return 無");
        if (!fn.isPublic)
            error(fn.line, fn.col, "E0012", "naked function " + fn.name + " must be 公開");
        std::function<void(const std::vector<StmtPtr>&)> only = [&](const std::vector<StmtPtr>& b) {
            for (auto& st : b) {
                if (st->kind == Stmt::Kind::UnsafeBlock) { only(st->unsafeBody); continue; }
                if (st->kind == Stmt::Kind::ExprStmt && st->expr &&
                    (st->expr->kind == Expr::Kind::Asm || st->expr->kind == Expr::Kind::Machine)) continue;
                error(st->line, st->col, "E0012", "naked function " + fn.name + " may contain only 組譯 or machine instructions");
            }
        };
        only(fn.body);
    }

    // Check the function body
    enterScope();

    // Declare parameters
    for (auto& p : fn.params) {
        declareVar(p.name, p.type);
    }

    TypePtr savedReturn = currentReturnType_;
    currentReturnType_ = fn.returnType;
    for (auto& st : fn.body) {
        checkStmt(*st);
    }
    currentReturnType_ = savedReturn;

    // 無 以外の関数は全経路で値を返すこと (言語仕様 §5)。不返 は対象外。
    if (fn.returnType && fn.returnType->kind != Type::Kind::Void && !fn.isNoreturn &&
        !alwaysReturns(fn.body)) {
        error(fn.line, fn.col, "E0011",
            "function " + fn.name + " does not return a value on every path");
    }

    exitScope();
}

// 文の列が必ず 歸 に到達して戻るか。当 (while) は 0 回かもしれないので数えない。
bool TypeChecker::alwaysReturns(const std::vector<StmtPtr>& block) const {
    for (auto& st : block) {
        if (!st) continue;
        switch (st->kind) {
            case Stmt::Kind::ReturnStmt:
                return true;
            case Stmt::Kind::IfStmt:
                if (st->hasElse && alwaysReturns(st->thenBlock) && alwaysReturns(st->elseBlock))
                    return true;
                break;
            case Stmt::Kind::UnsafeBlock:
                if (alwaysReturns(st->unsafeBody)) return true;
                break;
            default:
                break;
        }
    }
    return false;
}

void TypeChecker::checkExternal(const FunctionDecl& fn) {
    // External functions don't have a body to check
    // But we can verify the signature is well-formed
    for (auto& p : fn.params) {
        if (!p.type) {
            error(fn.line, fn.col, "E0001",
                "external function " + fn.name + " has parameter without type");
        }
    }
}

void TypeChecker::checkConstant(const ConstantDecl& c) {
    if (c.value) {
        TypePtr vt = checkExpr(*c.value);
        if (c.type && vt && !vt->isSameAs(*c.type)) {
            if (!coerceLiteral(c.value, c.type)) {
                error(c.line, c.col, "E0001",
                    "constant " + c.name + " value type " + vt->toString() +
                    " does not match declared type " + c.type->toString());
            }
        }
    }
}

void TypeChecker::checkStruct(const StructDecl& s) {
    for (auto& f : s.fields) {
        if (!f.type) {
            error(s.line, s.col, "E0001",
                "struct " + s.name + " field " + f.name + " has no type");
        }
    }
}

} // namespace chokanbun
