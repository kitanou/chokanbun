#pragma once
#include <string>
#include <vector>
#include <memory>
#include <variant>
#include <cstdint>

namespace chokanbun {

// Forward declarations
struct Expr;
struct Stmt;
struct Type;

using ExprPtr = std::shared_ptr<Expr>;
using StmtPtr = std::shared_ptr<Stmt>;
using TypePtr = std::shared_ptr<Type>;

// ========== Types ==========

struct Type {
    enum class Kind {
        Bool,
        I8, I16, I32, I64,
        U8, U16, U32, U64,
        Void,
        Pointer,
        Array,
        Struct,
        String,   // 『...』 literals: immutable byte array
    };

    Kind kind;
    // For Pointer
    TypePtr pointee;
    // For Array
    TypePtr element;
    uint64_t length = 0;
    // For Struct
    std::string name;

    static TypePtr Bool() { auto t = std::make_shared<Type>(); t->kind = Kind::Bool; return t; }
    static TypePtr I8() { auto t = std::make_shared<Type>(); t->kind = Kind::I8; return t; }
    static TypePtr I16() { auto t = std::make_shared<Type>(); t->kind = Kind::I16; return t; }
    static TypePtr I32() { auto t = std::make_shared<Type>(); t->kind = Kind::I32; return t; }
    static TypePtr I64() { auto t = std::make_shared<Type>(); t->kind = Kind::I64; return t; }
    static TypePtr U8() { auto t = std::make_shared<Type>(); t->kind = Kind::U8; return t; }
    static TypePtr U16() { auto t = std::make_shared<Type>(); t->kind = Kind::U16; return t; }
    static TypePtr U32() { auto t = std::make_shared<Type>(); t->kind = Kind::U32; return t; }
    static TypePtr U64() { auto t = std::make_shared<Type>(); t->kind = Kind::U64; return t; }
    static TypePtr Void() { auto t = std::make_shared<Type>(); t->kind = Kind::Void; return t; }
    static TypePtr Pointer(TypePtr inner) {
        auto t = std::make_shared<Type>();
        t->kind = Kind::Pointer;
        t->pointee = std::move(inner);
        return t;
    }
    static TypePtr Array(TypePtr elem, uint64_t len) {
        auto t = std::make_shared<Type>();
        t->kind = Kind::Array;
        t->element = std::move(elem);
        t->length = len;
        return t;
    }
    static TypePtr Struct(std::string name) {
        auto t = std::make_shared<Type>();
        t->kind = Kind::Struct;
        t->name = std::move(name);
        return t;
    }
    static TypePtr String(uint64_t len) {
        auto t = std::make_shared<Type>();
        t->kind = Kind::String;
        t->element = U8();
        t->length = len;
        return t;
    }

    std::string toString() const;
    bool isInteger() const;
    bool isSigned() const;
    bool isSameAs(const Type& other) const;
    uint64_t sizeBytes() const;  // 0 if unknown (e.g., unresolved struct)
};

// ========== Expressions ==========

struct Expr {
    enum class Kind {
        IntegerLit,
        BoolLit,
        StringLit,
        NullLit,      // 空
        Ident,
        BinOp,
        UnaryOp,
        Call,         // 呼「名」以(...)
        AddrOf,       // 取址(lvalue)
        Deref,        // 取值(expr)
        Cast,         // 轉〈type〉(expr)
        VolatileRead, // 讀揮發〈T〉(ptr)
        VolatileWrite,// 寫揮發〈T〉(ptr, val)
        Fence,        // 障壁〈種〉()
        Asm,          // 組譯〈T〉(『文』, 『制約』, 引...)
        Machine,      // 型付き機械命令 (系統讀・系統寫・記憶障壁 など)
        StrLen,       // 長度(expr)
        FieldAccess,  // 欄(lvalue, 「field」)
        ElemAccess,   // 項(lvalue, expr)
    };

    Kind kind;

    // IntegerLit
    uint64_t intValue = 0;
    bool isNegative = false;
    // BoolLit
    bool boolValue = false;
    // StringLit
    std::string strValue;
    // Ident
    std::string identName;
    // BinOp
    std::string opText;  // 加, 減, etc.
    ExprPtr left, right;
    // UnaryOp
    std::string unaryOp;  // 負, 非, 位非
    ExprPtr operand;
    // Call
    std::string callee;
    std::vector<ExprPtr> args;
    // AddrOf
    ExprPtr addend;  // the lvalue
    // Deref
    ExprPtr pointee;
    // Cast
    TypePtr castTo;
    ExprPtr castFrom;
    // VolatileRead
    TypePtr volType;
    ExprPtr volPtr;
    // VolatileWrite
    ExprPtr volVal;
    // Fence
    std::string fenceKind;
    // Asm: asmText=args[0] literal, constraints=args[1] literal, inputs=args[2..]
    std::string asmText;
    std::string asmConstraints;
    TypePtr asmType;
    // Machine: 型付き機械命令。machineOp が種類、asmText がレジスタ名・障壁の領域・TLB 操作名。
    enum class MachineOp {
        SysRegRead,       // 系統讀〈『reg』〉() -> 無符六四
        SysRegWrite,      // 系統寫〈『reg』〉(値)
        MemBarrier,       // 記憶障壁〈『領域』〉() -> dsb
        InstrBarrier,     // 命令障壁() -> isb
        TlbInvalidate,    // 臺無效〈『操作』〉() -> tlbi
        DataCacheClean,   // 資清(址) -> dc cvau
        InstrCacheClean,  // 令清() -> ic iallu
        WaitEvent,        // 待事象() -> wfi
        Syscall,          // 漢令(番 [, 引...]) -> svc #0
        Breakpoint,       // 異常令(即値) -> brk
        FrameSave,        // 框存〈『種』〉() -> sp を下げて汎用レジスタ等を框へ退避
        FrameRestore,     // 框復〈『種』〉() -> 框から復帰して sp を戻す (eret は含まない)
        ExceptionReturn,  // 例外歸() -> eret
        CallSym,          // 呼出〈『記號』,『引種』〉() -> 引数を用意して bl
        FrameSwitch,      // 框移〈『駐』,『再開』〉() -> x0 が 0 なら駐へ、でなければ sp = x0 で再開へ
        FramePark,        // 框待〈『問』,『再開』〉() -> 問 を繰り返し呼び、框が返れば再開、0 なら wfi
        SvcHalt,          // 令止(番 [, 引0]) -> svc して戻らない
        StackSet,         // 棧置〈『記号|即値』〉() -> sp を設定
        HaltLoop,         // 永停() -> wfi の無限ループ
        EnterUser,        // 入民() -> enter_el0 の本体 (eret で EL0 へ)
        Transfer,         // 移譲(入口, 引数) -> x0 = 引数 にして入口へ br する (戻らない。ローダーが核へ制御を渡す)
        DropToEL1,        // 降位() -> EL2 で始まったら EL1 へ降りる (EL1 ならそのまま。x0 は保つ)。EL3 は止まる
        VectorTable,      // 向量表〈『既定』,『核割込』,『下位同期』,『下位割込』〉() -> 16 項 × 0x80 の b 命令
    };
    MachineOp machineOp = MachineOp::SysRegRead;
    // FieldAccess
    ExprPtr base;
    std::string fieldName;
    // ElemAccess
    ExprPtr index;

    uint32_t line, col;
};

// ========== Statements ==========

struct Stmt {
    enum class Kind {
        LocalDecl,    // 設「名」之type 為 expr
        Assign,       // 置 lvalue 為 expr
        CallStmt,     // 行「名」以(...)
        IfStmt,       // 若 expr 則 block [否則 block] 終若
        WhileStmt,    // 當 expr 則 block 終當
        ReturnStmt,   // 歸 [expr]
        UnsafeBlock,  // 險 block 終險
        ExprStmt,     // a bare expression statement (for volatile writes etc.)
    };

    Kind kind;

    // LocalDecl
    std::string varName;
    TypePtr varType;
    ExprPtr init;

    // Assign
    ExprPtr target;
    ExprPtr value;

    // CallStmt
    std::string callee;
    std::vector<ExprPtr> args;

    // IfStmt
    ExprPtr cond;
    std::vector<StmtPtr> thenBlock;
    std::vector<StmtPtr> elseBlock;
    bool hasElse = false;

    // WhileStmt
    std::vector<StmtPtr> body;

    // ReturnStmt
    ExprPtr retVal;
    bool hasRetVal = false;

    // UnsafeBlock
    std::vector<StmtPtr> unsafeBody;

    // ExprStmt
    ExprPtr expr;

    uint32_t line, col;
};

// ========== Declarations ==========

struct Param {
    std::string name;
    TypePtr type;
};

struct StructField {
    std::string name;
    TypePtr type;
};

struct FunctionDecl {
    std::string name;
    std::vector<Param> params;
    TypePtr returnType = Type::Void();
    std::vector<StmtPtr> body;
    bool isExternal = false;
    std::string symbolName;  // for external: ASCII symbol
    bool isPublic = false;   // 公開
    bool isNoreturn = false; // 不返
    std::string section;     // 節「.text.boot」
    bool isNaked = false;    // 裸
    uint64_t alignment = 0;  // 齊「N」 (0 = 既定)

    uint32_t line, col;
};

struct AliasDecl {
    std::string name;
    TypePtr type;
    uint32_t line, col;
};

struct ConstantDecl {
    std::string name;
    TypePtr type;
    ExprPtr value;
    uint32_t line, col;
};

struct StructDecl {
    std::string name;
    std::vector<StructField> fields;
    uint32_t line, col;
};

using DeclPtr = std::shared_ptr<void>;

// We use a variant-based approach for declarations
struct Decl {
    enum class Kind { Function, External, Alias, Constant, Struct };
    Kind kind;
    std::shared_ptr<FunctionDecl> function;
    std::shared_ptr<AliasDecl> alias;
    std::shared_ptr<ConstantDecl> constant;
    std::shared_ptr<StructDecl> structDecl;
};

// ========== Module ==========

struct Module {
    std::string name;
    std::vector<Decl> decls;
};

} // namespace chokanbun
