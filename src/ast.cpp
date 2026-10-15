#include "ast.h"

namespace chokanbun {

std::string Type::toString() const {
    switch (kind) {
        case Kind::Bool: return "真偽";
        case Kind::I8: return "有符八";
        case Kind::I16: return "有符十六";
        case Kind::I32: return "有符三二";
        case Kind::I64: return "有符六四";
        case Kind::U8: return "無符八";
        case Kind::U16: return "無符十六";
        case Kind::U32: return "無符三二";
        case Kind::U64: return "無符六四";
        case Kind::Void: return "無";
        case Kind::Pointer: return "指標〈" + (pointee ? pointee->toString() : "?") + "〉";
        case Kind::Array: return "列陣〈" + (element ? element->toString() : "?") + "," + std::to_string(length) + "〉";
        case Kind::Struct: return name;
        case Kind::String: return "列陣〈無符八," + std::to_string(length) + "〉";
    }
    return "?";
}

bool Type::isInteger() const {
    switch (kind) {
        case Kind::I8: case Kind::I16: case Kind::I32: case Kind::I64:
        case Kind::U8: case Kind::U16: case Kind::U32: case Kind::U64:
            return true;
        default:
            return false;
    }
}

bool Type::isSigned() const {
    switch (kind) {
        case Kind::I8: case Kind::I16: case Kind::I32: case Kind::I64:
            return true;
        default:
            return false;
    }
}

bool Type::isSameAs(const Type& other) const {
    if (kind != other.kind) return false;
    switch (kind) {
        case Kind::Pointer:
            return pointee && other.pointee && pointee->isSameAs(*other.pointee);
        case Kind::Array:
            return length == other.length && element && other.element && element->isSameAs(*other.element);
        case Kind::Struct:
            return name == other.name;
        case Kind::String:
            return length == other.length;
        default:
            return true;
    }
}

uint64_t Type::sizeBytes() const {
    switch (kind) {
        case Kind::Bool: return 1;
        case Kind::I8: case Kind::U8: return 1;
        case Kind::I16: case Kind::U16: return 2;
        case Kind::I32: case Kind::U32: return 4;
        case Kind::I64: case Kind::U64: return 8;
        case Kind::Void: return 0;
        case Kind::Pointer: return 8;
        case Kind::Array:
            if (!element) return 0;
            return element->sizeBytes() * length;
        case Kind::Struct:
        case Kind::String:
            return 0; // unknown without layout info
    }
    return 0;
}

} // namespace chokanbun
