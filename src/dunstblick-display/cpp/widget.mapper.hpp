struct Button;
template<> constexpr UIWidget widgetTypeToEnum<Button>() { return UIWidget::button; }
struct Label;
template<> constexpr UIWidget widgetTypeToEnum<Label>() { return UIWidget::label; }
struct ComboBox;
template<> constexpr UIWidget widgetTypeToEnum<ComboBox>() { return UIWidget::combobox; }
struct TreeView;
template<> constexpr UIWidget widgetTypeToEnum<TreeView>() { return UIWidget::treeview; }
struct ListBox;
template<> constexpr UIWidget widgetTypeToEnum<ListBox>() { return UIWidget::listbox; }
struct Picture;
template<> constexpr UIWidget widgetTypeToEnum<Picture>() { return UIWidget::picture; }
struct TextBox;
template<> constexpr UIWidget widgetTypeToEnum<TextBox>() { return UIWidget::textbox; }
struct CheckBox;
template<> constexpr UIWidget widgetTypeToEnum<CheckBox>() { return UIWidget::checkbox; }
struct RadioButton;
template<> constexpr UIWidget widgetTypeToEnum<RadioButton>() { return UIWidget::radiobutton; }
struct ScrollView;
template<> constexpr UIWidget widgetTypeToEnum<ScrollView>() { return UIWidget::scrollview; }
struct ScrollBar;
template<> constexpr UIWidget widgetTypeToEnum<ScrollBar>() { return UIWidget::scrollbar; }
struct Slider;
template<> constexpr UIWidget widgetTypeToEnum<Slider>() { return UIWidget::slider; }
struct ProgressBar;
template<> constexpr UIWidget widgetTypeToEnum<ProgressBar>() { return UIWidget::progressbar; }
struct SpinEdit;
template<> constexpr UIWidget widgetTypeToEnum<SpinEdit>() { return UIWidget::spinedit; }
struct Separator;
template<> constexpr UIWidget widgetTypeToEnum<Separator>() { return UIWidget::separator; }
struct Spacer;
template<> constexpr UIWidget widgetTypeToEnum<Spacer>() { return UIWidget::spacer; }
struct Panel;
template<> constexpr UIWidget widgetTypeToEnum<Panel>() { return UIWidget::panel; }
struct Container;
template<> constexpr UIWidget widgetTypeToEnum<Container>() { return UIWidget::container; }
struct TabLayout;
template<> constexpr UIWidget widgetTypeToEnum<TabLayout>() { return UIWidget::tab_layout; }
struct CanvasLayout;
template<> constexpr UIWidget widgetTypeToEnum<CanvasLayout>() { return UIWidget::canvas_layout; }
struct FlowLayout;
template<> constexpr UIWidget widgetTypeToEnum<FlowLayout>() { return UIWidget::flow_layout; }
struct GridLayout;
template<> constexpr UIWidget widgetTypeToEnum<GridLayout>() { return UIWidget::grid_layout; }
struct DockLayout;
template<> constexpr UIWidget widgetTypeToEnum<DockLayout>() { return UIWidget::dock_layout; }
struct StackLayout;
template<> constexpr UIWidget widgetTypeToEnum<StackLayout>() { return UIWidget::stack_layout; }
