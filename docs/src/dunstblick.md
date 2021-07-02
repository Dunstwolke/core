# Dunstblick

A graphical user interface with remote display capabilities.

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

- [Protocol](dunstblick/protocol.md)
- [Layout Engine](dunstblick/layout-engine.md)
- [Layout Language](dunstblick/layout-language.md)
- [Widgets](dunstblick/widgets.md)
