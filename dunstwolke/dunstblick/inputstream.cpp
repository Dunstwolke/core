#include "inputstream.hpp"
#include <stdexcept>


InputStream::InputStream(const uint8_t *data, size_t length) :
    data(data), length(length), offset(0)
{

}

uint8_t InputStream::read_byte()
{
    if(offset >= length)
        throw std::out_of_range("stream is out of bytes");
    return data[offset++];
}

uint32_t InputStream::read_uint()
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

float InputStream::read_float()
{
    uint8_t buf[4];
    buf[0] = read_byte();
    buf[1] = read_byte();
    buf[2] = read_byte();
    buf[3] = read_byte();
    return *reinterpret_cast<float const*>(buf);
}

std::string_view InputStream::read_string()
{
    auto const len = read_uint();
    if(offset + len >= length)
        throw std::out_of_range("stream is out of bytes!");
    std::string_view result(reinterpret_cast<char const *>(data + offset), len);
    offset += len;
    return result;
}
