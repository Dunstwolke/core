@page dunstblick Dunstblick
@brief A graphical user interface with remote display capabilities.

## Concept

## Design Goals

- Simple API
- Declarative approach
- Automatic layouting
- Feasible to implement on a microcontroller
  - Low memory footprint
  - Reduced graphic fidelity should not hurt the user experience
- Consistent look-and-feel

## Dunstblick URI Scheme

The current URL scheme for dunstblick services is this:
```
dunstblick://host.name:port/
```
The path must be either empty or `/`.

## Further Reading

- @ref dunstblick-proto
- @ref dunstblick-layout-engine
- @ref dunstblick-layout-language
- @ref dunstblick-widgets
- @ref dunstblick.h
