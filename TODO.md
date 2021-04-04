# TODO

## dunstblick-app

- [ ] Also free the current_event thingy if any. This would dangle if the application would be closed.
- [ ] Implement new SingleInterfaceApplication
      Single application interface that behaves like a connection to the outer world and replicates that behaviour. All connections will see the same data.
- [ ] Rework the C api to use the event-driven API style as well

## dunstblick-display
- [ ] Create a pure-zig implementation
- [ ] Port the implementation to android

## dunstblick-compiler
- [ ] Create a generator for resource info ("bindgen")

## Old

- [x] Resource System
	- [ ] Vector Drawing
		- [ ] Deserialize Vectors
		- [ ] Define Vector format
		- [ ] Define Vector rendering
- [ ] Implement missing widgets
	- [ ] ComboBox
	- [ ] TreeView
	- [ ] TreeViewItem
	- [ ] ListBox
	- [ ] ListBoxItem
	- [ ] TextBox
	- [ ] ScrollView
	- [x] ScrollBar
	- [ ] SpinEdit
  - [ ] RadioButton
  - [ ] Slider
    - Implement discrete and continuous mode
    - Snap to integers/values
  - [ ] GridLayout
    - Implement `row-span` and `col-span`.
- [ ] Fix Bugs
  - [ ] Empty grid (no colums, no rows) should not crash
- [ ] ~~Add "deferModalDrawing" to render/ui context~~
- [ ] Allow creation of modal popup windows
	- allow rendering stuff *after* everything else
	- required for combo boxes
  - required for message boxes
- Improved text rendering API
	- [ ] Rich text
	- [ ] Full unicode
	- [ ] Multi-Line Rendering
		- [ ] Left-align
		- [ ] Right-align
		- [ ] Center
		- [ ] Justify
- [ ] Object System
	- [ ] Make object properties mark if they have feedback to the client
- [ ] Input Routing
	- [ ] Tab Switch
	- [ ] Filter keyboard for widgets with tab stop
- [ ] Transitions between widgets
	- [ ] Ease-in
	- [ ] Ease-out
	- [ ] Transition between two layouts
- [ ] Widget
	- [ ] Bindable child lists
		- [ ] Add "sort by property" + "sort asc, sort desc"
  - [ ] Give widgets a bindable "name" property that will be passed along with sent events to identify auto-generated widgets.
- [ ] Add support for "push notifications" on the discovery network to allow certain applications announce messages without having an open connection to them
