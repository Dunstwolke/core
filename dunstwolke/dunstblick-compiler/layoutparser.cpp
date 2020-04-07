#include "layoutparser.hpp"
#include "FlexLexer.h"

#include <cassert>
#include <gsl/gsl>
#include <map>
#include <stdexcept>
#include <string>
#include <variant>
#include <vector>
// #include <xstd/format>
// #include <xstd/resource>

using UISize = dunstblick_Size;
using UIPoint = dunstblick_Point;

struct UISizeAutoTag
{};
struct UISizeExpandTag
{};
//                             "auto",        "expand",        px,  percent
using UISizeDef = std::variant<UISizeAutoTag, UISizeExpandTag, int, float>;
static_assert(std::is_same_v<std::variant_alternative_t<0, UISizeDef>, UISizeAutoTag>);
static_assert(std::is_same_v<std::variant_alternative_t<1, UISizeDef>, UISizeExpandTag>);
static_assert(std::is_same_v<std::variant_alternative_t<2, UISizeDef>, int>);
static_assert(std::is_same_v<std::variant_alternative_t<3, UISizeDef>, float>);

using UISizeList = std::vector<UISizeDef>;

inline bool operator==(UISizeExpandTag, UISizeExpandTag)
{
    return true;
}
inline bool operator!=(UISizeExpandTag, UISizeExpandTag)
{
    return false;
}

inline bool operator==(UISizeAutoTag, UISizeAutoTag)
{
    return true;
}
inline bool operator!=(UISizeAutoTag, UISizeAutoTag)
{
    return false;
}

#include "enums.hpp"

#define INCLUDE_PARSER_FIELDS
#include "parser-info.hpp"
#undef INCLUDE_PARSER_FIELDS

#include <iostream>

struct ParseError
{
    int line, column;
    std::string message;
};

using ErrorList = std::vector<ParseError>;

static std::string toString(LexerTokenType type)
{
    switch (type) {
        case LexerTokenType::identifier:
            return "identifier";
        case LexerTokenType::integer:
            return "integer";
        case LexerTokenType::number:
            return "number";
        case LexerTokenType::openBrace:
            return "opening brace";
        case LexerTokenType::closeBrace:
            return "closing brace";
        case LexerTokenType::openParens:
            return "opening parens";
        case LexerTokenType::closeParens:
            return "closing parens";
        case LexerTokenType::colon:
            return "colon";
        case LexerTokenType::semiColon:
            return "semicolon";
        case LexerTokenType::comma:
            return "comma";
        case LexerTokenType::string:
            return "string";
        case LexerTokenType::percentage:
            return "percentage";
        case LexerTokenType::eof:
            return "<end of file>";
        case LexerTokenType::invalid:
            return "<invalid token>";
    }
    return "???";
}

LayoutParser::LayoutParser() {}

struct Lexer
{
    FlexLexer * lexer;

    std::optional<Token> peeked_token; // 0…1 element buffer

    Lexer(std::istream & input) : lexer(LayoutParser::AllocLexer(&input))
    {
        assert(lexer != nullptr);
    }
    ~Lexer()
    {
        LayoutParser::FreeLexer(lexer);
    }

    std::optional<Token> peek()
    {
        if (peeked_token)
            return peeked_token;
        peeked_token = LayoutParser::Lex(lexer);
        return peeked_token;
    }

    std::optional<Token> lex()
    {
        if (peeked_token) {
            auto result = peeked_token;
            peeked_token.reset();
            return result;
        }
        return LayoutParser::Lex(lexer);
    }

    std::string accept(LexerTokenType type)
    {
        auto tok = lex();
        if (not tok or tok->type != type) {
            if (not tok)
                throw std::runtime_error("unexpected end of file!");
            throw std::runtime_error("expected " + toString(type) + ", found: '" + tok->text + "'!");
        }
        return tok->text;
    }

    std::variant<std::string, uint32_t> acceptStringOrNumber()
    {
        auto tok = lex();
        if (not tok)
            throw std::runtime_error("unexpected end of file!");
        if (tok->type == LexerTokenType::string)
            return tok->text;
        if (tok->type == LexerTokenType::integer)
            return uint32_t(std::strtoul(tok->text.c_str(), nullptr, 10));
        throw std::runtime_error("expected string or integer!");
    }
};

static int lex_int(Lexer & lexer)
{
    auto text = lexer.accept(LexerTokenType::integer);
    return gsl::narrow<int>(strtol(text.c_str(), nullptr, 10));
}

static void write_varint(std::ostream & output, uint32_t value)
{
    char buf[5];

    size_t maxidx = 4;
    for (size_t n = 0; n < 5; n++) {
        char & c = buf[4 - n];
        c = (value >> (7 * n)) & 0x7F;
        if (c != 0)
            maxidx = 4 - n;
        if (n > 0)
            c |= 0x80;
    }

    assert(maxidx < 5);
    output.write(buf + maxidx, std::streamsize(5 - maxidx));
}

template <typename T>
static void write_enum(std::ostream & output, T const & value)
{
    static_assert(std::is_enum_v<T> or std::is_same_v<T, uint8_t>);
    static_assert(sizeof(T) == 1);
    output.write(reinterpret_cast<char const *>(&value), 1);
}

static void write_string(std::ostream & output, std::string const & text)
{
    write_varint(output, gsl::narrow<uint32_t>(text.size()));
    output.write(text.c_str(), gsl::narrow<std::streamsize>(text.size()));
}

static void write_number(std::ostream & output, float value)
{
    output.write(reinterpret_cast<char const *>(&value), sizeof(value));
}

// static float lex_number(FlexLexer * lexer)
//{
//	auto text = Accept(lexer, LexerTokenType::number);
//	return strtof(text.c_str(), nullptr);
//}

static void parse_and_translate(
    LayoutParser const & parser, UIType type, Lexer & lexer, ErrorList & errors, std::ostream & output)
{
    switch (type) {
        case UIType::integer: {
            auto value = lex_int(lexer);
            write_varint(output, gsl::narrow<uint32_t>(value));
            lexer.accept(LexerTokenType::semiColon);
            return;
        }

        case UIType::number: {
            auto tok = lexer.lex();
            if (not tok)
                throw std::runtime_error("unexpected end of file!");
            float value;
            if (tok->type == LexerTokenType::integer) {
                value = strtol(tok->text.c_str(), nullptr, 10);
            } else if (tok->type == LexerTokenType::number) {
                value = strtof(tok->text.c_str(), nullptr);
            } else {
                throw std::runtime_error("unexpected token. expected number or integer!");
            }
            write_number(output, value);
            lexer.accept(LexerTokenType::semiColon);
            return;
        }

        case UIType::enumeration: {
            auto text = lexer.accept(LexerTokenType::identifier);

            if (auto it = enumerations.find(text); it != enumerations.end())
                write_enum(output, it->second);
            else
                throw std::runtime_error("unknown enumeration value: " + text);

            lexer.accept(LexerTokenType::semiColon);
            return;
        }

        case UIType::string: {
            write_string(output, lexer.accept(LexerTokenType::string));
            lexer.accept(LexerTokenType::semiColon);
            return;
        }

        case UIType::boolean: {
            auto text = lexer.accept(LexerTokenType::identifier);
            char value;
            if (text == "true" or text == "yes")
                value = 1;
            else if (text == "false" or text == "no")
                value = 0;
            else
                throw std::runtime_error("invalid boolean value: " + text);

            output.write(&value, 1);

            lexer.accept(LexerTokenType::semiColon);
            return;
        }

        // same serialization and notation style
        case UIType::size:
        case UIType::point: {
            UISize size;
            size.w = lex_int(lexer);
            lexer.accept(LexerTokenType::comma);
            size.h = lex_int(lexer);
            lexer.accept(LexerTokenType::semiColon);

            write_varint(output, gsl::narrow<uint32_t>(size.w));
            write_varint(output, gsl::narrow<uint32_t>(size.h));
            return;
        }

        case UIType::margins: {
            std::vector<int> items;
            items.push_back(lex_int(lexer));
            while (items.size() < 4) {
                auto next = lexer.lex();
                if (not next)
                    throw std::runtime_error("unexpected end of file!");
                if (next->type == LexerTokenType::semiColon)
                    break;
                else if (next->type != LexerTokenType::comma)
                    throw std::runtime_error("expected comma, got '" + next->text + "' instead!");
                items.push_back(lex_int(lexer));
            }
            if (items.size() == 4)
                lexer.accept(LexerTokenType::semiColon);
            switch (items.size()) {
                case 1:
                    items.push_back(items[0]);
                    items.push_back(items[0]);
                    items.push_back(items[0]);
                    break;

                case 2:
                    items.push_back(items[0]);
                    items.push_back(items[1]);
                    break;

                case 4:
                    break;

                default:
                    throw std::runtime_error("invalid count for margins. only 1, 2 or 4 values are allowed");
            }

            assert(items.size() == 4);

            for (size_t i = 0; i < 4; i++)
                write_varint(output, gsl::narrow<uint32_t>(items[i]));

            return;
        }

        case UIType::sizelist: {
            auto lex_item = [&]() -> UISizeDef {
                auto tok = lexer.lex();
                if (not tok)
                    throw std::runtime_error("unexpected end of file!");
                if (tok->type == LexerTokenType::identifier) {
                    if (tok->text == "auto")
                        return UISizeAutoTag{};
                    else if (tok->text == "expand")
                        return UISizeExpandTag{};
                    else
                        throw std::runtime_error("unexpected identifier. must be auto or expand!");
                } else if (tok->type == LexerTokenType::integer) {
                    return int(strtol(tok->text.c_str(), nullptr, 10));
                } else if (tok->type == LexerTokenType::percentage) {
                    return 0.01f * strtof(tok->text.c_str(), nullptr);
                } else {
                    throw std::runtime_error("unexpected token '" + tok->text +
                                             "'. expected on of 'auto', 'expand', integer or percentage!");
                }
            };

            UISizeList list;
            list.push_back(lex_item());
            while (true) {
                auto next = lexer.lex();
                if (not next)
                    throw std::runtime_error("unexpected end of file!");
                if (next->type == LexerTokenType::semiColon)
                    break;
                else if (next->type != LexerTokenType::comma)
                    throw std::runtime_error("expected comma, got '" + next->text + "' instead!");
                list.push_back(lex_item());
            }

            // size of the list
            write_varint(output, gsl::narrow<uint32_t>(list.size()));

            // bitmask containing two bits per entry:
            // 00 = auto
            // 01 = expand
            // 10 = integer / pixels
            // 11 = number / percentage
            for (size_t i = 0; i < list.size(); i += 4) {
                uint8_t value = 0;
                for (size_t j = 0; j < std::min(4UL, list.size() - i); j++)
                    value |= (list[i + j].index() & 0x3) << (2 * j);
                output.write(reinterpret_cast<char const *>(&value), 1);
            }

            for (size_t i = 0; i < list.size(); i++) {
                switch (list[i].index()) {
                    case 2: // pixels
                        write_varint(output, gsl::narrow<uint32_t>(std::get<int>(list[i])));
                        break;
                    case 3: // percentage
                        write_number(output, std::get<float>(list[i]));
                        break;
                }
            }

            return;
        }

        case UIType::resource: {
            auto const tokResource = lexer.accept(LexerTokenType::identifier);
            if (tokResource != "resource")
                throw std::runtime_error("expected 'resource', found " + tokResource + " instead!");

            lexer.accept(LexerTokenType::openParens);

            auto const callbackName = lexer.acceptStringOrNumber();

            lexer.accept(LexerTokenType::closeParens);

            lexer.accept(LexerTokenType::semiColon);

            if (callbackName.index() == 0) {
                auto const & name = std::get<0>(callbackName);
                if (auto it = parser.knownResources.find(name); it == parser.knownResources.end())
                    throw std::runtime_error("unknown resource: '" + name + "'!");
                else
                    write_varint(output, gsl::narrow<uint32_t>(it->second));
            } else {
                write_varint(output, std::get<1>(callbackName));
            }

            return;
        }

        case UIType::event: {
            auto const tokResource = lexer.accept(LexerTokenType::identifier);
            if (tokResource != "callback")
                throw std::runtime_error("expected 'callback', found " + tokResource + " instead!");

            lexer.accept(LexerTokenType::openParens);

            auto const callbackName = lexer.acceptStringOrNumber();

            lexer.accept(LexerTokenType::closeParens);

            lexer.accept(LexerTokenType::semiColon);

            if (callbackName.index() == 0) {
                auto const & name = std::get<0>(callbackName);
                if (auto it = parser.knownCallbacks.find(name); it == parser.knownCallbacks.end())
                    throw std::runtime_error("unknown callback: '" + name + "'!");
                else
                    write_varint(output, gsl::narrow<uint32_t>(it->second));
            } else {
                write_varint(output, std::get<1>(callbackName));
            }

            return;
        }
    }
    assert(false and "not supported type!");
}

static void parse_and_translate(LayoutParser const & parser,
                                std::string const & widgetName,
                                Lexer & lexer,
                                ErrorList & errors,
                                std::ostream & output)
{
    lexer.accept(LexerTokenType::openBrace);

    UIWidget widgetType = UIWidget::invalid;
    if (auto it = widgetTypes.find(widgetName); it != widgetTypes.end())
        widgetType = it->second;
    else
        errors.push_back(ParseError{0, 0, "Widget type '" + widgetName + "' not found"});

    write_enum(output, widgetType);

    bool isReadingChildren = false;

    while (true) {
        auto tok = lexer.lex();
        if (not tok)
            throw std::runtime_error("unexpected end of file!");
        if (tok->type == LexerTokenType::closeBrace) {
            break;
        } else if (tok->type == LexerTokenType::identifier) {
            if (auto it1 = properties.find(tok->text); it1 != properties.end()) {
                if (isReadingChildren)
                    throw std::runtime_error("property definitions are only allowed before child widgets!!");
                lexer.accept(LexerTokenType::colon);

                uint8_t propId = uint8_t(it1->second);
                assert((propId & ~0x7F) == 0);

                auto const propertyType = getPropertyType(it1->second);

                if (auto bindTok = lexer.peek();
                    bindTok and (bindTok->type == LexerTokenType::identifier) and (bindTok->text == "bind")) {
                    // this is a binding
                    propId |= 0x80; // set "is property bit"

                    output.write(reinterpret_cast<char const *>(&propId), 1);

                    lexer.accept(LexerTokenType::identifier);
                    lexer.accept(LexerTokenType::openParens);

                    auto const propertyName = lexer.acceptStringOrNumber();

                    lexer.accept(LexerTokenType::closeParens);
                    lexer.accept(LexerTokenType::semiColon);

                    uint32_t propertyKey;
                    if (propertyName.index() == 0) {

                        auto const name = std::get<0>(propertyName);
                        auto it3 = parser.knownProperties.find(name);
                        if (it3 == parser.knownProperties.end())
                            throw std::runtime_error("unknown property: " + name);

                        propertyKey = gsl::narrow<uint32_t>(it3->second);
                    } else {
                        propertyKey = std::get<1>(propertyName);
                    }

                    write_varint(output, propertyKey);
                } else {
                    write_enum(output, it1->second);

                    parse_and_translate(parser, propertyType, lexer, errors, output);
                }
            } else if (auto it2 = widgetTypes.find(tok->text); it2 != widgetTypes.end()) {
                if (not isReadingChildren)
                    write_enum(output, UIProperty::invalid); // end of properties
                isReadingChildren = true;
                parse_and_translate(parser, tok->text, lexer, errors, output);
            } else {
                throw std::runtime_error("unexpected identifier: " + tok->text);
            }
        } else {
            throw std::runtime_error("unexpected token: '" + tok->text + "'");
        }
    }

    if (not isReadingChildren)
        write_enum(output, UIProperty::invalid); // end of properties
    write_enum(output, UIWidget::invalid);       // end of children
}

static void parse_and_translate(LayoutParser const & parser, Lexer & lexer, ErrorList & errors, std::ostream & output)
{
    auto const widgetName = lexer.accept(LexerTokenType::identifier);
    parse_and_translate(parser, widgetName, lexer, errors, output);
}

bool LayoutParser::compile(std::istream & input, std::ostream & output) const
{
    ErrorList errors;
    Lexer lexer{input};

    try {
        parse_and_translate(*this, lexer, errors, output);
    } catch (std::runtime_error const & ex) {
        errors.push_back(ParseError{0, 0, ex.what()});
    }

    for (auto const & err : errors) {
        std::cerr << err.line << ":" << err.column << ": " << err.message << std::endl;
    }

    return errors.empty();
}
