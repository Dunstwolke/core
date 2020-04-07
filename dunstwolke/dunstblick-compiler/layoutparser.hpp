#ifndef LAYOUTPARSER_HPP
#define LAYOUTPARSER_HPP

#include "dunstblick.h"

#include <map>
#include <memory>
#include <optional>
#include <sstream>

class FlexLexer;

enum class LexerTokenType : int
{
    invalid = -1,
    eof = 0,
    identifier = 1,
    integer = 2,
    number = 3,
    openBrace = 4,
    closeBrace = 5,
    colon = 6,
    semiColon = 7,
    comma = 8,
    string = 9,
    percentage = 10,
    openParens = 11,
    closeParens = 12,
};

struct Token
{
    LexerTokenType type;
    std::string text;
};

struct LayoutParser
{
    static FlexLexer * AllocLexer(std::istream * input);
    static void FreeLexer(FlexLexer *);
    static std::optional<Token> Lex(FlexLexer *);

    std::map<std::string, dunstblick_PropertyName> knownProperties;
    std::map<std::string, dunstblick_ResourceID> knownResources;
    std::map<std::string, dunstblick_EventID> knownCallbacks;

    LayoutParser();

    bool compile(std::istream & input, std::ostream & output) const;
};

#endif // LAYOUTPARSER_HPP
