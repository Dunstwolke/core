#include "layoutparser.hpp"
#include "FlexLexer.h"

#include <map>
#include <cassert>
#include <string>
#include <gsl/gsl>
#include <stdexcept>
#include "enums.hpp"
#include "types.hpp"

#define INCLUDE_PARSER_FIELDS
#include "parser-info.hpp"
#undef INCLUDE_PARSER_FIELDS

LayoutParser::LayoutParser()
{

}

static std::string toString(LexerTokenType type)
{
    switch(type)
    {
    case LexerTokenType::identifier: return "identifier";
    case LexerTokenType::integer: return "integer";
    case LexerTokenType::number: return "number";
    case LexerTokenType::openBrace: return "opening brace";
    case LexerTokenType::closeBrace: return "closing brace";
    case LexerTokenType::colon: return "colon";
    case LexerTokenType::semiColon: return "semicolon";
    case LexerTokenType::comma: return "comma";
    case LexerTokenType::string: return "string";
    case LexerTokenType::percentage: return "percentage";
    }
    return "???";
}

static std::string Accept(FlexLexer * lexer, LexerTokenType type)
{
    auto tok = LayoutParser::Lex(lexer);
    if(not tok or tok->type != type) {
        if(not tok)
            throw std::runtime_error("unexpected end of file!");
        throw std::runtime_error("expected " + toString(type) + ", found: '" + tok->text + "'!");
    }
    return tok->text;
}

static void write_varint(std::ostream &output, uint32_t value)
{
    char buf[5];

    size_t maxidx = 4;
    for(size_t n = 0; n < 5; n++)
    {
        char & c = buf[4 - n];
        c = (value >> (7 * n)) & 0x7F;
        if(c != 0)
            maxidx = 4 - n;
        if(n > 0)
            c |= 0x80;
    }

    assert(maxidx < 5);
    output.write(buf + maxidx, std::streamsize(5 - maxidx));
}

template<typename T>
static void write_enum(std::ostream &output, T const & value)
{
    static_assert (std::is_enum_v<T> or std::is_same_v<T, uint8_t>);
    static_assert (sizeof(T) == 1);
    output.write(reinterpret_cast<char const *>(&value), 1);
}

static void write_string(std::ostream & output, std::string const & text)
{
    write_varint(output, text.size());
    output.write(text.c_str(), text.size());
}

static void write_number(std::ostream & output, float value)
{
    output.write(reinterpret_cast<char const *>(&value), sizeof(value));
}

static int lex_int(FlexLexer * lexer)
{
    auto text = Accept(lexer, LexerTokenType::integer);
    return strtol(text.c_str(), nullptr, 10);
}

static float lex_number(FlexLexer * lexer)
{
    auto text = Accept(lexer, LexerTokenType::number);
    return strtof(text.c_str(), nullptr);
}

static void parse_and_translate(UIType type, FlexLexer * lexer, std::ostream &output)
{
    switch(type)
    {
        case UIType::integer: {
            auto value = lex_int(lexer);
            write_varint(output, value);
            Accept(lexer, LexerTokenType::semiColon);
            return;
        }

        case UIType::number: {
            auto tok = LayoutParser::Lex(lexer);
            if(not tok)
                throw std::runtime_error("unexpected end of file!");
            float value;
            if(tok->type == LexerTokenType::integer) {
                value = strtol(tok->text.c_str(), nullptr, 10);
            }
            else if(tok->type == LexerTokenType::number) {
                value = strtof(tok->text.c_str(), nullptr);
            }
            else {
                throw std::runtime_error("unexpected token. expected number or integer!");
            }
            write_number(output, value);
            Accept(lexer, LexerTokenType::semiColon);
            return;
        }

        case UIType::enumeration: {
            auto text = Accept(lexer, LexerTokenType::identifier);

            if(auto it = enumerations.find(text); it != enumerations.end())
                write_enum(output, it->second);
            else
                throw std::runtime_error("unknown enumeration value: " + text);

            Accept(lexer, LexerTokenType::semiColon);
            return;
        }

        case UIType::string: {
            write_string(output, Accept(lexer, LexerTokenType::string));
            Accept(lexer, LexerTokenType::semiColon);
            return;
        }

        case UIType::boolean: {
            auto text = Accept(lexer, LexerTokenType::identifier);
            char value;
            if(text == "true" or text == "yes")
                value = 1;
            else if(text == "false" or text == "no")
                value = 0;
            else
                throw std::runtime_error("invalid boolean value: " + text);

            output.write(&value, 1);

            Accept(lexer, LexerTokenType::semiColon);
            return;
        }

        case UIType::margins: {
            std::vector<int> items;
            items.push_back(lex_int(lexer));
            while(items.size() < 4)
            {
                auto next = LayoutParser::Lex(lexer);
                if(not next)
                    throw std::runtime_error("unexpected end of file!");
                if(next->type == LexerTokenType::semiColon)
                    break;
                else if(next->type != LexerTokenType::comma)
                    throw std::runtime_error("expected comma, got '" + next->text + "' instead!");
                items.push_back(lex_int(lexer));
            }
            if(items.size() == 4)
                Accept(lexer, LexerTokenType::semiColon);
            switch(items.size())
            {
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

            for(size_t i = 0; i < 4; i++)
                write_varint(output, items[i]);

            return;
        }

        case UIType::sizelist: {
            auto lex_item = [&]() -> UISizeDef {
                auto tok = LayoutParser::Lex(lexer);
                if(not tok)
                    throw std::runtime_error("unexpected end of file!");
                if(tok->type == LexerTokenType::identifier) {
                    if(tok->text == "auto")
                        return UISizeAutoTag { };
                    else if(tok->text == "expand")
                        return UISizeExpandTag { };
                    else
                        throw std::runtime_error("unexpected identifier. must be auto or expand!");
                }
                else if(tok->type == LexerTokenType::integer) {
                    return int(strtol(tok->text.c_str(), nullptr, 10));
                }
                else if(tok->type == LexerTokenType::percentage) {
                    return 0.01f * strtof(tok->text.c_str(), nullptr);
                }
                else {
                    throw std::runtime_error("unexpected token '" + tok->text + "'. expected on of 'auto', 'expand', integer or percentage!");
                }
            };

            UISizeList list;
            list.push_back(lex_item());
            while(true)
            {
                auto next = LayoutParser::Lex(lexer);
                if(not next)
                    throw std::runtime_error("unexpected end of file!");
                if(next->type == LexerTokenType::semiColon)
                    break;
                else if(next->type != LexerTokenType::comma)
                    throw std::runtime_error("expected comma, got '" + next->text + "' instead!");
                list.push_back(lex_item());
            }

            // size of the list
            write_varint(output, list.size());

            // bitmask containing two bits per entry:
            // 00 = auto
            // 01 = expand
            // 10 = integer / pixels
            // 11 = number / percentage
            for(size_t i = 0; i < list.size(); i += 4)
            {
                uint8_t value = 0;
                for(size_t j = 0; j < std::min(4UL, list.size() - i); j++)
                    value |= (list[i + j].index() & 0x3) << (2 * j);
                output.write(reinterpret_cast<char const *>(&value), 1);
            }

            for(size_t i = 0; i < list.size(); i++)
            {
                switch(list[i].index())
                {
                case 2: // pixels
                    write_varint(output, std::get<int>(list[i]));
                    break;
                case 3: // percentage
                    write_number(output, std::get<float>(list[i]));
                    break;
                }
            }

            return;
        }


    }
    assert(false and "not supported type!");
}

static void parse_and_translate(std::string const & widgetName, FlexLexer * lexer, std::ostream &output)
{
    Accept(lexer, LexerTokenType::openBrace);

    auto const widgetType = widgetTypes.at(widgetName);
    write_enum(output, widgetType);

    bool isReadingChildren = false;

    while(true)
    {
        auto tok = LayoutParser::Lex(lexer);
        if(not tok)
            throw std::runtime_error("unexpected end of file!");
        if(tok->type == LexerTokenType::closeBrace)
        {
            break;
        }
        else if(tok->type == LexerTokenType::identifier)
        {
            if(auto it = properties.find(tok->text); it != properties.end())
            {
                if(isReadingChildren)
                    throw std::runtime_error("property definitions are only allowed before child widgets!!");
                Accept(lexer, LexerTokenType::colon);

                write_enum(output, it->second);

                auto propertyType = getPropertyType(it->second);

                parse_and_translate(propertyType, lexer, output);
            }
            else if(auto it = widgetTypes.find(tok->text); it != widgetTypes.end())
            {
                if(not isReadingChildren)
                    write_enum(output, UIProperty::invalid); // end of properties
                isReadingChildren = true;
                parse_and_translate(tok->text, lexer, output);
            }
            else
            {
                throw std::runtime_error("unexpected identifier: " + tok->text);
            }
        }
        else
        {
            throw std::runtime_error("unexpected token: '" + tok->text + "'");
        }
    }

    if(not isReadingChildren)
        write_enum(output, UIProperty::invalid); // end of properties
    write_enum(output, UIWidget::invalid); // end of children
}

static void parse_and_translate(FlexLexer * lexer, std::ostream &output)
{
    auto const widgetName = Accept(lexer, LexerTokenType::identifier);
    parse_and_translate(widgetName, lexer, output);
}

void LayoutParser::compile(std::istream &input, std::ostream &output)
{
    xstd::resource<FlexLexer*, FreeLexer> lexer(AllocLexer(&input));

    parse_and_translate(lexer.get(), output);
}
