using UIValue = std::variant<
	std::monostate,
	int,
	float,
	std::string,
	uint8_t,
	UIMargin,
	UIColor,
	SDL_Size,
	SDL_Point,
	UIResourceID,
	bool,
	UISizeList
>;

static_assert(std::is_same_v<std::variant_alternative_t<size_t(UIType::invalid),     UIValue>, std::monostate>);
static_assert(std::is_same_v<std::variant_alternative_t<size_t(UIType::integer),     UIValue>, int>);
static_assert(std::is_same_v<std::variant_alternative_t<size_t(UIType::number),     UIValue>, float>);
static_assert(std::is_same_v<std::variant_alternative_t<size_t(UIType::string),     UIValue>, std::string>);
static_assert(std::is_same_v<std::variant_alternative_t<size_t(UIType::enumeration),     UIValue>, uint8_t>);
static_assert(std::is_same_v<std::variant_alternative_t<size_t(UIType::margins),     UIValue>, UIMargin>);
static_assert(std::is_same_v<std::variant_alternative_t<size_t(UIType::color),     UIValue>, UIColor>);
static_assert(std::is_same_v<std::variant_alternative_t<size_t(UIType::size),     UIValue>, SDL_Size>);
static_assert(std::is_same_v<std::variant_alternative_t<size_t(UIType::point),     UIValue>, SDL_Point>);
static_assert(std::is_same_v<std::variant_alternative_t<size_t(UIType::resource),     UIValue>, UIResourceID>);
static_assert(std::is_same_v<std::variant_alternative_t<size_t(UIType::boolean),     UIValue>, bool>);
static_assert(std::is_same_v<std::variant_alternative_t<size_t(UIType::sizelist),     UIValue>, UISizeList>);
