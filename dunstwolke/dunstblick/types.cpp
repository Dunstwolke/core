#include "types.hpp"


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

