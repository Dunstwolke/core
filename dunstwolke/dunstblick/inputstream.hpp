#ifndef INPUTSTREAM_HPP
#define INPUTSTREAM_HPP

#include <cstddef>
#include <cstdint>
#include <string_view>

#include "types.hpp"
#include "object.hpp"

// varint encoding:
// numbers are encoded with a 7 bit big endian code
// each byte that has the MSB set notes that there
// is more data to read in
struct InputStream
{
    uint8_t const * data;
    size_t length;
    size_t offset;

    explicit InputStream(uint8_t const * data, size_t length);

    template<size_t N>
    explicit InputStream(uint8_t const (&_data)[N]) :
        InputStream(_data, N)
    {

    }

    uint8_t read_byte(); // reads a single byte

    uint32_t read_uint(); // uses varint encoding

    float read_float(); // uses ieee754 encoding

    std::string_view read_string();

    // enums are always 8-bit-sized
    template<typename T>
    T read_enum() {
        static_assert(std::is_enum_v<T>);
        static_assert(sizeof(T) == 1);
        return T(read_byte());
    }

	template<typename T>
	static constexpr bool check_is_uniqueid(xstd::unique_id<T>) { return true; }

	template<typename T>
	T read_id() {
		static_assert(check_is_uniqueid(T()) == true);
		return T(read_uint());
	}

	std::tuple<UIProperty, bool> read_property_enum();

	Object read_object();

	UIValue read_value(UIType type);
};

#endif // INPUTSTREAM_HPP
