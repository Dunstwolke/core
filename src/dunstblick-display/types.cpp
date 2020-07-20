#include "types.hpp"
#include "object.hpp"
#include <stdexcept>
#include <xstd/format>

UIMargin::UIMargin(int all)
{
    this->top = all;
    this->left = all;
    this->bottom = all;
    this->right = all;
}

UIMargin::UIMargin(int horizontal, int vertical)
{
    this->top = vertical;
    this->left = horizontal;
    this->bottom = vertical;
    this->right = horizontal;
}

UIMargin::UIMargin(int _top, int _left, int _right, int _bottom)
{
    this->top = _top;
    this->left = _left;
    this->bottom = _bottom;
    this->right = _right;
}

static std::string convertToString(UIValue const & value, ConversionOptions const & opts)
{
    switch (UIType(value.index())) {
        case UIType::boolean:
            switch (opts.booleanFormat) {
                case BooleanFormat::truefalse:
                    return std::get<bool>(value) ? "true" : "false";
                case BooleanFormat::yesno:
                    return std::get<bool>(value) ? "yes" : "no";
                case BooleanFormat::onoff:
                    return std::get<bool>(value) ? "on" : "off";
            }
        case UIType::integer:
            return std::to_string(std::get<int>(value));

        case UIType::number:
            return std::to_string(std::get<float>(value));

        default:
            throw std::runtime_error(
                xstd::format("cannot convert %0 to string!").arg(to_string(UIType(value.index()))));
    }
}

static int convertToInteger(UIValue const & value, ConversionOptions const & opts)
{
    switch (UIType(value.index())) {
        case UIType::boolean:
            return std::get<bool>(value) ? 1 : 0;

        case UIType::number:
            return int(std::get<float>(value) + 0.5f);

        case UIType::string:
            return static_cast<int>(strtol(std::get<std::string>(value).c_str(), nullptr, 10));

        default:
            throw std::runtime_error(
                xstd::format("cannot convert %0 to string!").arg(to_string(UIType(value.index()))));
    }
}

static float convertToNumber(UIValue const & value, ConversionOptions const & opts)
{
    switch (UIType(value.index())) {
        case UIType::boolean:
            return std::get<bool>(value) ? 1.0f : 0.0f;

        case UIType::integer:
            return float(std::get<int>(value));

        case UIType::string:
            return strtof(std::get<std::string>(value).c_str(), nullptr);

        default:
            throw std::runtime_error(
                xstd::format("cannot convert %0 to string!").arg(to_string(UIType(value.index()))));
    }
}

UIValue convertTo(UIValue const & value, UIType type, ConversionOptions const & opts)
{
    if (UIType(value.index()) == type)
        return value;

    switch (type) {
        case UIType::string:
            return convertToString(value, opts);

        case UIType::integer:
            return convertToInteger(value, opts);

        case UIType::number:
            return convertToNumber(value, opts);

        default:
            throw std::runtime_error("cannot convert from " + to_string(UIType(value.index())) + " to " +
                                     to_string(type) + "!");
    }
}

ObjectRef::ObjectRef(std::nullptr_t) : id() {}

ObjectRef::ObjectRef(ObjectID _id) : id(_id) {}

ObjectRef::ObjectRef(const Object & obj) : id(obj.get_id()) {}
