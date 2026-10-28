#pragma once
#include <cstdint>
#include <string>
#include <vector>
#include <string_view>
#include <stdexcept>

namespace chokanbun {

enum class TokKind {
    // Delimiters
    Ident,        // 「名」
    StringLit,    // 『内容』
    IntegerLit,   // 123, 0xFF
    LeftParen,    // (
    RightParen,   // )
    Comma,        // ,
    LeftAngle,    // 〈
    RightAngle,   // 〉

    // Keywords
    ShuJie,       // 術曰
    Shu,          // 終術
    WaiShuJie,    // 外術曰
    WaiShu,       // 終外術
    Shou,         // 受
    Zhi,          // 之
    Fan,          // 返
    Gui,          // 歸
    Ruo,          // 若
    Ze,           // 則
    FouZe,       // 否則
    ZhongRuo,     // 終若
    Dang,         // 當
    ZhongDang,    // 終當
    She,          // 設
    Zhi2,         // 置
    Xing,         // 行
    Xian,         // 險
    ZhongXian,    // 終險
    Gong,         // 構
    ZhongGong,    // 終構
    Bieming,      // 別名
    Wei,          // 為
    Chang,        // 常
    Gongkai,      // 公開
    Bufan,        // 不返
    Jie,          // 節
    Jihao,        // 記號
    Luo,          // 裸
    Qi,           // 齊

    // Primitive type keywords
    WufuBa,       // 無符八
    WufuShiliu,   // 無符十六
    WufuSaner,    // 無符三二
    WufuLiushi,   // 無符六四
    YoufuBa,      // 有符八
    YoufuShiliu,  // 有符十六
    YoufuSaner,   // 有符三二
    YoufuLiushi,  // 有符六四
    Zhenwei,      // 真偽
    Wu,           // 無
    ZhiZheng,     // 指標
    LieZhen,      // 列陣

    // Literals
    Kong,         // 空
    Zhen,         // 真
    Wei2,         // 偽

    // Built-in function keywords
    QuZhi,        // 取址
    QuZhi2,       // 取值
    Hu,           // 呼
    Zhuan,        // 轉
    DuHuiFa,      // 讀揮發
    XieHuiFa,     // 寫揮發
    ZhangBei,     // 障壁
    ZuYi,         // 組譯
    XiTongDu,     // 系統讀
    XiTongXie,    // 系統寫
    JiyiZhangbi,  // 記憶障壁
    MinglingZhangbi, // 命令障壁
    TaiWuXiao,    // 臺無效
    ZiQing,       // 資清
    LingQing,     // 令清
    DaiShiXiang,  // 待事象
    HanLing,      // 漢令
    YiChangLing,  // 異常令
    KuangCun,     // 框存
    KuangFu,      // 框復
    LiWaiGui,     // 例外歸
    XiangLiangBiao, // 向量表
    HuChu,        // 呼出
    KuangYi,      // 框移
    KuangDai,     // 框待
    LingZhi,      // 令止
    ZhanZhi,      // 棧置
    YongTing,     // 永停
    RuMin,        // 入民
    ChangDu,      // 長度
    Lan,          // 欄
    Xiang,        // 項

    // Binary operators
    Jia,          // 加
    Jian,         // 減
    Cheng,        // 乘
    Chu,          // 除
    Yu,           // 餘
    ZuoYi,        // 左移
    YouYi,        // 右移
    XiaoYu,       // 小於
    XiaoDeng,     // 小等
    DaYu,         // 大於
    DaDeng,       // 大等
    DengYu,       // 等於
    BuDeng,       // 不等
    WeiYu,        // 位與
    WeiYi,        // 位異
    WeiHuo,       // 位或
    Qie,          // 且
    Huo,          // 或

    // Unary operators
    Fei,          // 非
    WeiFei,       // 位非
    Fu,           // 負

    Eof
};

struct Token {
    TokKind kind;
    std::string text;      // Original source text (for diagnostics)
    std::string value;     // For Ident: name without brackets; for IntegerLit: decimal string; for StringLit: decoded content
    uint32_t line;
    uint32_t col;          // Column in Unicode code points (1-based)
    uint32_t byte_offset;  // Byte offset in source (0-based)

    const char* kindName() const;
};

class Diagnostic {
public:
    enum class Level { Error, Warning };
    Diagnostic(Level level, uint32_t line, uint32_t col, std::string code, std::string message)
        : level_(level), line_(line), col_(col), code_(std::move(code)), message_(std::move(message)) {}
    Level level() const { return level_; }
    uint32_t line() const { return line_; }
    uint32_t col() const { return col_; }
    const std::string& code() const { return code_; }
    const std::string& message() const { return message_; }
    std::string format() const {
        std::string prefix = (level_ == Level::Error) ? "錯 " : "警 ";
        return prefix + code_ + ": " + std::to_string(line_) + ":" + std::to_string(col_) + ": " + message_;
    }
private:
    Level level_;
    uint32_t line_;
    uint32_t col_;
    std::string code_;
    std::string message_;
};

class Lexer {
public:
    explicit Lexer(std::string source);

    std::vector<Token> tokenize();

    const std::vector<Diagnostic>& diagnostics() const { return diags_; }

private:
    // NFC normalization
    static std::string normalizeNFC(const std::string& input);

    void error(uint32_t line, uint32_t col, const std::string& code, const std::string& msg);

    void skipWhitespaceAndComments();
    Token readIdent();
    Token readWord();
    Token readString();
    Token readNumber();
    Token readPunct();

    // Helpers
    bool atEnd() const;
    uint8_t peek() const;
    uint8_t peekAt(size_t offset) const;
    uint8_t advance();
    bool match(uint8_t expected);
    bool matchBytes(const std::string& expected);
    std::string decodeUTF8Char(size_t& i);
    char32_t decodeUTF8At(size_t& i) const;
    bool isIdentStart(char32_t cp) const;
    bool isIdentPart(char32_t cp) const;
    bool isDigit(uint8_t c) const;
    bool isHexDigit(uint8_t c) const;

    std::string src_;
    size_t pos_ = 0;
    uint32_t line_ = 1;
    uint32_t col_ = 1;  // in code points
    std::vector<Token> tokens_;
    std::vector<Diagnostic> diags_;
    bool failed_ = false;
};

} // namespace chokanbun
