
#pragma once

enum LexerTokenType
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

struct FlexLexer
{
    unsigned long offset;
    char const * source;
    unsigned long size;
};

struct FlexLexer_Token
{
    enum LexerTokenType type;
    char * string;
    unsigned long length;
};

void FlexLexer_init(struct FlexLexer * lexer, char const * source, unsigned long size);

int FlexLexer_lex(struct FlexLexer * lexer, struct FlexLexer_Token * token);
