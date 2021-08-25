# Dunstwolke

Repository for developing software for a "personal cloud" project

## Dunstblick

A UI system with a different approach:

Serialize widgets and layout structure into a binary structure, deserialize this on the server side
and only communicate with state changes in "object values" (bindings), not widget states.

### Video

[![](https://mq32.de/public/screenshot/951e859e400b506b1e6f8cedf0838b4d.png)](https://mq32.de/public/dunstwolke-04.mp4)

### Examples

- [Calculator](https://github.com/Dunstwolke/core/tree/master/src/examples/calculator)
- Address Book
- Text Editor
- Media Player
- Chat Application
- Game Menu

### Documentation

- Basic Concepts
- Layout Definition and Semantics
- Serialization / Binary Formats
- 
- 

### Configuration

For the desktop variant, the following environment variables are available for configuration:
- `DUNSTBLICK_DPI` might be used to set a fallback display density when the display one could not be determined
- `DUNSTBLICK_FULLSCREEN` might be used to enforce fullscreen or window mode. Use `yes` or `no`
