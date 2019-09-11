#include "enums.hpp"
#include <cassert>

UIType getPropertyType(UIProperty property)
{
	switch(property)
	{
		case UIProperty::horizontalAlignment: return UIType::enumeration;
		case UIProperty::verticalAlignment: return UIType::enumeration;
		case UIProperty::margins: return UIType::margins;
		case UIProperty::paddings: return UIType::margins;
		case UIProperty::stackDirection: return UIType::enumeration;
		case UIProperty::dockSite: return UIType::enumeration;
		case UIProperty::visibility: return UIType::enumeration;
		case UIProperty::sizeHint: return UIType::size;
		case UIProperty::fontFamily: return UIType::enumeration;
		case UIProperty::text: return UIType::string;
		case UIProperty::minimum: return UIType::number;
		case UIProperty::maximum: return UIType::number;
		case UIProperty::value: return UIType::number;
		case UIProperty::displayProgressStyle: return UIType::enumeration;
		case UIProperty::isChecked: return UIType::boolean;
		case UIProperty::tabTitle: return UIType::string;
		case UIProperty::selectedIndex: return UIType::integer;
		case UIProperty::columns: return UIType::sizelist;
		case UIProperty::rows: return UIType::sizelist;
	}
	assert(false and "invalid property was passed to getPropertyType!");
}
