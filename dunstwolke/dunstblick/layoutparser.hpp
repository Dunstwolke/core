#ifndef LAYOUTPARSER_HPP
#define LAYOUTPARSER_HPP

#include <memory>
#include <optional>
#include <sstream>
#include <xstd/resource>

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
    static std::optional<Token> Lex(FlexLexer*);

    LayoutParser();

    void compile(std::istream & input, std::ostream & output);
};

#endif // LAYOUTPARSER_HPP
