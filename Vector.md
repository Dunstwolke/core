# Dunstblick Vector Graphics Format

## Features

- Path Rendering
	- Filled path (area rendering)
		- Single-colored
		- Two-point-gradient
	- Stroke path ("outline", line rendering)
		- Thickness
		- Color
- Path Segments
	- Line
	- Hermite spline (n-point-spline)



Vector Encoding:

file starts with "reference size":

	width  : varint
	height : varint

after header there will be commands:
first byte of encodes command, after that there is fixed encoding:
	command : [ C² C¹ C⁰ N⁴ N³ N² N¹ N⁰ ]
	x,y     : varint
	r,g,b,a : byte

Commands:
0 - start new path (resets the edge list to zero)
1 - draw N lines (x₀, y₀, x₁, y₁, x₂, y₂,  … )
2 - draw spline with N points (x₀, y₀, x₁, y₁, x₂, y₂,  … )
3 - end path, stroke size = N
4 - end path, fill with current fill
5 - set fill color (r, g, b, a)
6 - set fill gradient (x₀, y₀, r₀, g₀, b₀, a₀, x₁, y₁, r₁, g₁, b₁, a₁)
7 - set stroke color (r, g, b, a)


