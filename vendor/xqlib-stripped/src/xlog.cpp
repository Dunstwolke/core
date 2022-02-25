#include "../include/xlog"

#include <iostream>
#include <mutex>
#include <xcept>

namespace
{
	bool colored_output = false;
#ifdef DEBUG
	xlog::log_level min_level = xlog::verbose;
#else
	xlog::log_level min_level = xlog::message;
#endif
	std::mutex output_lock;
#ifdef DEBUG
	bool die_on_critical = true;
#else
	bool die_on_critical = false;
#endif
}

void xlog::enable_colors(bool enabled)
{
	colored_output = enabled;
}

void xlog::abort_on_critical(bool enabled)
{
	die_on_critical = enabled;
}

void xlog::set_verbosity(log_level min)
{
	min_level = min;
}

xlog::log::log(xlog::log_level lvl) :
  level(lvl),
  text()
{

}

xlog::log::log(char const * prefix, xlog::log_level lvl) :
  level(lvl),
  text()
{
	text << prefix << ": ";
}

xlog::log::~log()
{
	if(level >= min_level)
	{
		std::lock_guard _ { output_lock };

		auto & stream =  (level >= warning) ? std::cerr : std::cout;

		if(colored_output)
		{
			stream << "\x1b[";
			if(level >= critical)
				stream << "35"; // magenta
			else if(level >= error)
				stream << "31"; // red
			else if(level >= warning)
				stream << "33"; // yellow
			else if(level < message)
				stream << "32"; // green
			else if(level < message)
				stream << "39"; // "reset/default"
			stream << "m";
		}

		stream << text.str() << std::endl;
		stream.flush();

		if(colored_output)
		{
			stream << "\x1b[39m";
		}
	}
	if((level >= critical) and die_on_critical)
		abort();
}
