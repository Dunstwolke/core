# Dunstblick Data Types

This document contains descriptions of all data types used in the
dunstblick project. It explains the encoding and data structures in
network streams or on disk.

The document uses a C/C++ like syntax to document compound types with `struct`
definitions. Each struct is considered tightly packed with no padding between
each members, the members are stored in the order of declaration.

Code examples are also in a C/C++ like language using the C type names and operators.

## Primitive Types

### `byte`
A byte is the most basic unit and is an 8 bit unsigned integer
ranging from 0 to 255.

### `uint`
An up-to 32 bit unsigned integer encoded in 1 to 5 bytes. The encoding stores
7 bit per byte of use data, the most significant bit marks that more bytes are to
follow. For each byte read this way, shift the currently decoded value 7 bits to the
left and insert the read bits at the least significant position.

The encoding allows arbitrary bit widths for integers, but dunstblick restricts the
numer of encoded bits to 32.

This encoding allows to store smaller numbers in a smaller amount of bytes than
large numbers. As numbers larger than 5000 aren't common in user interfaces, most
numbers can be encoded in one or two bytes.

| Range                  | Number of bytes |
|------------------------|-----------------|
| 0 … 127                |               1 |
| 128 … 16383            |               2 |
| 16384 … 2097151        |               3 |
| 2097152 … 268435455    |               4 |
| 268435456 … 4294967295 |               5 |

Reference implementation:

```c
uint32_t decode_uint()
{
    uint32_t number = 0;

    uint8_t value;
    do {
        value = read_byte();
        number <<= 7;
        number |= value & 0x7F;
    } while ((value & 0x80) != 0);

    return number;
}

void encode_uint(uint32_t value)
{
    uint8_t buf[5];

    size_t maxidx = 4;
    for (size_t n = 0; n < 5; n++) {
        uint8_t c = (value >> (7 * n)) & 0x7F;
        if (c != 0)
            maxidx = 4 - n;
        if (n > 0)
            c |= 0x80;
        buf[4 - n] = c;
    }

    assert(maxidx < 5);
    write(buf + maxidx, 5 - maxidx);
}
```

### `int`
A signed 32 bit integer encoded in a ZigZag pattern similar to the [ProtoBuf](https://developers.google.com/protocol-buffers/docs/encoding)
signed integers:

| Signed Original | Encoded As |
|-----------------|------------|
|           0	    |          0 |
|          -1     |          1 |
|           1     |          2 |
|          -2     |          3 |
|  2147483647	    | 4294967294 |
| -2147483648	    | 4294967295 |

This is achieved by the following conversion:

```cpp
uint32_t encode(int32_t n) {
  int32_t encoded = (n << 1) ^ (n >> 31); // uses arithmetic shift/sign extend
  return bitcast<uint32_t>(input);
}
```

This encoding allows storing numbers with a small absolute value in a smaller
number of bytes than values with a high absolute value.

Two's complement is not a good encoding here as `-1` would encode to 5 bytes
whereas `1` would encode to a single byte.

### `number`
A floating point number encoded in little-endian IEEE 754 binary32.

### `chunk`
A chunk is a sequence of bytes of unspecified length. The length is not encoded
in the chunk itself and must be either well-known or stored in a previously encoded
field.

## Compound Types

### `string`
A string is a sequence of bytes with a known length. The string is encoded as
the length encoded as an `uint` followed by a `chunk` of *length* bytes:

```c
struct {
  uint length;
  byte data[length];
}
```

## `boolean`
A boolean is encoded as a single byte where 0 is the `false` value and
any other value encodes `true`.

## `color`
An sRGB color value with linear alpha.

```c
struct {
  byte r;
  byte g;
  byte b;
  byte a;
}
```

## `size`
The vertical and horizontal extends of a rectangle.

```c
struct {
  uint width;
  uint height;
}
```

## `point`
A coordinate on the 2D euclidean plane.

```c
struct {
  int x;
  int y;
}
```

## `margins`
Stores the margins of each rectangle edge. Each field stores the distance
to the given edge of a rectangle.

```c
struct {
  int left;
  int top;
  int right;
  int bottom;
}
```

## `sizelist`
Used in the grid widget to configure the rows/columns of the grid and their
respective sizes.

Sizelists store the number of rows/columns, the type for each element (`auto`, `expand`, size in pixels or size in percent) and the size for sized columns.

First, the number of elements is encoded as a `uint`, followed by `ceil(number/4)`
bytes containing the size specification for each element:

The elements are encoded by two bits each, starting with the least significant
bits and going up. If the number of elements is not divisible by 4, the rest 
of the bits is padded with zero.

After that, for each element which encodes a size in pixels, a `uint` follows.
For each element in percent, a single byte follows, encoding the percentage
in the value range `0 … 100. The most significant bit is reserved for future use
and must be 0.

### Element Type Encoding

| Element Type | Bits   |
|--------------|--------|
| `auto`       | `0b00` |
| `expand`     | `0b01` |
| `pixels`     | `0b10` |
| `percentage` | `0b11` |

### Example

The encoding of the list `expand, auto, auto, 374px, 10%, 15%` is the following
byte sequence:
```rb
06    # length
81 0F # element encoding
82 76 # 374 pixels
10    # 10%
15    # 15%
```