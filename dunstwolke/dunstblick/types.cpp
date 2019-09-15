#include "types.hpp"
#include <stdexcept>
#include <xstd/format>
#include <gsl/gsl>

UIMargin::UIMargin(int all)
    : top(all), left(all), bottom(all), right(all)
{
}

UIMargin::UIMargin(int horizontal, int vertical)
    : top(vertical), left(horizontal), bottom(vertical), right(horizontal)
{
}

UIMargin::UIMargin(int _top, int _left, int _right, int _bottom)
    : top(_top), left(_left), bottom(_bottom), right(_right)
{

}

static std::string convertToString(UIValue const & value, ConversionOptions const & opts)
{
	switch(UIType(value.index()))
	{
		case UIType::boolean:
			switch(opts.booleanFormat)
			{
				case BooleanFormat::truefalse: return std::get<bool>(value) ? "true" : "false";
				case BooleanFormat::yesno:     return std::get<bool>(value) ? "yes"  : "no";
				case BooleanFormat::onoff:     return std::get<bool>(value) ? "on"   : "off";
			}
		case UIType::integer:
			return std::to_string(std::get<int>(value));

		case UIType::number:
			return std::to_string(std::get<float>(value));

		default:
			throw std::runtime_error(xstd::format("cannot convert %0 to string!").arg(to_string(UIType(value.index()))));
	}
}

static int convertToInteger(UIValue const & value, ConversionOptions const & opts)
{
	switch(UIType(value.index()))
	{
		case UIType::boolean:
			return std::get<bool>(value) ? 1 : 0;

		case UIType::number:
			return int(std::get<float>(value) + 0.5f);

		case UIType::string:
			return gsl::narrow<int>(strtol(std::get<std::string>(value).c_str(), nullptr, 10));

		default:
			throw std::runtime_error(xstd::format("cannot convert %0 to string!").arg(to_string(UIType(value.index()))));
	}
}

static float convertToNumber(UIValue const & value, ConversionOptions const & opts)
{
	switch(UIType(value.index()))
	{
		case UIType::boolean:
			return std::get<bool>(value) ? 1.0f : 0.0f;

		case UIType::integer:
			return float(std::get<int>(value));

		case UIType::string:
			return strtof(std::get<std::string>(value).c_str(), nullptr);

		default:
			throw std::runtime_error(xstd::format("cannot convert %0 to string!").arg(to_string(UIType(value.index()))));
	}
}

UIValue convertTo(UIValue const & value, UIType type, ConversionOptions const & opts)
{
	if(UIType(value.index()) == type)
		return value;

	switch(type)
	{
		case UIType::string:
			return convertToString(value, opts);

		case UIType::integer:
			return convertToInteger(value, opts);

		case UIType::number:
			return convertToNumber(value, opts);

		default:
			throw std::runtime_error("unsupported conversion target!");
	}
}

ObjectProperty & Object::add(PropertyName name, UIType type)
{
	auto [ it, emplaced ] = properties.emplace(name, ObjectProperty { type, UIValue { } });
	if(not emplaced)
		throw std::runtime_error("object already has this property!");
	return it->second;
}

xstd::optional<ObjectProperty &> Object::get(PropertyName property)
{
	if(auto it = properties.find(property); it != properties.end())
		return it->second;
	else
		return xstd::nullopt;
}

xstd::optional<const ObjectProperty &> Object::get(PropertyName property) const
{
	if(auto it = properties.find(property); it != properties.end())
		return it->second;
	else
		return xstd::nullopt;
}
