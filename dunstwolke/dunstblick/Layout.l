/* don't support include files*/
%option noyywrap

/* use c++ scanner for reentrance */
%option c++

%{
#include "layoutparser.hpp"

using LTT = LexerTokenType;
#define MAX_STR_CONST 1024

struct CustomBuffer
{
  std::string stringContent;
};

static CustomBuffer & BufferFromPtr(FlexLexer *);

%}

%%

%{
  int something;
%}

"/*"                    { // parse a comment
                          int c;
                          while((c = yyinput()) != 0)
                          {
                            if(c == '*')
                            {
                              if((c = yyinput()) == '/')
                                  break;
                              else
                                  unput(c);
                            }
                          }
                        }


["']                    {
                          int eos = yytext[0];
                          int c;
                          std::string result;
                          while((c = yyinput()) != 0)
                          {
                            if(c == '\\') {
                              c = yyinput();
                              if(c == 0)
                                return int(LTT::eof);
                              switch(c) {
                                case 't': c = '\t'; break;
                                case 'r': c = '\r'; break;
                                case 'n': c = '\n'; break;
                              }
                            }
                            else if(c == eos)
                              break;
                            result.append(1, c);
                          }
                          BufferFromPtr(this).stringContent = result;
                          return int((c == 0) ? LTT::eof : LTT::string);
                        }

[ \t\n]                 { /* skip whitespace */ }

[A-Za-z]+(\-[A-Za-z]+)* { return int(LTT::identifier); }

[0-9]+[ ]*\%            { return int(LTT::percentage); }

[0-9]+\.[0-9]*          { return int(LTT::number); }

[0-9]+                  { return int(LTT::integer); }

\{                      { return int(LTT::openBrace); }
\}                      { return int(LTT::closeBrace); }
\(                      { return int(LTT::openParens); }
\)                      { return int(LTT::closeParens); }
\:                      { return int(LTT::colon); }
\;                      { return int(LTT::semiColon); }
\,                      { return int(LTT::comma); }

.                       { return int(LTT::invalid); }

%%

FlexLexer * LayoutParser::AllocLexer(std::istream * input)
{
  auto * bytes = new char[sizeof(LayoutFlexLexer) + sizeof(CustomBuffer)];



  auto * lexer = new (&bytes[0]) LayoutFlexLexer;
  lexer->switch_streams(input, nullptr);

  auto * cb = new (&bytes[sizeof(LayoutFlexLexer)]) CustomBuffer;

  return lexer;
}

void LayoutParser::FreeLexer(FlexLexer * lexer)
{
  auto * bytes = reinterpret_cast<char*>(lexer);

  reinterpret_cast<LayoutFlexLexer*>(&bytes[0])->~LayoutFlexLexer();

  reinterpret_cast<CustomBuffer*>(&bytes[sizeof(LayoutFlexLexer)])->~CustomBuffer();

  delete[] bytes;
}

static CustomBuffer & BufferFromPtr(FlexLexer * lexer)
{
  auto * bytes = reinterpret_cast<char*>(lexer);

  return *reinterpret_cast<CustomBuffer*>(&bytes[sizeof(LayoutFlexLexer)]);
}

std::optional<Token> LayoutParser::Lex(FlexLexer * lexer)
{
  auto const type = LexerTokenType(lexer->yylex());
  if(type == LexerTokenType::eof)
    return std::nullopt;

  std::string textValue(lexer->YYText());
  if(type == LexerTokenType::string)
    textValue = BufferFromPtr(lexer).stringContent;

  // printf("got token: %u, [[%s]]\n", type, textValue.c_str());
  // fflush(stdout);

  return Token {
    type,
    std::move(textValue),
  };
}

