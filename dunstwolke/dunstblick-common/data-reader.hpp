#ifndef DUNSTBLICK_DATAREADER_HPP
#define DUNSTBLICK_DATAREADER_HPP

#include <cstddef>
#include <cstdint>
#include <string_view>
#include <tuple>

// varint encoding:
// numbers are encoded with a 7 bit big endian code
// each byte that has the MSB set notes that there
// is more data to read in
struct DataReader
{
    uint8_t const * data;
    size_t length;
    size_t offset;

    explicit DataReader(void const * _data, size_t _length) :
	    data(reinterpret_cast<uint8_t const *>(_data)),
	    length(_length),
	    offset(0)
	{

	}

    template<size_t N>
    explicit DataReader(uint8_t const (&_data)[N]) :
        DataReader(_data, N)
    {

    }

    uint8_t read_byte()
	{
	    if(offset >= length)
	        throw std::out_of_range("stream is out of bytes");
	    return data[offset++];
	}

    uint32_t read_uint()
	{
	    uint32_t number = 0;

	    uint8_t value;
	    do {
	        value = read_byte();
	        number <<= 7;
	        number |= value & 0x7F;
	    } while((value & 0x80) != 0);

	    return number;
	}

    float read_float()
	{
	    uint8_t buf[4];
	    buf[0] = read_byte();
	    buf[1] = read_byte();
	    buf[2] = read_byte();
	    buf[3] = read_byte();
	    return *reinterpret_cast<float const*>(buf);
	}

    std::string_view read_string()
	{
	    auto const len = read_uint();
	    if(offset + len > length)
	        throw std::out_of_range("stream is out of bytes!");
	    std::string_view result(reinterpret_cast<char const *>(data + offset), len);
	    offset += len;
		return result;
	}

	std::tuple<void const *, size_t> read_data(size_t len)
	{
		if(offset + len > length)
	        throw std::out_of_range("stream is out of bytes");

		void const * start = &data[offset];
		offset += len;
		return std::make_tuple(start, len);
	}

	std::tuple<void const *, size_t> read_to_end()
	{
		return read_data(length - offset);
	}

};

#endif // DATAREADER_HPP
