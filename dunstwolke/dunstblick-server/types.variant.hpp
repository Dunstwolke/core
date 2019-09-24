using UIValue = std::variant<
	std::monostate,
	int,
	float,
	std::string,
	uint8_t,
	UIMargin,
	UIColor,
	UISize,
	UIPoint,
	UIResourceID,
	bool,
	UISizeList,
	ObjectRef,
	ObjectList,
	CallbackID
>;

static_assert(std::is_same_v<std::variant_alternative_t<size_t(UIType::invalid),     UIValue>, std::monostate>);
static_assert(std::is_same_v<std::variant_alternative_t<size_t(UIType::integer),     UIValue>, int>);
static_assert(std::is_same_v<std::variant_alternative_t<size_t(UIType::number),     UIValue>, float>);
static_assert(std::is_same_v<std::variant_alternative_t<size_t(UIType::string),     UIValue>, std::string>);
static_assert(std::is_same_v<std::variant_alternative_t<size_t(UIType::enumeration),     UIValue>, uint8_t>);
static_assert(std::is_same_v<std::variant_alternative_t<size_t(UIType::margins),     UIValue>, UIMargin>);
static_assert(std::is_same_v<std::variant_alternative_t<size_t(UIType::color),     UIValue>, UIColor>);
static_assert(std::is_same_v<std::variant_alternative_t<size_t(UIType::size),     UIValue>, UISize>);
static_assert(std::is_same_v<std::variant_alternative_t<size_t(UIType::point),     UIValue>, UIPoint>);
static_assert(std::is_same_v<std::variant_alternative_t<size_t(UIType::resource),     UIValue>, UIResourceID>);
static_assert(std::is_same_v<std::variant_alternative_t<size_t(UIType::boolean),     UIValue>, bool>);
static_assert(std::is_same_v<std::variant_alternative_t<size_t(UIType::sizelist),     UIValue>, UISizeList>);
static_assert(std::is_same_v<std::variant_alternative_t<size_t(UIType::object),     UIValue>, ObjectRef>);
static_assert(std::is_same_v<std::variant_alternative_t<size_t(UIType::objectlist),     UIValue>, ObjectList>);
static_assert(std::is_same_v<std::variant_alternative_t<size_t(UIType::callback),     UIValue>, CallbackID>);


template<> constexpr UIType getUITypeFromType<std::monostate>() { return UIType::invalid; }
template<> constexpr UIType getUITypeFromType<int>() { return UIType::integer; }
template<> constexpr UIType getUITypeFromType<float>() { return UIType::number; }
template<> constexpr UIType getUITypeFromType<std::string>() { return UIType::string; }
template<> constexpr UIType getUITypeFromType<uint8_t>() { return UIType::enumeration; }
template<> constexpr UIType getUITypeFromType<UIMargin>() { return UIType::margins; }
template<> constexpr UIType getUITypeFromType<UIColor>() { return UIType::color; }
template<> constexpr UIType getUITypeFromType<UISize>() { return UIType::size; }
template<> constexpr UIType getUITypeFromType<UIPoint>() { return UIType::point; }
template<> constexpr UIType getUITypeFromType<UIResourceID>() { return UIType::resource; }
template<> constexpr UIType getUITypeFromType<bool>() { return UIType::boolean; }
template<> constexpr UIType getUITypeFromType<UISizeList>() { return UIType::sizelist; }
template<> constexpr UIType getUITypeFromType<ObjectRef>() { return UIType::object; }
template<> constexpr UIType getUITypeFromType<ObjectList>() { return UIType::objectlist; }
template<> constexpr UIType getUITypeFromType<CallbackID>() { return UIType::callback; }
template<> constexpr UIType getUITypeFromType<VAlignment>() { return UIType::enumeration; }
template<> constexpr UIType getUITypeFromType<BooleanFormat>() { return UIType::enumeration; }
template<> constexpr UIType getUITypeFromType<DisplayProgressStyle>() { return UIType::enumeration; }
template<> constexpr UIType getUITypeFromType<StackDirection>() { return UIType::enumeration; }
template<> constexpr UIType getUITypeFromType<Visibility>() { return UIType::enumeration; }
template<> constexpr UIType getUITypeFromType<UIFont>() { return UIType::enumeration; }
template<> constexpr UIType getUITypeFromType<ImageScaling>() { return UIType::enumeration; }
template<> constexpr UIType getUITypeFromType<Orientation>() { return UIType::enumeration; }
template<> constexpr UIType getUITypeFromType<DockSite>() { return UIType::enumeration; }
template<> constexpr UIType getUITypeFromType<HAlignment>() { return UIType::enumeration; }


static_assert(getUITypeFromType<std::monostate>() == UIType::invalid);
static_assert(getUITypeFromType<int>() == UIType::integer);
static_assert(getUITypeFromType<float>() == UIType::number);
static_assert(getUITypeFromType<std::string>() == UIType::string);
static_assert(getUITypeFromType<uint8_t>() == UIType::enumeration);
static_assert(getUITypeFromType<UIMargin>() == UIType::margins);
static_assert(getUITypeFromType<UIColor>() == UIType::color);
static_assert(getUITypeFromType<UISize>() == UIType::size);
static_assert(getUITypeFromType<UIPoint>() == UIType::point);
static_assert(getUITypeFromType<UIResourceID>() == UIType::resource);
static_assert(getUITypeFromType<bool>() == UIType::boolean);
static_assert(getUITypeFromType<UISizeList>() == UIType::sizelist);
static_assert(getUITypeFromType<ObjectRef>() == UIType::object);
static_assert(getUITypeFromType<ObjectList>() == UIType::objectlist);
static_assert(getUITypeFromType<CallbackID>() == UIType::callback);
static_assert(getUITypeFromType<VAlignment>() == UIType::enumeration);
static_assert(getUITypeFromType<BooleanFormat>() == UIType::enumeration);
static_assert(getUITypeFromType<DisplayProgressStyle>() == UIType::enumeration);
static_assert(getUITypeFromType<StackDirection>() == UIType::enumeration);
static_assert(getUITypeFromType<Visibility>() == UIType::enumeration);
static_assert(getUITypeFromType<UIFont>() == UIType::enumeration);
static_assert(getUITypeFromType<ImageScaling>() == UIType::enumeration);
static_assert(getUITypeFromType<Orientation>() == UIType::enumeration);
static_assert(getUITypeFromType<DockSite>() == UIType::enumeration);
static_assert(getUITypeFromType<HAlignment>() == UIType::enumeration);
