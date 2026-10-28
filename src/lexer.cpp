#include "lexer.h"
#include <cstdint>
#include <cstring>

namespace chokanbun {

Lexer::Lexer(std::string source)
    : src_(std::move(source)) {
    // Validate UTF-8
    size_t i = 0;
    while (i < src_.size()) {
        uint8_t c = static_cast<uint8_t>(src_[i]);
        size_t len;
        if (c < 0x80) len = 1;
        else if ((c & 0xE0) == 0xC0) len = 2;
        else if ((c & 0xF0) == 0xE0) len = 3;
        else if ((c & 0xF8) == 0xF0) len = 4;
        else {
            error(1, 1, "E0009", "invalid UTF-8 byte");
            failed_ = true;
            return;
        }
        // Check continuation bytes
        if (len > 1) {
            if (i + len > src_.size()) {
                error(1, 1, "E0009", "truncated UTF-8 sequence");
                failed_ = true;
                return;
            }
            for (size_t j = 1; j < len; j++) {
                uint8_t cb = static_cast<uint8_t>(src_[i + j]);
                if ((cb & 0xC0) != 0x80) {
                    error(1, 1, "E0009", "invalid UTF-8 continuation byte");
                    failed_ = true;
                    return;
                }
            }
        }
        i += len;
    }
}

void Lexer::error(uint32_t line, uint32_t col, const std::string& code, const std::string& msg) {
    diags_.emplace_back(Diagnostic::Level::Error, line, col, code, msg);
}

bool Lexer::atEnd() const { return pos_ >= src_.size(); }

uint8_t Lexer::peek() const {
    if (atEnd()) return 0;
    return static_cast<uint8_t>(src_[pos_]);
}

uint8_t Lexer::peekAt(size_t offset) const {
    if (pos_ + offset >= src_.size()) return 0;
    return static_cast<uint8_t>(src_[pos_ + offset]);
}

uint8_t Lexer::advance() {
    uint8_t c = peek();
    pos_++;
    if (c == '\n') {
        line_++;
        col_ = 1;
    } else {
        col_++;
    }
    return c;
}

bool Lexer::match(uint8_t expected) {
    if (atEnd() || peek() != expected) return false;
    advance();
    return true;
}

bool Lexer::matchBytes(const std::string& expected) {
    if (pos_ + expected.size() > src_.size()) return false;
    if (src_.compare(pos_, expected.size(), expected) != 0) return false;
    for (size_t i = 0; i < expected.size(); i++) {
        advance();
    }
    return true;
}

char32_t Lexer::decodeUTF8At(size_t& i) const {
    if (i >= src_.size()) return 0xFFFD;
    uint8_t c = static_cast<uint8_t>(src_[i]);
    char32_t cp;
    size_t len;
    if (c < 0x80) { cp = c; len = 1; }
    else if ((c & 0xE0) == 0xC0) {
        if (i + 1 >= src_.size()) return 0xFFFD;
        cp = ((c & 0x1F) << 6) | (static_cast<uint8_t>(src_[i+1]) & 0x3F);
        len = 2;
    }
    else if ((c & 0xF0) == 0xE0) {
        if (i + 2 >= src_.size()) return 0xFFFD;
        cp = ((c & 0x0F) << 12) | ((static_cast<uint8_t>(src_[i+1]) & 0x3F) << 6) | (static_cast<uint8_t>(src_[i+2]) & 0x3F);
        len = 3;
    }
    else if ((c & 0xF8) == 0xF0) {
        if (i + 3 >= src_.size()) return 0xFFFD;
        cp = ((c & 0x07) << 18) | ((static_cast<uint8_t>(src_[i+1]) & 0x3F) << 12) |
             ((static_cast<uint8_t>(src_[i+2]) & 0x3F) << 6) | (static_cast<uint8_t>(src_[i+3]) & 0x3F);
        len = 4;
    }
    else return 0xFFFD;
    i += len;
    return cp;
}

bool Lexer::isIdentStart(char32_t cp) const {
    if (cp >= 0x4E00 && cp <= 0x9FFF) return true;
    if (cp >= 0x3400 && cp <= 0x4DBF) return true;
    if (cp >= 0x20000 && cp <= 0x2A6DF) return true;
    if (cp >= 0xF900 && cp <= 0xFAFF) return true;
    if (cp >= 0x3040 && cp <= 0x30FF) return true;
    return false;
}

bool Lexer::isIdentPart(char32_t cp) const {
    // Inside 「」 identifiers may hold CJK, ASCII letters, digits, '_' and '.'.
    // ASCII is required so that 記號「ascii_symbol」 (spec §7) can name linker
    // symbols, and so identifiers stay usable from hand-written assembly.
    if (cp >= 0x0030 && cp <= 0x0039) return true; // 0-9
    if (cp >= 0x0041 && cp <= 0x005A) return true; // A-Z
    if (cp >= 0x0061 && cp <= 0x007A) return true; // a-z
    if (cp == 0x005F) return true;                 // _
    if (cp == 0x002E) return true;                 // . (節「.text.boot」 のセクション名用)
    return isIdentStart(cp);
}

bool Lexer::isDigit(uint8_t c) const { return c >= '0' && c <= '9'; }

bool Lexer::isHexDigit(uint8_t c) const {
    return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
}

void Lexer::skipWhitespaceAndComments() {
    while (!atEnd()) {
        uint8_t c = peek();
        if (c == ' ' || c == '\t' || c == '\r' || c == '\n') {
            advance();
        } else if (c == 0xE8) {
            // Check for 註 (E8 A8 BB) - line comment (spec §2)
            if (pos_ + 2 < src_.size() &&
                static_cast<uint8_t>(src_[pos_+1]) == 0xA8 &&
                static_cast<uint8_t>(src_[pos_+2]) == 0xBB) {
                while (!atEnd() && peek() != '\n') advance();
                if (!atEnd()) advance();
            } else {
                break;
            }
        } else {
            break;
        }
    }
}

// All keywords in the language (reserved words, valid only outside identifiers)
static const std::vector<std::pair<std::string, TokKind>>& allKeywords() {
    static const std::vector<std::pair<std::string, TokKind>> kws = {
        {"術曰", TokKind::ShuJie}, {"終術", TokKind::Shu},
        {"外術曰", TokKind::WaiShuJie}, {"終外術", TokKind::WaiShu},
        {"受", TokKind::Shou}, {"之", TokKind::Zhi},
        {"返", TokKind::Fan}, {"歸", TokKind::Gui},
        {"若", TokKind::Ruo}, {"則", TokKind::Ze},
        {"否則", TokKind::FouZe}, {"終若", TokKind::ZhongRuo},
        {"當", TokKind::Dang}, {"終當", TokKind::ZhongDang},
        {"設", TokKind::She}, {"置", TokKind::Zhi2}, {"行", TokKind::Xing},
        {"險", TokKind::Xian}, {"終險", TokKind::ZhongXian},
        {"構", TokKind::Gong}, {"終構", TokKind::ZhongGong},
        {"別名", TokKind::Bieming}, {"為", TokKind::Wei},
        {"常", TokKind::Chang}, {"公開", TokKind::Gongkai},
        {"不返", TokKind::Bufan}, {"節", TokKind::Jie},
        {"記號", TokKind::Jihao}, {"裸", TokKind::Luo}, {"齊", TokKind::Qi},
        {"無符八", TokKind::WufuBa}, {"無符十六", TokKind::WufuShiliu},
        {"無符三二", TokKind::WufuSaner}, {"無符六四", TokKind::WufuLiushi},
        {"有符八", TokKind::YoufuBa}, {"有符十六", TokKind::YoufuShiliu},
        {"有符三二", TokKind::YoufuSaner}, {"有符六四", TokKind::YoufuLiushi},
        {"真偽", TokKind::Zhenwei}, {"無", TokKind::Wu},
        {"指標", TokKind::ZhiZheng}, {"列陣", TokKind::LieZhen},
        {"空", TokKind::Kong}, {"真", TokKind::Zhen}, {"偽", TokKind::Wei2},
        {"取址", TokKind::QuZhi}, {"取值", TokKind::QuZhi2},
        {"呼", TokKind::Hu}, {"轉", TokKind::Zhuan},
        {"讀揮發", TokKind::DuHuiFa}, {"寫揮發", TokKind::XieHuiFa},
        {"障壁", TokKind::ZhangBei}, {"組譯", TokKind::ZuYi},
        {"系統讀", TokKind::XiTongDu}, {"系統寫", TokKind::XiTongXie},
        {"記憶障壁", TokKind::JiyiZhangbi}, {"命令障壁", TokKind::MinglingZhangbi},
        {"臺無效", TokKind::TaiWuXiao}, {"資清", TokKind::ZiQing},
        {"令清", TokKind::LingQing}, {"待事象", TokKind::DaiShiXiang},
        {"漢令", TokKind::HanLing}, {"異常令", TokKind::YiChangLing},
        {"框存", TokKind::KuangCun}, {"框復", TokKind::KuangFu}, {"例外歸", TokKind::LiWaiGui}, {"向量表", TokKind::XiangLiangBiao},
        {"呼出", TokKind::HuChu}, {"框移", TokKind::KuangYi}, {"框待", TokKind::KuangDai}, {"令止", TokKind::LingZhi},
        {"棧置", TokKind::ZhanZhi}, {"永停", TokKind::YongTing}, {"入民", TokKind::RuMin},
        {"長度", TokKind::ChangDu},
        {"欄", TokKind::Lan}, {"項", TokKind::Xiang},
        {"加", TokKind::Jia}, {"減", TokKind::Jian},
        {"乘", TokKind::Cheng}, {"除", TokKind::Chu}, {"餘", TokKind::Yu},
        {"左移", TokKind::ZuoYi}, {"右移", TokKind::YouYi},
        {"小於", TokKind::XiaoYu}, {"小等", TokKind::XiaoDeng},
        {"大於", TokKind::DaYu}, {"大等", TokKind::DaDeng},
        {"等於", TokKind::DengYu}, {"不等", TokKind::BuDeng},
        {"位與", TokKind::WeiYu}, {"位異", TokKind::WeiYi},
        {"位或", TokKind::WeiHuo}, {"且", TokKind::Qie},
        {"或", TokKind::Huo}, {"非", TokKind::Fei},
        {"位非", TokKind::WeiFei}, {"負", TokKind::Fu},
    };
    return kws;
}

// Try to match the longest keyword at position pos in src.
// Returns true and sets out to the matched keyword if one is found.
static bool matchKeywordAt(const std::string& src, size_t pos, std::string& out) {
    size_t bestLen = 0;
    const std::string* bestKw = nullptr;
    for (const auto& [kw, kind] : allKeywords()) {
        size_t kwBytes = kw.size();
        if (pos + kwBytes > src.size()) continue;
        if (src.compare(pos, kwBytes, kw) == 0) {
            if (kwBytes > bestLen) {
                bestLen = kwBytes;
                bestKw = &kw;
            }
        }
    }
    if (bestKw) {
        out = *bestKw;
        return true;
    }
    return false;
}

// Map a keyword string to its TokKind
static TokKind keywordToTokKind(const std::string& kw) {
    for (const auto& [k, kind] : allKeywords()) {
        if (k == kw) return kind;
    }
    return TokKind::Ident;
}

// Read a CJK word (sequence of CJK characters, not brackets).
// Per spec §2: reserved words are only valid outside identifiers.
// A CJK word is split at keyword boundaries using longest-match.
// E.g. "之指標" → 之 (keyword) + 指標 (keyword)
// E.g. "外術曰" → 外術曰 (keyword, longest match)
// E.g. "核外輸出" → single identifier (no keyword match)
Token Lexer::readWord() {
    uint32_t startLine = line_;
    uint32_t startCol = col_;
    uint32_t startByte = static_cast<uint32_t>(pos_);


    size_t start = pos_;

    // Read the full CJK sequence to determine the longest keyword match.
    // Stop at any byte that is not part of a CJK character:
    //  - ASCII bytes (< 0x80) like '(', ')', ','
    //  - bracket sequences (「」『』〈〉)
    //  - whitespace
    size_t scan = pos_;
    size_t endOfWord = scan;
    while (scan < src_.size()) {
        uint8_t c = static_cast<uint8_t>(src_[scan]);
        // Stop at ASCII (punctuation, digits, etc.)
        if (c < 0x80) break;
        // Stop at continuation bytes (shouldn't happen if we're at a valid start)
        if ((c & 0xC0) == 0x80) break;
        // Stop at brackets
        if (c == 0xE3) {
            uint8_t b1 = (scan + 1 < src_.size()) ? static_cast<uint8_t>(src_[scan+1]) : 0;
            uint8_t b2 = (scan + 2 < src_.size()) ? static_cast<uint8_t>(src_[scan+2]) : 0;
            if (b1 == 0x80 && (b2 == 0x88 || b2 == 0x89 || b2 == 0x8C || b2 == 0x8D || b2 == 0x8E || b2 == 0x8F)) {
                break;
            }
            // Other E3 sequences (e.g. other 0xE3 CJK chars like 々 U+3005)
            // Check if it's a CJK char that could be part of a word
            size_t i = scan;
            char32_t cp = decodeUTF8At(i);
            if (cp == 0xFFFD || !isIdentStart(cp)) break;
            endOfWord = scan + (i - scan);
            scan = endOfWord;
            continue;
        }
        // CJK Unified (E4-E9), Compatibility (EF), Extension B (F0)
        // Note: decodeUTF8At modifies i by reference, so save scan first.
        size_t i = scan;
        char32_t cp = decodeUTF8At(i);
        if (cp == 0xFFFD || !isIdentStart(cp)) break;

        // i has been advanced past the sequence; compute length from original scan
        size_t seqLen = i - scan;
        endOfWord = scan + seqLen;
        scan = endOfWord;
    }

    std::string fullWord = src_.substr(start, endOfWord - start);

    if (fullWord.empty()) {
        error(startLine, startCol, "E0009", "empty word");
        failed_ = true;
        advance();
        return {TokKind::Eof, "", "", startLine, startCol, startByte};
    }

    // Try longest-match keyword at the start of the word.
    // If a keyword is found, advance pos_ past it.  The caller (next())
    // will then lex the remaining CJK bytes as a separate token.
    // We return the keyword token; the rest is picked up on the next next() call.
    std::string kw;
    if (matchKeywordAt(fullWord, 0, kw)) {
        size_t kwBytes = kw.size();
        pos_ = start + kwBytes;
        // Count codepoints in the keyword to update col_
        size_t off = 0;
        while (off < kwBytes) {
            uint8_t b = static_cast<uint8_t>(fullWord[off]);
            if ((b & 0xC0) == 0x80) { off++; }
            else if ((b & 0xE0) == 0xC0) { off += 2; col_++; }
            else if ((b & 0xF0) == 0xE0) { off += 3; col_++; }
            else if ((b & 0xF8) == 0xF0) { off += 4; col_++; }
            else { off++; col_++; }
        }
        return {keywordToTokKind(kw), kw, kw, startLine, startCol, startByte};
    }

    // Not a keyword: the whole word is a bare identifier
    size_t wordBytes = fullWord.size();
    pos_ = start + wordBytes;
    size_t off = 0;
    while (off < wordBytes) {
        uint8_t b = static_cast<uint8_t>(fullWord[off]);
        if ((b & 0xC0) == 0x80) { off++; }
        else if ((b & 0xE0) == 0xC0) { off += 2; col_++; }
        else if ((b & 0xF0) == 0xE0) { off += 3; col_++; }
        else if ((b & 0xF8) == 0xF0) { off += 4; col_++; }
        else { off++; col_++; }
    }
    return {TokKind::Ident, fullWord, fullWord, startLine, startCol, startByte};
}

Token Lexer::readIdent() {
    uint32_t startLine = line_;
    uint32_t startCol = col_;
    uint32_t startByte = static_cast<uint32_t>(pos_);

    // Expect 「
    if (!matchBytes("\xE3\x80\x8C")) { // 「
        error(startLine, startCol, "E0009", "expected 「");
        failed_ = true;
        return {TokKind::Eof, "", "", startLine, startCol, startByte};
    }

    std::string inner;
    bool closed = false;
    while (!atEnd()) {
        uint8_t c = peek();
        if (c == '\n') {
            error(line_, col_, "E0009", "newline in identifier");
            failed_ = true;
            break;
        }
        if (c == 0xE3 && peekAt(1) == 0x80 && peekAt(2) == 0x8D) { // 」
            advance(); advance(); advance();
            closed = true;
            break;
        }
        size_t i = pos_;
        char32_t cp = decodeUTF8At(i);
        if (cp == 0xFFFD || !isIdentPart(cp)) {
            error(line_, col_, "E0009", "invalid character in identifier");
            failed_ = true;
            advance();
            continue;
        }
        inner.append(src_, pos_, i - pos_);
        pos_ = i;
        col_++;
    }

    if (!closed) {
        error(startLine, startCol, "E0009", "unterminated identifier");
        failed_ = true;
    }

    // Identifiers are always Ident tokens (keywords are only valid outside identifiers)
    return {TokKind::Ident, inner, inner, startLine, startCol, startByte};
}

Token Lexer::readString() {
    uint32_t startLine = line_;
    uint32_t startCol = col_;
    uint32_t startByte = static_cast<uint32_t>(pos_);

    // Expect 『
    if (!matchBytes("\xE3\x80\x8E")) { // 『
        error(startLine, startCol, "E0009", "expected 『");
        failed_ = true;
        return {TokKind::Eof, "", "", startLine, startCol, startByte};
    }

    std::string content;
    bool closed = false;
    while (!atEnd()) {
        uint8_t c = peek();
        if (c == 0xE3 && peekAt(1) == 0x80 && peekAt(2) == 0x8F) { // 』
            advance(); advance(); advance();
            closed = true;
            break;
        }
        if (c == '\\') {
            advance(); // consume backslash
            if (atEnd()) break;
            uint8_t esc = advance();
            switch (esc) {
                case 'n': content += '\n'; break;
                case 'r': content += '\r'; break;
                case 't': content += '\t'; break;
                case '\\': content += '\\'; break;
                case 0xE3: {
                    if (peekAt(0) == 0x80 && peekAt(1) == 0x8F) {
                        advance(); advance(); // consume 』
                        content.append("\xE3\x80\x8F", 3);
                    } else {
                        error(line_, col_, "E0009", "invalid escape sequence");
                        failed_ = true;
                    }
                    break;
                }
                case 'u': {
                    if (!match('{')) {
                        error(line_, col_, "E0009", "expected { after \\u");
                        failed_ = true;
                    }
                    std::string hex;
                    while (!atEnd() && isHexDigit(peek())) {
                        hex += static_cast<char>(advance());
                    }
                    if (!match('}')) {
                        error(line_, col_, "E0009", "expected } in \\u{...}");
                        failed_ = true;
                    }
                    unsigned long cp = 0;
                    for (char h : hex) {
                        cp <<= 4;
                        if (h >= '0' && h <= '9') cp += h - '0';
                        else if (h >= 'a' && h <= 'f') cp += h - 'a' + 10;
                        else if (h >= 'A' && h <= 'F') cp += h - 'A' + 10;
                    }
                    if (cp < 0x80) content += static_cast<char>(cp);
                    else if (cp < 0x800) {
                        content += static_cast<char>(0xC0 | (cp >> 6));
                        content += static_cast<char>(0x80 | (cp & 0x3F));
                    }
                    else if (cp < 0x10000) {
                        content += static_cast<char>(0xE0 | (cp >> 12));
                        content += static_cast<char>(0x80 | ((cp >> 6) & 0x3F));
                        content += static_cast<char>(0x80 | (cp & 0x3F));
                    }
                    else {
                        content += static_cast<char>(0xF0 | (cp >> 18));
                        content += static_cast<char>(0x80 | ((cp >> 12) & 0x3F));
                        content += static_cast<char>(0x80 | ((cp >> 6) & 0x3F));
                        content += static_cast<char>(0x80 | (cp & 0x3F));
                    }
                    break;
                }
                default:
                    error(line_ - 1, col_, "E0009", "invalid escape character");
                    failed_ = true;
                    break;
            }
        } else if (c == '\n') {
            error(line_, col_, "E0009", "newline in string literal");
            failed_ = true;
            advance();
        } else {
            size_t i = pos_;
            char32_t cp = decodeUTF8At(i);
            if (cp == 0xFFFD) {
                error(line_, col_, "E0009", "invalid UTF-8 in string");
                failed_ = true;
                advance();
            } else {
                content.append(src_, pos_, i - pos_);
                pos_ = i;
                col_++;
            }
        }
    }

    if (!closed) {
        error(startLine, startCol, "E0009", "unterminated string literal");
        failed_ = true;
    }

    return {TokKind::StringLit, content, content, startLine, startCol, startByte};
}

Token Lexer::readNumber() {
    uint32_t startLine = line_;
    uint32_t startCol = col_;
    uint32_t startByte = static_cast<uint32_t>(pos_);

    std::string text;

    if (peek() == '0' && peekAt(1) == 'x') {
        text += advance(); // '0'
        text += advance(); // 'x'
        while (!atEnd() && isHexDigit(peek())) {
            text += static_cast<char>(advance());
        }
    } else {
        while (!atEnd() && isDigit(peek())) {
            text += static_cast<char>(advance());
        }
    }

    return {TokKind::IntegerLit, text, text, startLine, startCol, startByte};
}

Token Lexer::readPunct() {
    uint32_t startLine = line_;
    uint32_t startCol = col_;
    uint32_t startByte = static_cast<uint32_t>(pos_);
    uint8_t c = advance();

    switch (c) {
        case '(': return {TokKind::LeftParen, "(", "(", startLine, startCol, startByte};
        case ')': return {TokKind::RightParen, ")", ")", startLine, startCol, startByte};
        case ',': return {TokKind::Comma, ",", ",", startLine, startCol, startByte};
        case 0xE3: {
            // 〈 = E3 80 88, 〉 = E3 80 89
            if (peekAt(0) == 0x80 && peekAt(1) == 0x88) {
                advance(); advance();
                return {TokKind::LeftAngle, "\xE3\x80\x88", "\xE3\x80\x88", startLine, startCol, startByte};
            }
            if (peekAt(0) == 0x80 && peekAt(1) == 0x89) {
                advance(); advance();
                return {TokKind::RightAngle, "\xE3\x80\x89", "\xE3\x80\x89", startLine, startCol, startByte};
            }
            break;
        }
        default:
            break;
    }

    error(startLine, startCol, "E0009", "unexpected character");
    failed_ = true;
    return {TokKind::Eof, "", "", startLine, startCol, startByte};
}

std::vector<Token> Lexer::tokenize() {
    tokens_.clear();
    diags_.clear();
    pos_ = 0;
    line_ = 1;
    col_ = 1;
    failed_ = false;

    while (!atEnd()) {
        skipWhitespaceAndComments();
        if (atEnd()) break;

        uint8_t c = peek();
        Token tok;

        if (c == 0xE3 && peekAt(1) == 0x80 && peekAt(2) == 0x8C) { // 「
            tok = readIdent();
        } else if (c == 0xE3 && peekAt(1) == 0x80 && peekAt(2) == 0x8E) { // 『
            tok = readString();
        } else if (isDigit(c)) {
            tok = readNumber();
        } else if (c == '(' || c == ')' || c == ',' ||
                   (c == 0xE3 && (peekAt(1) == 0x80) && (peekAt(2) == 0x88 || peekAt(2) == 0x89))) {
            tok = readPunct();
        } else if (c >= 0xE4 && c <= 0xE9) {
            // CJK Unified Ideographs (U+4E00 to U+9FFF)
            tok = readWord();
        } else if (c == 0xEF || c == 0xF0) {
            // CJK Compatibility or Extension B
            tok = readWord();
        } else {
            error(line_, col_, "E0009", "unexpected character");
            failed_ = true;
            advance();
            continue;
        }

        if (failed_) break;
        tokens_.push_back(std::move(tok));
    }

    tokens_.push_back({TokKind::Eof, "", "", line_, col_, static_cast<uint32_t>(pos_)});
    return tokens_;
}

const char* Token::kindName() const {
    switch (kind) {
        case TokKind::Ident: return "Ident";
        case TokKind::StringLit: return "StringLit";
        case TokKind::IntegerLit: return "IntegerLit";
        case TokKind::LeftParen: return "(";
        case TokKind::RightParen: return ")";
        case TokKind::Comma: return ",";
        case TokKind::LeftAngle: return "〈";
        case TokKind::RightAngle: return "〉";
        case TokKind::ShuJie: return "術曰";
        case TokKind::Shu: return "終術";
        case TokKind::WaiShuJie: return "外術曰";
        case TokKind::WaiShu: return "終外術";
        case TokKind::Shou: return "受";
        case TokKind::Zhi: return "之";
        case TokKind::Fan: return "返";
        case TokKind::Gui: return "歸";
        case TokKind::Ruo: return "若";
        case TokKind::Ze: return "則";
        case TokKind::FouZe: return "否則";
        case TokKind::ZhongRuo: return "終若";
        case TokKind::Dang: return "當";
        case TokKind::ZhongDang: return "終當";
        case TokKind::She: return "設";
        case TokKind::Zhi2: return "置";
        case TokKind::Xing: return "行";
        case TokKind::Xian: return "險";
        case TokKind::ZhongXian: return "終險";
        case TokKind::Gong: return "構";
        case TokKind::ZhongGong: return "終構";
        case TokKind::Bieming: return "別名";
        case TokKind::Wei: return "為";
        case TokKind::Chang: return "常";
        case TokKind::Gongkai: return "公開";
        case TokKind::Bufan: return "不返";
        case TokKind::Jie: return "節";
        case TokKind::Luo: return "裸";
        case TokKind::Qi: return "齊";
        case TokKind::Jihao: return "記號";
        case TokKind::WufuBa: return "無符八";
        case TokKind::WufuShiliu: return "無符十六";
        case TokKind::WufuSaner: return "無符三二";
        case TokKind::WufuLiushi: return "無符六四";
        case TokKind::YoufuBa: return "有符八";
        case TokKind::YoufuShiliu: return "有符十六";
        case TokKind::YoufuSaner: return "有符三二";
        case TokKind::YoufuLiushi: return "有符六四";
        case TokKind::Zhenwei: return "真偽";
        case TokKind::Wu: return "無";
        case TokKind::ZhiZheng: return "指標";
        case TokKind::LieZhen: return "列陣";
        case TokKind::Kong: return "空";
        case TokKind::Zhen: return "真";
        case TokKind::Wei2: return "偽";
        case TokKind::QuZhi: return "取址";
        case TokKind::QuZhi2: return "取值";
        case TokKind::Hu: return "呼";
        case TokKind::Zhuan: return "轉";
        case TokKind::DuHuiFa: return "讀揮發";
        case TokKind::XieHuiFa: return "寫揮發";
        case TokKind::ZhangBei: return "障壁";
        case TokKind::ZuYi: return "組譯";
        case TokKind::XiTongDu: return "系統讀";
        case TokKind::XiTongXie: return "系統寫";
        case TokKind::JiyiZhangbi: return "記憶障壁";
        case TokKind::MinglingZhangbi: return "命令障壁";
        case TokKind::TaiWuXiao: return "臺無效";
        case TokKind::ZiQing: return "資清";
        case TokKind::LingQing: return "令清";
        case TokKind::DaiShiXiang: return "待事象";
        case TokKind::HanLing: return "漢令";
        case TokKind::YiChangLing: return "異常令";
        case TokKind::KuangCun: return "框存";
        case TokKind::KuangFu: return "框復";
        case TokKind::LiWaiGui: return "例外歸";
        case TokKind::XiangLiangBiao: return "向量表";
        case TokKind::HuChu: return "呼出";
        case TokKind::KuangYi: return "框移";
        case TokKind::KuangDai: return "框待";
        case TokKind::LingZhi: return "令止";
        case TokKind::ZhanZhi: return "棧置";
        case TokKind::YongTing: return "永停";
        case TokKind::RuMin: return "入民";
        case TokKind::ChangDu: return "長度";
        case TokKind::Lan: return "欄";
        case TokKind::Xiang: return "項";
        case TokKind::Jia: return "加";
        case TokKind::Jian: return "減";
        case TokKind::Cheng: return "乘";
        case TokKind::Chu: return "除";
        case TokKind::Yu: return "餘";
        case TokKind::ZuoYi: return "左移";
        case TokKind::YouYi: return "右移";
        case TokKind::XiaoYu: return "小於";
        case TokKind::XiaoDeng: return "小等";
        case TokKind::DaYu: return "大於";
        case TokKind::DaDeng: return "大等";
        case TokKind::DengYu: return "等於";
        case TokKind::BuDeng: return "不等";
        case TokKind::WeiYu: return "位與";
        case TokKind::WeiYi: return "位異";
        case TokKind::WeiHuo: return "位或";
        case TokKind::Qie: return "且";
        case TokKind::Huo: return "或";
        case TokKind::Fei: return "非";
        case TokKind::WeiFei: return "位非";
        case TokKind::Fu: return "負";
        case TokKind::Eof: return "EOF";
    }
    return "?";
}

} // namespace chokanbun
