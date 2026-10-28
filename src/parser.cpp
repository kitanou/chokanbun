#include "parser.h"
#include <iostream>
#include <cctype>

namespace chokanbun {

namespace {

// 型付き機械命令の引数 (レジスタ名・障壁の領域・TLB 操作名) は ASCII 小文字・数字・_ のみ。
// 文字列をそのままアセンブラへ渡すため、ここで文字種を絞って注入を防ぐ。
bool isMachineName(const std::string& s) {
    if (s.empty() || s.size() > 64) return false;
    for (char c : s) {
        if ((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_') continue;
        return false;
    }
    return true;
}

bool isBarrierDomain(const std::string& s) {
    static const char* kDomains[] = {
        "sy", "st", "ld", "ish", "ishst", "ishld",
        "nsh", "nshst", "nshld", "osh", "oshst", "oshld",
    };
    for (auto d : kDomains) if (s == d) return true;
    return false;
}

// オペランドを取らない TLBI 命令だけを許す (レジスタ付きは 組譯 で書く)。
// 框の種類: el1 (256 バイト・x0..x30)、el1irq (256 バイト・+248 に NZCV)、
// el0 (288 バイト・+248 NZCV、+256 ELR、+264 SPSR、+272 SP_EL0)。
bool isFrameKind(const std::string& s) {
    return s == "el1" || s == "el1irq" || s == "el0";
}

bool isTlbInvalidateOp(const std::string& s) {
    static const char* kOps[] = {
        "vmalle1", "vmalle1is", "vmalls12e1", "vmalls12e1is",
        "alle1", "alle1is", "alle2", "alle2is", "alle3", "alle3is",
        "aside1", "aside1is",
    };
    for (auto op : kOps) if (s == op) return true;
    return false;
}

} // namespace

Parser::Parser(std::vector<Token> tokens) : tokens_(std::move(tokens)) {}

bool Parser::atEnd() const { return current().kind == TokKind::Eof; }

const Token& Parser::current() const { return tokens_[pos_]; }
const Token& Parser::peek() const {
    if (pos_ + 1 < tokens_.size()) return tokens_[pos_ + 1];
    return tokens_.back();
}

Token Parser::advance() {
    Token tok = tokens_[pos_];
    if (pos_ < tokens_.size() - 1) pos_++;
    return tok;
}

bool Parser::check(TokKind kind) const { return current().kind == kind; }

bool Parser::match(TokKind kind) {
    if (check(kind)) {
        advance();
        return true;
    }
    return false;
}

bool Parser::matchAny(std::initializer_list<TokKind> kinds) {
    for (auto k : kinds) {
        if (check(k)) {
            advance();
            return true;
        }
    }
    return false;
}

Token Parser::expect(TokKind kind, const std::string& what) {
    if (check(kind)) return advance();
    error(current(), "E0008", "expected " + what + ", got " + current().text);
    hasErrors_ = true;
    return current();
}

void Parser::error(const Token& tok, const std::string& code, const std::string& msg) {
    diags_.emplace_back(Diagnostic::Level::Error, tok.line, tok.col, code, msg);
    hasErrors_ = true;
}

void Parser::errorAt(uint32_t line, uint32_t col, const std::string& code, const std::string& msg) {
    diags_.emplace_back(Diagnostic::Level::Error, line, col, code, msg);
    hasErrors_ = true;
}

Module Parser::parseModule() {
    Module mod;
    mod.name = "main";
    while (!atEnd()) {
        Decl d = parseDeclaration();
        mod.decls.push_back(std::move(d));
    }
    return mod;
}

Decl Parser::parseDeclaration() {
    Decl d;
    Token tok = current();

    // Check for attributes (公開, 不返, 節, 記號)
    auto isAttr = [&]() {
        return check(TokKind::Gongkai) || check(TokKind::Bufan) ||
               check(TokKind::Jie) || check(TokKind::Jihao) ||
               check(TokKind::Luo) || check(TokKind::Qi);
    };
    if (isAttr()) {
        bool isPublic = false;
        bool isNoreturn = false;
        bool isNaked = false;
        uint64_t alignment = 0;
        std::string section;
        std::string symbol;

        // Parse all attributes
        while (isAttr()) {
            if (match(TokKind::Gongkai)) {
                isPublic = true;
            } else if (match(TokKind::Luo)) {
                isNaked = true;
            } else if (match(TokKind::Qi)) {
                // 齊 2048
                if (check(TokKind::IntegerLit)) {
                    alignment = std::stoull(current().value);
                    advance();
                } else {
                    error(current(), "E0008", "expected alignment after 齊");
                    hasErrors_ = true;
                    advance();
                }
            } else if (match(TokKind::Bufan)) {
                isNoreturn = true;
            } else if (match(TokKind::Jie)) {
                // 節「.text.boot」
                if (check(TokKind::Ident)) {
                    section = current().value;
                    advance();
                } else {
                    error(current(), "E0008", "expected section name after 節");
                    hasErrors_ = true;
                    advance();
                }
            } else if (match(TokKind::Jihao)) {
                // 記號「ascii_symbol」
                if (check(TokKind::Ident)) {
                    symbol = current().value;
                    advance();
                } else {
                    error(current(), "E0008", "expected symbol name after 記號");
                    hasErrors_ = true;
                    advance();
                }
            }
        }

        // Now expect 術曰 or 外術曰
        bool isExt = false;
        if (match(TokKind::ShuJie)) {
            isExt = false;
        } else if (match(TokKind::WaiShuJie)) {
            isExt = true;
        } else {
            error(current(), "E0008", "expected 術曰 or 外術曰 after attributes");
            hasErrors_ = true;
            Decl bad;
            bad.kind = Decl::Kind::Function;
            return bad;
        }

        auto fn = parseFunctionAfterKeyword(isExt);
        fn->isPublic = isPublic;
        fn->isNoreturn = isNoreturn;
        fn->isNaked = isNaked;
        fn->alignment = alignment;
        fn->section = section;
        if (!symbol.empty()) fn->symbolName = symbol;

        d.function = fn;
        d.kind = isExt ? Decl::Kind::External : Decl::Kind::Function;
        return d;
    }

    // Regular function: 術曰「name」...
    if (match(TokKind::ShuJie)) {
        d.kind = Decl::Kind::Function;
        d.function = parseFunctionAfterKeyword(false);
        return d;
    }

    // External function: 外術曰「name」...
    if (match(TokKind::WaiShuJie)) {
        d.kind = Decl::Kind::External;
        d.function = parseFunctionAfterKeyword(true);
        return d;
    }

    // Struct: 構「name」...終構
    if (match(TokKind::Gong)) {
        d.kind = Decl::Kind::Struct;
        d.structDecl = parseStruct();
        return d;
    }

    // Alias: 別名「name」為 type
    if (match(TokKind::Bieming)) {
        d.kind = Decl::Kind::Alias;
        d.alias = parseAlias();
        return d;
    }

    // Constant: 常「name」之type 為 expr
    if (match(TokKind::Chang)) {
        d.kind = Decl::Kind::Constant;
        d.constant = parseConstant();
        return d;
    }

    error(tok, "E0008", "expected declaration, got " + tok.text);
    hasErrors_ = true;
    advance(); // skip to avoid infinite loop
    return d;
}

// Parse function body after 術曰/外術曰 keyword has been consumed
std::shared_ptr<FunctionDecl> Parser::parseFunctionAfterKeyword(bool isExternal) {
    auto fn = std::make_shared<FunctionDecl>();
    fn->isExternal = isExternal;
    fn->line = current().line;
    fn->col = current().col;

    // 「name」
    if (check(TokKind::Ident)) {
        fn->name = current().value;
        advance();
    } else {
        error(current(), "E0008", "expected function name");
        hasErrors_ = true;
        advance();
    }

    // Parameters: 受「name」之type ...
    while (match(TokKind::Shou)) {
        Param p;
        if (check(TokKind::Ident)) {
            p.name = current().value;
            advance();
        } else {
            error(current(), "E0008", "expected parameter name");
            hasErrors_ = true;
            advance();
        }
        expect(TokKind::Zhi, "之");
        p.type = parseType();
        fn->params.push_back(std::move(p));
    }

    // Return type: 返 type
    if (match(TokKind::Fan)) {
        fn->returnType = parseType();
    } else {
        fn->returnType = Type::Void();
    }

    if (!isExternal) {
        // Body
        fn->body = parseBlock();
        // 終術
        expect(TokKind::Shu, "終術");
    } else {
        // Optional: 記號「symbol」
        if (match(TokKind::Jihao)) {
            if (check(TokKind::Ident)) {
                fn->symbolName = current().value;
                advance();
            } else {
                error(current(), "E0008", "expected symbol name");
                hasErrors_ = true;
                advance();
            }
        }
        // 終外術
        expect(TokKind::WaiShu, "終外術");
    }

    return fn;
}

// parseFunction: expects 術曰 to be present (for backward compat)
std::shared_ptr<FunctionDecl> Parser::parseFunction() {
    expect(TokKind::ShuJie, "術曰");
    return parseFunctionAfterKeyword(false);
}

std::shared_ptr<FunctionDecl> Parser::parseExternal() {
    expect(TokKind::WaiShuJie, "外術曰");
    return parseFunctionAfterKeyword(true);
}

std::shared_ptr<AliasDecl> Parser::parseAlias() {
    auto a = std::make_shared<AliasDecl>();
    a->line = current().line;
    a->col = current().col;

    // 別名「name」為 type
    if (check(TokKind::Ident)) {
        a->name = current().value;
        advance();
    } else {
        error(current(), "E0008", "expected alias name");
        hasErrors_ = true;
        advance();
    }
    expect(TokKind::Wei, "為");
    a->type = parseType();

    return a;
}

std::shared_ptr<ConstantDecl> Parser::parseConstant() {
    auto c = std::make_shared<ConstantDecl>();
    c->line = current().line;
    c->col = current().col;

    // 常「name」之type 為 expr
    if (check(TokKind::Ident)) {
        c->name = current().value;
        advance();
    } else {
        error(current(), "E0008", "expected constant name");
        hasErrors_ = true;
        advance();
    }
    expect(TokKind::Zhi, "之");
    c->type = parseType();
    expect(TokKind::Wei, "為");
    c->value = parseExpr();

    return c;
}

std::shared_ptr<StructDecl> Parser::parseStruct() {
    auto s = std::make_shared<StructDecl>();
    s->line = current().line;
    s->col = current().col;

    // 構「name」
    if (check(TokKind::Ident)) {
        s->name = current().value;
        advance();
    } else {
        error(current(), "E0008", "expected struct name");
        hasErrors_ = true;
        advance();
    }

    // Fields: 「name」之type ...
    while (!check(TokKind::ZhongGong) && !atEnd()) {
        StructField f;
        if (check(TokKind::Ident)) {
            f.name = current().value;
            advance();
        } else {
            error(current(), "E0008", "expected field name");
            hasErrors_ = true;
            advance();
            break;
        }
        expect(TokKind::Zhi, "之");
        f.type = parseType();
        s->fields.push_back(std::move(f));
    }

    expect(TokKind::ZhongGong, "終構");

    return s;
}

TypePtr Parser::parseType() {
    if (match(TokKind::Zhenwei)) return Type::Bool();
    if (match(TokKind::WufuBa)) return Type::U8();
    if (match(TokKind::WufuShiliu)) return Type::U16();
    if (match(TokKind::WufuSaner)) return Type::U32();
    if (match(TokKind::WufuLiushi)) return Type::U64();
    if (match(TokKind::YoufuBa)) return Type::I8();
    if (match(TokKind::YoufuShiliu)) return Type::I16();
    if (match(TokKind::YoufuSaner)) return Type::I32();
    if (match(TokKind::YoufuLiushi)) return Type::I64();
    if (match(TokKind::Wu)) return Type::Void();

    if (match(TokKind::ZhiZheng)) {
        // 指標〈type〉
        expect(TokKind::LeftAngle, "〈");
        TypePtr inner = parseType();
        expect(TokKind::RightAngle, "〉");
        return Type::Pointer(inner);
    }

    if (match(TokKind::LieZhen)) {
        // 列陣〈type, length〉
        expect(TokKind::LeftAngle, "〈");
        TypePtr elem = parseType();
        expect(TokKind::Comma, ",");
        if (check(TokKind::IntegerLit)) {
            uint64_t len = std::stoull(current().value);
            advance();
            expect(TokKind::RightAngle, "〉");
            return Type::Array(elem, len);
        } else {
            error(current(), "E0008", "expected array length");
            hasErrors_ = true;
            expect(TokKind::RightAngle, "〉");
            return Type::Array(elem, 0);
        }
    }

    // Struct type reference
    if (check(TokKind::Ident)) {
        std::string name = current().value;
        advance();
        return Type::Struct(name);
    }

    error(current(), "E0008", "expected type");
    hasErrors_ = true;
    advance();
    return Type::Void();
}

std::vector<StmtPtr> Parser::parseBlock() {
    std::vector<StmtPtr> stmts;
    while (!atEnd()) {
        if (check(TokKind::Shu) || check(TokKind::ZhongRuo) ||
            check(TokKind::ZhongDang) || check(TokKind::ZhongXian) ||
            check(TokKind::FouZe)) {
            break;
        }
        StmtPtr s = parseStatement();
        if (s) stmts.push_back(std::move(s));
    }
    return stmts;
}

StmtPtr Parser::parseStatement() {
    Token tok = current();
    StmtPtr s = std::make_shared<Stmt>();
    s->line = tok.line;
    s->col = tok.col;

    if (match(TokKind::She)) {
        s->kind = Stmt::Kind::LocalDecl;
        // 設「name」之type 為 expr
        if (check(TokKind::Ident)) {
            s->varName = current().value;
            advance();
        } else {
            error(current(), "E0008", "expected variable name");
            hasErrors_ = true;
            advance();
        }
        expect(TokKind::Zhi, "之");
        s->varType = parseType();
        expect(TokKind::Wei, "為");
        s->init = parseExpr();
        return s;
    }

    if (match(TokKind::Zhi2)) {
        s->kind = Stmt::Kind::Assign;
        // 置 lvalue 為 expr
        s->target = parseLvalue();
        expect(TokKind::Wei, "為");
        s->value = parseExpr();
        return s;
    }

    if (match(TokKind::Xing)) {
        s->kind = Stmt::Kind::CallStmt;
        // 行「name」以(args)
        if (check(TokKind::Ident)) {
            s->callee = current().value;
            advance();
        } else {
            error(current(), "E0008", "expected function name");
            hasErrors_ = true;
            advance();
        }
        // 以 is lexed as Ident (not a keyword)
        if (check(TokKind::Ident) && current().value == "以") {
            advance();
        } else {
            error(current(), "E0008", "expected 以 after function name");
            hasErrors_ = true;
        }
        expect(TokKind::LeftParen, "(");
        if (!check(TokKind::RightParen)) {
            s->args.push_back(parseExpr());
            while (match(TokKind::Comma)) {
                s->args.push_back(parseExpr());
            }
        }
        expect(TokKind::RightParen, ")");
        return s;
    }

    if (match(TokKind::Ruo)) {
        s->kind = Stmt::Kind::IfStmt;
        s->cond = parseExpr();
        expect(TokKind::Ze, "則");
        s->thenBlock = parseBlock();
        if (match(TokKind::FouZe)) {
            s->hasElse = true;
            s->elseBlock = parseBlock();
        }
        expect(TokKind::ZhongRuo, "終若");
        return s;
    }

    if (match(TokKind::Dang)) {
        s->kind = Stmt::Kind::WhileStmt;
        s->cond = parseExpr();
        expect(TokKind::Ze, "則");
        s->body = parseBlock();
        expect(TokKind::ZhongDang, "終當");
        return s;
    }

    if (match(TokKind::Gui)) {
        s->kind = Stmt::Kind::ReturnStmt;
        if (!check(TokKind::Shu) && !check(TokKind::ZhongRuo) &&
            !check(TokKind::ZhongDang) && !check(TokKind::ZhongXian) &&
            !check(TokKind::FouZe) && !atEnd()) {
            s->hasRetVal = true;
            s->retVal = parseExpr();
        }
        return s;
    }

    if (match(TokKind::Xian)) {
        s->kind = Stmt::Kind::UnsafeBlock;
        s->unsafeBody = parseBlock();
        expect(TokKind::ZhongXian, "終險");
        return s;
    }

    // Expression statement (e.g., volatile write)
    s->kind = Stmt::Kind::ExprStmt;
    s->expr = parseExpr();
    return s;
}

ExprPtr Parser::parseExpr() {
    return parseOrExpr();
}

ExprPtr Parser::parseOrExpr() {
    ExprPtr left = parseAndExpr();
    while (check(TokKind::Huo)) {
        advance();
        auto e = std::make_shared<Expr>();
        e->kind = Expr::Kind::BinOp;
        e->opText = "或";
        e->left = left;
        e->right = parseAndExpr();
        e->line = left->line;
        e->col = left->col;
        left = e;
    }
    return left;
}

ExprPtr Parser::parseAndExpr() {
    ExprPtr left = parseBitOrExpr();
    while (check(TokKind::Qie)) {
        advance();
        auto e = std::make_shared<Expr>();
        e->kind = Expr::Kind::BinOp;
        e->opText = "且";
        e->left = left;
        e->right = parseBitOrExpr();
        e->line = left->line;
        e->col = left->col;
        left = e;
    }
    return left;
}

ExprPtr Parser::parseBitOrExpr() {
    ExprPtr left = parseBitXorExpr();
    while (check(TokKind::WeiHuo)) {
        advance();
        auto e = std::make_shared<Expr>();
        e->kind = Expr::Kind::BinOp;
        e->opText = "位或";
        e->left = left;
        e->right = parseBitXorExpr();
        e->line = left->line;
        e->col = left->col;
        left = e;
    }
    return left;
}

ExprPtr Parser::parseBitXorExpr() {
    ExprPtr left = parseBitAndExpr();
    while (check(TokKind::WeiYi)) {
        advance();
        auto e = std::make_shared<Expr>();
        e->kind = Expr::Kind::BinOp;
        e->opText = "位異";
        e->left = left;
        e->right = parseBitAndExpr();
        e->line = left->line;
        e->col = left->col;
        left = e;
    }
    return left;
}

ExprPtr Parser::parseBitAndExpr() {
    ExprPtr left = parseEqualityExpr();
    while (check(TokKind::WeiYu)) {
        advance();
        auto e = std::make_shared<Expr>();
        e->kind = Expr::Kind::BinOp;
        e->opText = "位與";
        e->left = left;
        e->right = parseEqualityExpr();
        e->line = left->line;
        e->col = left->col;
        left = e;
    }
    return left;
}

ExprPtr Parser::parseEqualityExpr() {
    ExprPtr left = parseRelationalExpr();
    if (check(TokKind::DengYu) || check(TokKind::BuDeng)) {
        std::string op = current().text;
        advance();
        auto e = std::make_shared<Expr>();
        e->kind = Expr::Kind::BinOp;
        e->opText = op;
        e->left = left;
        e->right = parseRelationalExpr();
        e->line = left->line;
        e->col = left->col;
        left = e;
        // 比較演算子は連鎖不可 (言語仕様 §4)
        if (check(TokKind::DengYu) || check(TokKind::BuDeng)) {
            error(current(), "E0008", "comparison operators cannot be chained: " + current().text);
        }
    }
    return left;
}

ExprPtr Parser::parseRelationalExpr() {
    ExprPtr left = parseShiftExpr();
    if (check(TokKind::XiaoYu) || check(TokKind::XiaoDeng) ||
        check(TokKind::DaYu) || check(TokKind::DaDeng)) {
        std::string op = current().text;
        advance();
        auto e = std::make_shared<Expr>();
        e->kind = Expr::Kind::BinOp;
        e->opText = op;
        e->left = left;
        e->right = parseShiftExpr();
        e->line = left->line;
        e->col = left->col;
        left = e;
        // 比較演算子は連鎖不可 (言語仕様 §4)
        if (check(TokKind::XiaoYu) || check(TokKind::XiaoDeng) ||
            check(TokKind::DaYu) || check(TokKind::DaDeng)) {
            error(current(), "E0008", "comparison operators cannot be chained: " + current().text);
        }
    }
    return left;
}

ExprPtr Parser::parseShiftExpr() {
    ExprPtr left = parseAdditiveExpr();
    while (check(TokKind::ZuoYi) || check(TokKind::YouYi)) {
        std::string op = current().text;
        advance();
        auto e = std::make_shared<Expr>();
        e->kind = Expr::Kind::BinOp;
        e->opText = op;
        e->left = left;
        e->right = parseAdditiveExpr();
        e->line = left->line;
        e->col = left->col;
        left = e;
    }
    return left;
}

ExprPtr Parser::parseAdditiveExpr() {
    ExprPtr left = parseMultiplicativeExpr();
    while (check(TokKind::Jia) || check(TokKind::Jian)) {
        std::string op = current().text;
        advance();
        auto e = std::make_shared<Expr>();
        e->kind = Expr::Kind::BinOp;
        e->opText = op;
        e->left = left;
        e->right = parseMultiplicativeExpr();
        e->line = left->line;
        e->col = left->col;
        left = e;
    }
    return left;
}

ExprPtr Parser::parseMultiplicativeExpr() {
    ExprPtr left = parseUnaryExpr();
    while (check(TokKind::Cheng) || check(TokKind::Chu) || check(TokKind::Yu)) {
        std::string op = current().text;
        advance();
        auto e = std::make_shared<Expr>();
        e->kind = Expr::Kind::BinOp;
        e->opText = op;
        e->left = left;
        e->right = parseUnaryExpr();
        e->line = left->line;
        e->col = left->col;
        left = e;
    }
    return left;
}

ExprPtr Parser::parseUnaryExpr() {
    if (check(TokKind::Fu) || check(TokKind::Fei) || check(TokKind::WeiFei)) {
        std::string op = current().text;
        advance();
        auto e = std::make_shared<Expr>();
        e->kind = Expr::Kind::UnaryOp;
        e->unaryOp = op;
        e->operand = parseUnaryExpr();
        e->line = e->operand->line;
        e->col = e->operand->col;
        return e;
    }
    return parsePrimary();
}

ExprPtr Parser::parsePrimary() {
    Token tok = current();
    ExprPtr e = std::make_shared<Expr>();
    e->line = tok.line;
    e->col = tok.col;

    // Integer literal
    if (match(TokKind::IntegerLit)) {
        e->kind = Expr::Kind::IntegerLit;
        // 10進、または 0x + 16進 (言語仕様 §2)。u64 を超える値は E0010。
        const std::string& lit = tok.value;
        bool hex = lit.size() > 2 && lit[0] == '0' && (lit[1] == 'x' || lit[1] == 'X');
        try {
            e->intValue = std::stoull(lit, nullptr, hex ? 16 : 10);
        } catch (const std::exception&) {
            error(tok, "E0010", "integer literal " + lit + " does not fit in 64 bits");
            e->intValue = 0;
        }
        e->isNegative = false;
        return e;
    }

    // Bool literals
    if (match(TokKind::Zhen)) {
        e->kind = Expr::Kind::BoolLit;
        e->boolValue = true;
        return e;
    }
    if (match(TokKind::Wei2)) {
        e->kind = Expr::Kind::BoolLit;
        e->boolValue = false;
        return e;
    }

    // Null
    if (match(TokKind::Kong)) {
        e->kind = Expr::Kind::NullLit;
        return e;
    }

    // String literal
    if (match(TokKind::StringLit)) {
        e->kind = Expr::Kind::StringLit;
        e->strValue = tok.value;
        return e;
    }

    // Ident
    if (check(TokKind::Ident)) {
        e->kind = Expr::Kind::Ident;
        e->identName = tok.value;
        advance();
        return e;
    }

    // Parenthesized expression
    if (match(TokKind::LeftParen)) {
        e = parseExpr();
        expect(TokKind::RightParen, ")");
        return e;
    }

    // 取址(lvalue)
    if (match(TokKind::QuZhi)) {
        e->kind = Expr::Kind::AddrOf;
        expect(TokKind::LeftParen, "(");
        // The lvalue can be a string literal, ident, deref, field, or element
        if (check(TokKind::StringLit)) {
            // 取址(『string』)
            Token str = advance();
            e->addend = std::make_shared<Expr>();
            e->addend->kind = Expr::Kind::StringLit;
            e->addend->strValue = str.value;
            e->addend->line = str.line;
            e->addend->col = str.col;
            expect(TokKind::RightParen, ")");
            return e;
        }
        e->addend = parseLvalue();
        expect(TokKind::RightParen, ")");
        return e;
    }

    // 取值(expr)
    if (match(TokKind::QuZhi2)) {
        e->kind = Expr::Kind::Deref;
        expect(TokKind::LeftParen, "(");
        e->pointee = parseExpr();
        expect(TokKind::RightParen, ")");
        return e;
    }

    // 呼「name」以(args)
    if (match(TokKind::Hu)) {
        e->kind = Expr::Kind::Call;
        if (check(TokKind::Ident)) {
            e->callee = current().value;
            advance();
        } else {
            error(current(), "E0008", "expected function name after 呼");
            hasErrors_ = true;
            advance();
        }
        // 以 is lexed as Ident
        if (check(TokKind::Ident) && current().value == "以") {
            advance();
        } else {
            error(current(), "E0008", "expected 以 after function name");
            hasErrors_ = true;
        }
        expect(TokKind::LeftParen, "(");
        if (!check(TokKind::RightParen)) {
            e->args.push_back(parseExpr());
            while (match(TokKind::Comma)) {
                e->args.push_back(parseExpr());
            }
        }
        expect(TokKind::RightParen, ")");
        return e;
    }

    // 轉〈type〉(expr)
    if (match(TokKind::Zhuan)) {
        e->kind = Expr::Kind::Cast;
        expect(TokKind::LeftAngle, "〈");
        e->castTo = parseType();
        expect(TokKind::RightAngle, "〉");
        expect(TokKind::LeftParen, "(");
        e->castFrom = parseExpr();
        expect(TokKind::RightParen, ")");
        return e;
    }

    // 讀揮發〈type〉(ptr)
    if (match(TokKind::DuHuiFa)) {
        e->kind = Expr::Kind::VolatileRead;
        expect(TokKind::LeftAngle, "〈");
        e->volType = parseType();
        expect(TokKind::RightAngle, "〉");
        expect(TokKind::LeftParen, "(");
        e->volPtr = parseExpr();
        expect(TokKind::RightParen, ")");
        return e;
    }

    // 寫揮發〈type〉(ptr, val)
    if (match(TokKind::XieHuiFa)) {
        e->kind = Expr::Kind::VolatileWrite;
        expect(TokKind::LeftAngle, "〈");
        e->volType = parseType();
        expect(TokKind::RightAngle, "〉");
        expect(TokKind::LeftParen, "(");
        e->volPtr = parseExpr();
        expect(TokKind::Comma, ",");
        e->volVal = parseExpr();
        expect(TokKind::RightParen, ")");
        return e;
    }

    // 障壁〈kind〉()
    if (match(TokKind::ZhangBei)) {
        e->kind = Expr::Kind::Fence;
        expect(TokKind::LeftAngle, "〈");
        if (check(TokKind::Ident)) {
            e->fenceKind = current().value;
            advance();
        }
        expect(TokKind::RightAngle, "〉");
        expect(TokKind::LeftParen, "(");
        expect(TokKind::RightParen, ")");
        return e;
    }

    // 組譯〈type〉(『文』, 『制約』 {, expr})
    if (match(TokKind::ZuYi)) {
        e->kind = Expr::Kind::Asm;
        expect(TokKind::LeftAngle, "〈");
        e->asmType = parseType();
        expect(TokKind::RightAngle, "〉");
        expect(TokKind::LeftParen, "(");
        if (check(TokKind::StringLit)) {
            e->asmText = current().value;
            advance();
        } else {
            error(current(), "E0008", "expected assembly text string after 組譯(");
            hasErrors_ = true;
        }
        expect(TokKind::Comma, ",");
        if (check(TokKind::StringLit)) {
            e->asmConstraints = current().value;
            advance();
        } else {
            error(current(), "E0008", "expected constraint string in 組譯");
            hasErrors_ = true;
        }
        while (match(TokKind::Comma)) {
            e->args.push_back(parseExpr());
        }
        expect(TokKind::RightParen, ")");
        return e;
    }

    // ---- 型付き機械命令 (言語仕様 §6) ----
    // 系統讀〈『reg』〉()
    if (match(TokKind::XiTongDu)) {
        e->kind = Expr::Kind::Machine;
        e->machineOp = Expr::MachineOp::SysRegRead;
        expect(TokKind::LeftAngle, "〈");
        if (check(TokKind::StringLit)) {
            e->asmText = current().value;
            advance();
        } else {
            error(current(), "E0008", "系統讀 requires a register name string");
            hasErrors_ = true;
        }
        if (!isMachineName(e->asmText)) {
            error(current(), "E0008", "invalid system register name: " + e->asmText);
            hasErrors_ = true;
        }
        expect(TokKind::RightAngle, "〉");
        expect(TokKind::LeftParen, "(");
        expect(TokKind::RightParen, ")");
        return e;
    }

    // 系統寫〈『reg』〉(値)
    if (match(TokKind::XiTongXie)) {
        e->kind = Expr::Kind::Machine;
        e->machineOp = Expr::MachineOp::SysRegWrite;
        expect(TokKind::LeftAngle, "〈");
        if (check(TokKind::StringLit)) {
            e->asmText = current().value;
            advance();
        } else {
            error(current(), "E0008", "系統寫 requires a register name string");
            hasErrors_ = true;
        }
        if (!isMachineName(e->asmText)) {
            error(current(), "E0008", "invalid system register name: " + e->asmText);
            hasErrors_ = true;
        }
        expect(TokKind::RightAngle, "〉");
        expect(TokKind::LeftParen, "(");
        e->args.push_back(parseExpr());
        expect(TokKind::RightParen, ")");
        return e;
    }

    // 記憶障壁〈『領域』〉() -> dsb
    if (match(TokKind::JiyiZhangbi)) {
        e->kind = Expr::Kind::Machine;
        e->machineOp = Expr::MachineOp::MemBarrier;
        expect(TokKind::LeftAngle, "〈");
        if (check(TokKind::StringLit)) {
            e->asmText = current().value;
            advance();
        } else {
            error(current(), "E0008", "記憶障壁 requires a domain string");
            hasErrors_ = true;
        }
        if (!isBarrierDomain(e->asmText)) {
            error(current(), "E0008", "unknown DSB domain: " + e->asmText);
            hasErrors_ = true;
        }
        expect(TokKind::RightAngle, "〉");
        expect(TokKind::LeftParen, "(");
        expect(TokKind::RightParen, ")");
        return e;
    }

    // 命令障壁() -> isb
    if (match(TokKind::MinglingZhangbi)) {
        e->kind = Expr::Kind::Machine;
        e->machineOp = Expr::MachineOp::InstrBarrier;
        expect(TokKind::LeftParen, "(");
        expect(TokKind::RightParen, ")");
        return e;
    }

    // 臺無效〈『操作』〉() -> tlbi
    if (match(TokKind::TaiWuXiao)) {
        e->kind = Expr::Kind::Machine;
        e->machineOp = Expr::MachineOp::TlbInvalidate;
        expect(TokKind::LeftAngle, "〈");
        if (check(TokKind::StringLit)) {
            e->asmText = current().value;
            advance();
        } else {
            error(current(), "E0008", "臺無效 requires a TLB operation string");
            hasErrors_ = true;
        }
        if (!isTlbInvalidateOp(e->asmText)) {
            error(current(), "E0008", "unknown TLBI operation: " + e->asmText);
            hasErrors_ = true;
        }
        expect(TokKind::RightAngle, "〉");
        expect(TokKind::LeftParen, "(");
        expect(TokKind::RightParen, ")");
        return e;
    }

    // 資清(址) -> dc cvau
    if (match(TokKind::ZiQing)) {
        e->kind = Expr::Kind::Machine;
        e->machineOp = Expr::MachineOp::DataCacheClean;
        expect(TokKind::LeftParen, "(");
        e->args.push_back(parseExpr());
        expect(TokKind::RightParen, ")");
        return e;
    }

    // 令清() -> ic iallu
    if (match(TokKind::LingQing)) {
        e->kind = Expr::Kind::Machine;
        e->machineOp = Expr::MachineOp::InstrCacheClean;
        expect(TokKind::LeftParen, "(");
        expect(TokKind::RightParen, ")");
        return e;
    }

    // 待事象() -> wfi
    if (match(TokKind::DaiShiXiang)) {
        e->kind = Expr::Kind::Machine;
        e->machineOp = Expr::MachineOp::WaitEvent;
        expect(TokKind::LeftParen, "(");
        expect(TokKind::RightParen, ")");
        return e;
    }

    // 漢令(番 [, 引...]) -> svc #0 (漢令 ABI v0.1)
    if (match(TokKind::HanLing)) {
        e->kind = Expr::Kind::Machine;
        e->machineOp = Expr::MachineOp::Syscall;
        expect(TokKind::LeftParen, "(");
        if (!check(TokKind::RightParen)) {
            e->args.push_back(parseExpr());
            while (match(TokKind::Comma)) {
                e->args.push_back(parseExpr());
            }
        }
        expect(TokKind::RightParen, ")");
        return e;
    }

    // 異常令(即値) -> brk #imm
    if (match(TokKind::YiChangLing)) {
        e->kind = Expr::Kind::Machine;
        e->machineOp = Expr::MachineOp::Breakpoint;
        expect(TokKind::LeftParen, "(");
        e->args.push_back(parseExpr());
        expect(TokKind::RightParen, ")");
        return e;
    }

    // 框存〈『種』〉() / 框復〈『種』〉() -> 例外の框の退避・復帰
    if (check(TokKind::KuangCun) || check(TokKind::KuangFu)) {
        bool save = check(TokKind::KuangCun);
        std::string name = save ? "框存" : "框復";
        advance();
        e->kind = Expr::Kind::Machine;
        e->machineOp = save ? Expr::MachineOp::FrameSave : Expr::MachineOp::FrameRestore;
        expect(TokKind::LeftAngle, "〈");
        if (check(TokKind::StringLit)) {
            e->asmText = current().value;
            advance();
        } else {
            error(current(), "E0008", name + " requires a frame kind string");
            hasErrors_ = true;
        }
        if (!isFrameKind(e->asmText)) {
            error(current(), "E0008", "unknown frame kind: " + e->asmText);
            hasErrors_ = true;
        }
        expect(TokKind::RightAngle, "〉");
        expect(TokKind::LeftParen, "(");
        expect(TokKind::RightParen, ")");
        return e;
    }

    // 向量表〈『既定』,『核割込』,『下位同期』,『下位割込』〉() -> ベクタ表 16 項
    if (match(TokKind::XiangLiangBiao)) {
        e->kind = Expr::Kind::Machine;
        e->machineOp = Expr::MachineOp::VectorTable;
        expect(TokKind::LeftAngle, "〈");
        for (int i = 0; i < 4; i++) {
            if (i > 0) expect(TokKind::Comma, ",");
            std::string sym;
            if (check(TokKind::StringLit)) {
                sym = current().value;
                advance();
            } else {
                error(current(), "E0008", "向量表 requires four handler symbol strings");
                hasErrors_ = true;
            }
            if (!isMachineName(sym)) {
                error(current(), "E0008", "invalid vector handler symbol: " + sym);
                hasErrors_ = true;
            }
            e->asmText += (i > 0 ? "," : "") + sym;
        }
        expect(TokKind::RightAngle, "〉");
        expect(TokKind::LeftParen, "(");
        expect(TokKind::RightParen, ")");
        return e;
    }

    // 入口の定型 (呼出・框移・框待・棧置): 記号の文字列を取る。引種は none|sp|esr_sp|esr_elr_ret。
    if (check(TokKind::HuChu) || check(TokKind::KuangYi) || check(TokKind::KuangDai) || check(TokKind::ZhanZhi)) {
        TokKind k = current().kind;
        std::string name = k == TokKind::HuChu ? "呼出" : k == TokKind::KuangYi ? "框移" : k == TokKind::KuangDai ? "框待" : "棧置";
        int want = k == TokKind::ZhanZhi ? 1 : 2;
        advance();
        e->kind = Expr::Kind::Machine;
        e->machineOp = k == TokKind::HuChu ? Expr::MachineOp::CallSym : k == TokKind::KuangYi ? Expr::MachineOp::FrameSwitch
                     : k == TokKind::KuangDai ? Expr::MachineOp::FramePark : Expr::MachineOp::StackSet;
        expect(TokKind::LeftAngle, "〈");
        for (int i = 0; i < want; i++) {
            if (i > 0) expect(TokKind::Comma, ",");
            std::string sym;
            if (check(TokKind::StringLit)) {
                sym = current().value;
                advance();
            } else {
                error(current(), "E0008", name + " requires symbol strings");
                hasErrors_ = true;
            }
            bool ok = isMachineName(sym);
            if (ok && i == 1 && k == TokKind::HuChu)
                ok = sym == "none" || sym == "sp" || sym == "esr_sp" || sym == "esr_elr_ret";
            if (!ok) {
                error(current(), "E0008", "invalid " + name + " operand: " + sym);
                hasErrors_ = true;
            }
            e->asmText += (i > 0 ? "," : "") + sym;
        }
        expect(TokKind::RightAngle, "〉");
        expect(TokKind::LeftParen, "(");
        expect(TokKind::RightParen, ")");
        return e;
    }

    // 令止(番 [, 引0]) -> svc して戻らない
    if (match(TokKind::LingZhi)) {
        e->kind = Expr::Kind::Machine;
        e->machineOp = Expr::MachineOp::SvcHalt;
        expect(TokKind::LeftParen, "(");
        e->args.push_back(parseExpr());
        if (match(TokKind::Comma)) e->args.push_back(parseExpr());
        expect(TokKind::RightParen, ")");
        return e;
    }

    // 永停() / 入民()
    if (check(TokKind::YongTing) || check(TokKind::RuMin) || check(TokKind::JiangWei)) {
        TokKind k = current().kind;
        advance();
        e->kind = Expr::Kind::Machine;
        e->machineOp = k == TokKind::YongTing ? Expr::MachineOp::HaltLoop
                     : k == TokKind::RuMin ? Expr::MachineOp::EnterUser : Expr::MachineOp::DropToEL1;
        expect(TokKind::LeftParen, "(");
        expect(TokKind::RightParen, ")");
        return e;
    }

    // 例外歸() -> eret
    if (match(TokKind::LiWaiGui)) {
        e->kind = Expr::Kind::Machine;
        e->machineOp = Expr::MachineOp::ExceptionReturn;
        expect(TokKind::LeftParen, "(");
        expect(TokKind::RightParen, ")");
        return e;
    }

    // 長度(expr)
    if (match(TokKind::ChangDu)) {
        e->kind = Expr::Kind::StrLen;
        expect(TokKind::LeftParen, "(");
        e->index = parseExpr();
        expect(TokKind::RightParen, ")");
        return e;
    }

    // 欄(lvalue, 「field」)
    if (match(TokKind::Lan)) {
        e->kind = Expr::Kind::FieldAccess;
        expect(TokKind::LeftParen, "(");
        e->base = parseLvalue();
        expect(TokKind::Comma, ",");
        if (check(TokKind::Ident)) {
            e->fieldName = current().value;
            advance();
        } else {
            error(current(), "E0008", "expected field name");
            hasErrors_ = true;
            advance();
        }
        expect(TokKind::RightParen, ")");
        return e;
    }

    // 項(lvalue, expr)
    if (match(TokKind::Xiang)) {
        e->kind = Expr::Kind::ElemAccess;
        expect(TokKind::LeftParen, "(");
        e->base = parseLvalue();
        expect(TokKind::Comma, ",");
        e->index = parseExpr();
        expect(TokKind::RightParen, ")");
        return e;
    }

    error(tok, "E0008", "unexpected token in expression: " + tok.text);
    hasErrors_ = true;
    advance();
    return e;
}

ExprPtr Parser::parseLvalue() {
    Token tok = current();
    ExprPtr e = std::make_shared<Expr>();
    e->line = tok.line;
    e->col = tok.col;

    // ident
    if (check(TokKind::Ident)) {
        e->kind = Expr::Kind::Ident;
        e->identName = tok.value;
        advance();
        return e;
    }

    // 取值(expr)
    if (match(TokKind::QuZhi2)) {
        e->kind = Expr::Kind::Deref;
        expect(TokKind::LeftParen, "(");
        e->pointee = parseExpr();
        expect(TokKind::RightParen, ")");
        return e;
    }

    // 欄(lvalue, 「field」)
    if (match(TokKind::Lan)) {
        e->kind = Expr::Kind::FieldAccess;
        expect(TokKind::LeftParen, "(");
        e->base = parseLvalue();
        expect(TokKind::Comma, ",");
        if (check(TokKind::Ident)) {
            e->fieldName = current().value;
            advance();
        } else {
            error(current(), "E0008", "expected field name");
            hasErrors_ = true;
            advance();
        }
        expect(TokKind::RightParen, ")");
        return e;
    }

    // 項(lvalue, expr)
    if (match(TokKind::Xiang)) {
        e->kind = Expr::Kind::ElemAccess;
        expect(TokKind::LeftParen, "(");
        e->base = parseLvalue();
        expect(TokKind::Comma, ",");
        e->index = parseExpr();
        expect(TokKind::RightParen, ")");
        return e;
    }

    error(tok, "E0008", "expected lvalue, got " + tok.text);
    hasErrors_ = true;
    advance();
    return e;
}

} // namespace chokanbun
