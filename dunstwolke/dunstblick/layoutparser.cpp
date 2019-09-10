#include "layoutparser.hpp"
#include "FlexLexer.h"

#include <map>
#include <cassert>
#include <string>
#include <gsl/gsl>
#include <stdexcept>
#include "enums.hpp"
#include "types.hpp"

const std::map<std::string, UIWidget> widgetTypes =
{
    { "Button", UIWidget::button },
    { "Label", UIWidget::label },
    { "ComboBox", UIWidget::combobox },
    { "TreeViewItem", UIWidget::treeviewitem },
    { "TreeView", UIWidget::treeview },
    { "ListBoxItem", UIWidget::listboxitem },
    { "ListBox", UIWidget::listbox },
    { "Drawing", UIWidget::drawing },
    { "Picture", UIWidget::picture },
    { "TextBox", UIWidget::textbox },
    { "CheckBox", UIWidget::checkbox },
    { "RadioButton", UIWidget::radiobutton },
    { "ScrollView", UIWidget::scrollview },
    { "ScrollBar", UIWidget::scrollbar },
    { "Slider", UIWidget::slider },
    { "ProgressBar", UIWidget::progressbar },
    { "SpinEdit", UIWidget::spinedit },
    { "Separator", UIWidget::separator },
    { "Spacer", UIWidget::spacer },

    // widgets go here ↑
    // layouts go here ↓

    { "CanvasLayout", UIWidget::canvas_layout },
    { "FlowLayout",   UIWidget::flow_layout },
    { "GridLayout",   UIWidget::grid_layout },
    { "DockLayout",   UIWidget::dock_layout },
    { "StackLayout",  UIWidget::stack_layout },
};

const std::map<std::string, UIProperty> properties =
{
    { "horizontal-alignment", UIProperty::horizontalAlignment },
    { "vertical-alignment", UIProperty::verticalAlignment },
    { "margins", UIProperty::margins },
    { "paddings", UIProperty::paddings },
    { "stack-direction", UIProperty::stackDirection },
    { "dock-sites", UIProperty::dockSites },
    { "visibility", UIProperty::visibility },
    { "size-hint", UIProperty::sizeHint },
    { "font-family", UIProperty::fontFamily },
    { "text", UIProperty::text },
};

const std::map<std::string, uint8_t> enumerations =
{
#define ENUM(_X) { #_X, UIEnum::_X }
    ENUM(none),
    ENUM(left),
    ENUM(center),
    ENUM(right),
    ENUM(top),
    ENUM(middle),
    ENUM(bottom),
    ENUM(stretch),
    ENUM(expand),
    { "auto", UIEnum::_auto },
    ENUM(yesno),
    ENUM(truefalse),
    ENUM(onoff),
    ENUM(visible),
    ENUM(hidden),
    ENUM(collapsed),
    ENUM(vertical),
    ENUM(horizontal),
    ENUM(sans),
    ENUM(serif),
    ENUM(monospace),
#undef ENUM
};

LayoutParser::LayoutParser()
{

}

static std::string Accept(FlexLexer * lexer, LexerTokenType type)
{
    auto tok = LayoutParser::Lex(lexer);
    if(not tok or tok->type != type)
        throw std::runtime_error("unexpected token!");
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

static int lex_int(FlexLexer * lexer)
{
    auto text = Accept(lexer, LexerTokenType::integer);
    return strtol(text.c_str(), nullptr, 10);
}

static void parse_and_translate(UIType type, FlexLexer * lexer, std::ostream &output)
{
    switch(type)
    {
        case UIType::integer: {
            auto text = Accept(lexer, LexerTokenType::integer);
            write_varint(output, strtoul(text.c_str(), nullptr, 10));

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
            throw std::runtime_error("unexpected token!");
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
            throw std::runtime_error("unexpected token!");
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
