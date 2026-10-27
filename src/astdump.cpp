#include "astdump.h"
#include <sstream>

namespace chokanbun {

namespace {

class Dumper {
public:
    std::string run(const Module& mod) {
        out_ << "(module\n";
        for (auto& d : mod.decls) dumpDecl(d, 1);
        out_ << ")\n";
        return out_.str();
    }

private:
    std::ostringstream out_;

    void indent(int n) { for (int i = 0; i < n; i++) out_ << "  "; }

    static std::string name(const std::string& n) { return "「" + n + "」"; }

    static std::string type(const TypePtr& t) { return t ? t->toString() : "?"; }

    void dumpDecl(const Decl& d, int lv) {
        switch (d.kind) {
            case Decl::Kind::Function:
            case Decl::Kind::External:
                dumpFunction(*d.function, lv);
                break;
            case Decl::Kind::Struct: {
                indent(lv);
                out_ << "(struct " << name(d.structDecl->name);
                for (auto& f : d.structDecl->fields)
                    out_ << " (" << name(f.name) << " " << type(f.type) << ")";
                out_ << ")\n";
                break;
            }
            case Decl::Kind::Alias:
                indent(lv);
                out_ << "(alias " << name(d.alias->name) << " " << type(d.alias->type) << ")\n";
                break;
            case Decl::Kind::Constant:
                indent(lv);
                out_ << "(const " << name(d.constant->name) << " " << type(d.constant->type) << " ";
                expr(d.constant->value);
                out_ << ")\n";
                break;
        }
    }

    void dumpFunction(const FunctionDecl& fn, int lv) {
        indent(lv);
        out_ << (fn.isExternal ? "(extern " : "(fn ") << name(fn.name);
        out_ << " (params";
        for (auto& p : fn.params) out_ << " (" << name(p.name) << " " << type(p.type) << ")";
        out_ << ") (ret " << type(fn.returnType) << ")";
        if (fn.isPublic) out_ << " public";
        if (fn.isNoreturn) out_ << " noreturn";
        if (fn.isNaked) out_ << " naked";
        if (fn.alignment) out_ << " (align " << fn.alignment << ")";
        if (!fn.section.empty()) out_ << " (section \"" << fn.section << "\")";
        if (!fn.symbolName.empty()) out_ << " (symbol \"" << fn.symbolName << "\")";
        if (fn.isExternal) {
            out_ << ")\n";
            return;
        }
        out_ << "\n";
        block(fn.body, lv + 1);
        indent(lv);
        out_ << ")\n";
    }

    void block(const std::vector<StmtPtr>& b, int lv) {
        for (auto& s : b) stmt(*s, lv);
    }

    void args(const std::vector<ExprPtr>& as) {
        for (auto& a : as) {
            out_ << " ";
            expr(a);
        }
    }

    void stmt(const Stmt& s, int lv) {
        indent(lv);
        switch (s.kind) {
            case Stmt::Kind::LocalDecl:
                out_ << "(let " << name(s.varName) << " " << type(s.varType) << " ";
                expr(s.init);
                out_ << ")\n";
                break;
            case Stmt::Kind::Assign:
                out_ << "(set ";
                expr(s.target);
                out_ << " ";
                expr(s.value);
                out_ << ")\n";
                break;
            case Stmt::Kind::CallStmt:
                out_ << "(do " << name(s.callee);
                args(s.args);
                out_ << ")\n";
                break;
            case Stmt::Kind::IfStmt:
                out_ << "(if ";
                expr(s.cond);
                out_ << "\n";
                indent(lv + 1);
                out_ << "(then\n";
                block(s.thenBlock, lv + 2);
                indent(lv + 1);
                out_ << ")\n";
                if (s.hasElse) {
                    indent(lv + 1);
                    out_ << "(else\n";
                    block(s.elseBlock, lv + 2);
                    indent(lv + 1);
                    out_ << ")\n";
                }
                indent(lv);
                out_ << ")\n";
                break;
            case Stmt::Kind::WhileStmt:
                out_ << "(while ";
                expr(s.cond);
                out_ << "\n";
                block(s.body, lv + 1);
                indent(lv);
                out_ << ")\n";
                break;
            case Stmt::Kind::ReturnStmt:
                out_ << "(return";
                if (s.hasRetVal) {
                    out_ << " ";
                    expr(s.retVal);
                }
                out_ << ")\n";
                break;
            case Stmt::Kind::UnsafeBlock:
                out_ << "(unsafe\n";
                block(s.unsafeBody, lv + 1);
                indent(lv);
                out_ << ")\n";
                break;
            case Stmt::Kind::ExprStmt:
                out_ << "(expr ";
                expr(s.expr);
                out_ << ")\n";
                break;
        }
    }

    void expr(const ExprPtr& ep) {
        if (!ep) {
            out_ << "(none)";
            return;
        }
        const Expr& e = *ep;
        switch (e.kind) {
            case Expr::Kind::IntegerLit:
                out_ << "(int " << (e.isNegative ? "-" : "") << e.intValue << ")";
                break;
            case Expr::Kind::BoolLit:
                out_ << (e.boolValue ? "真" : "偽");
                break;
            case Expr::Kind::StringLit:
                out_ << "(str 『" << e.strValue << "』)";
                break;
            case Expr::Kind::NullLit:
                out_ << "空";
                break;
            case Expr::Kind::Ident:
                out_ << name(e.identName);
                break;
            case Expr::Kind::BinOp:
                out_ << "(" << e.opText << " ";
                expr(e.left);
                out_ << " ";
                expr(e.right);
                out_ << ")";
                break;
            case Expr::Kind::UnaryOp:
                out_ << "(" << e.unaryOp << " ";
                expr(e.operand);
                out_ << ")";
                break;
            case Expr::Kind::Call:
                out_ << "(呼 " << name(e.callee);
                args(e.args);
                out_ << ")";
                break;
            case Expr::Kind::AddrOf:
                out_ << "(取址 ";
                expr(e.addend);
                out_ << ")";
                break;
            case Expr::Kind::Deref:
                out_ << "(取值 ";
                expr(e.pointee);
                out_ << ")";
                break;
            case Expr::Kind::Cast:
                out_ << "(轉 " << type(e.castTo) << " ";
                expr(e.castFrom);
                out_ << ")";
                break;
            case Expr::Kind::VolatileRead:
                out_ << "(讀揮發 " << type(e.volType) << " ";
                expr(e.volPtr);
                out_ << ")";
                break;
            case Expr::Kind::VolatileWrite:
                out_ << "(寫揮發 " << type(e.volType) << " ";
                expr(e.volPtr);
                out_ << " ";
                expr(e.volVal);
                out_ << ")";
                break;
            case Expr::Kind::Fence:
                out_ << "(障壁 " << e.fenceKind << ")";
                break;
            case Expr::Kind::Asm:
                out_ << "(組譯 " << type(e.asmType) << " \"" << e.asmText << "\" \"" << e.asmConstraints << "\"";
                for (auto& a : e.args) { out_ << " "; expr(a); }
                out_ << ")";
                break;
            case Expr::Kind::Machine: {
                static const char* kNames[] = {
                    "系統讀", "系統寫", "記憶障壁", "命令障壁", "臺無效",
                    "資清", "令清", "待事象", "漢令", "異常令",
                    "框存", "框復", "例外歸",
                };
                out_ << "(" << kNames[static_cast<int>(e.machineOp)];
                if (!e.asmText.empty()) out_ << " \"" << e.asmText << "\"";
                for (auto& a : e.args) { out_ << " "; expr(a); }
                out_ << ")";
                break;
            }
            case Expr::Kind::StrLen:
                out_ << "(長度 ";
                expr(e.index);
                out_ << ")";
                break;
            case Expr::Kind::FieldAccess:
                out_ << "(欄 ";
                expr(e.base);
                out_ << " " << name(e.fieldName) << ")";
                break;
            case Expr::Kind::ElemAccess:
                out_ << "(項 ";
                expr(e.base);
                out_ << " ";
                expr(e.index);
                out_ << ")";
                break;
        }
    }
};

} // namespace

std::string dumpModule(const Module& mod) {
    return Dumper().run(mod);
}

} // namespace chokanbun
