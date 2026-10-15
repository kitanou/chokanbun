#include "parser.h"
#include <iostream>
#include <cctype>

namespace chokanbun {

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
    error(current(), "E0002", "expected " + what + ", got " + current().text);
    hasErrors_ = true;
    return current();
}

void Parser::error(const Token& tok, const std::string& code, const std::string& msg) {
    diags_.emplace_back(Diagnostic::Level::Error, tok.line, tok.col, code, msg);
}

void Parser::errorAt(uint32_t line, uint32_t col, const std::string& code, const std::string& msg) {
    diags_.emplace_back(Diagnostic::Level::Error, line, col, code, msg);
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

    // Check for attributes (公開, 不返, 節)
    if (check(TokKind::Gongkai) || check(TokKind::Bufan) || check(TokKind::Jie)) {
        // Parse attributes, then expect 術曰 or 外術曰
        d.kind = Decl::Kind::Function;
        auto fn = std::make_shared<FunctionDecl>();
        fn->line = tok.line;
        fn->col = tok.col;

        // Parse all attributes
        while (check(TokKind::Gongkai) || check(TokKind::Bufan) || check(TokKind::Jie)) {
            if (match(TokKind::Gongkai)) {
                fn->isPublic = true;
            } else if (match(TokKind::Bufan)) {
                fn->isNoreturn = true;
            } else if (match(TokKind::Jie)) {
                // 節「.text.boot」
                if (check(TokKind::Ident)) {
                    fn->section = current().value;
                    advance();
                } else {
                    error(current(), "E0002", "expected section name after 節");
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
            error(current(), "E0002", "expected 術曰 or 外術曰 after attributes");
            hasErrors_ = true;
            return d;
        }

        *fn = *parseFunctionAfterKeyword(isExt);
        d.function = fn;
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

    error(tok, "E0002", "expected declaration, got " + tok.text);
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
        error(current(), "E0002", "expected function name");
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
            error(current(), "E0002", "expected parameter name");
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
                error(current(), "E0002", "expected symbol name");
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
        error(current(), "E0002", "expected alias name");
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
        error(current(), "E0002", "expected constant name");
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
        error(current(), "E0002", "expected struct name");
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
            error(current(), "E0002", "expected field name");
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
            error(current(), "E0002", "expected array length");
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

    error(current(), "E0002", "expected type");
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
            error(current(), "E0002", "expected variable name");
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
            error(current(), "E0002", "expected function name");
            hasErrors_ = true;
            advance();
        }
        // 以 is lexed as Ident (not a keyword)
        if (check(TokKind::Ident) && current().value == "以") {
            advance();
        } else {
            error(current(), "E0002", "expected 以 after function name");
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
    while (check(TokKind::DengYu) || check(TokKind::BuDeng)) {
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
    }
    return left;
}

ExprPtr Parser::parseRelationalExpr() {
    ExprPtr left = parseShiftExpr();
    while (check(TokKind::XiaoYu) || check(TokKind::XiaoDeng) ||
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
        e->intValue = std::stoull(tok.value);
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
        if (match(TokKind::StringLit)) {
            // 取址(『string』)
            e->addend = std::make_shared<Expr>();
            e->addend->kind = Expr::Kind::StringLit;
            e->addend->strValue = current().value;
            e->addend->line = current().line;
            e->addend->col = current().col;
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
            error(current(), "E0002", "expected function name after 呼");
            hasErrors_ = true;
            advance();
        }
        // 以 is lexed as Ident
        if (check(TokKind::Ident) && current().value == "以") {
            advance();
        } else {
            error(current(), "E0002", "expected 以 after function name");
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

    // 長度(expr)
    if (match(TokKind::ChangDu)) {
        e->kind = Expr::Kind::StrLen;
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
            error(current(), "E0002", "expected field name");
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

    error(tok, "E0002", "unexpected token in expression: " + tok.text);
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
            error(current(), "E0002", "expected field name");
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

    error(tok, "E0002", "expected lvalue, got " + tok.text);
    hasErrors_ = true;
    advance();
    return e;
}

} // namespace chokanbun
