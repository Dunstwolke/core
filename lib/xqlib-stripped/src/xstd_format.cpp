#include "../include/xstd/format"

#include <regex>

namespace /* private */
{
	std::regex format_pattern("%(\\d+)");

	std::string replace_pattern(std::string const & input, std::string const & repl)
	{
		std::string result;

		std::sregex_iterator start(input.begin(), input.end(), format_pattern);
		std::sregex_iterator const end;

		if(auto it = start; it != end)
		{
			auto last = it;
			for(; it != end; ++it)
			{
				result += it->prefix();
				auto pos = std::strtoul((*it)[1].str().c_str(), nullptr, 10);
				if(pos == 0)
					result += repl;
				else
					result += "%" + std::to_string(pos - 1);
				last = it;
			}
			result += last->suffix();
			return result;
		}
		else
		{
			return input;
		}
	}
}

xstd::format & xstd::format::arg(std::string const & value)
{
	contents = replace_pattern(contents, value);
	return *this;
}


xstd::format xstd::format::arg(std::string const & value) const
{
	return format(replace_pattern(contents, value));
}
