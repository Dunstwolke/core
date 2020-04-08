#ifndef LAYOUTPARSER_HPP
#define LAYOUTPARSER_HPP

#include "dunstblick.h"
#include "lexer.h"

#include <map>
#include <memory>
#include <optional>
#include <sstream>

struct LayoutParser
{
    std::map<std::string, dunstblick_PropertyName> knownProperties;
    std::map<std::string, dunstblick_ResourceID> knownResources;
    std::map<std::string, dunstblick_EventID> knownCallbacks;

    LayoutParser();

    bool compile(std::istream & input, std::ostream & output) const;
};

#endif // LAYOUTPARSER_HPP
