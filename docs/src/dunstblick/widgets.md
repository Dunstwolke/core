# Dunstblick Widgets

Description of the Widgets available in [Dunstblick](../dunstblick.md)

## Overview

The following widgets are available in [Dunstblick](../dunstblick.md):

- [Button](#widget:button)
- [Label](#widget:label)
- [Picture](#widget:picture)
- [TextBox](#widget:textbox)
- [CheckBox](#widget:checkbox)
- [RadioButton](#widget:radiobutton)
- [ScrollView](#widget:scrollview)
- [ScrollBar](#widget:scrollbar)
- [Slider](#widget:slider)
- [ProgressBar](#widget:progressbar)
- [SpinEdit](#widget:spinedit)
- [Separator](#widget:separator)
- [Spacer](#widget:spacer)
- [Panel](#widget:panel)
- [Container](#widget:container)
- [TabLayout](#widget:tab_layout)
- [CanvasLayout](#widget:canvas_layout)
- [FlowLayout](#widget:flow_layout)
- [GridLayout](#widget:grid_layout)
- [DockLayout](#widget:dock_layout)
- [StackLayout](#widget:stack_layout)
- [ComboBox](#widget:combobox)
- [TreeView](#widget:treeview)
- [ListBox](#widget:listbox)

## Widgets

<h3 id="widget:button">Button</h3>
The button provides the user the ability to trigger a single-shot action like *Save* or *Load*. It provides a event callback when the user clicks it.

**Properties:**

[`horizontal-alignment`](#property:horizontal_alignment), [`vertical-alignment`](#property:vertical_alignment), [`margins`](#property:margins), [`paddings`](#property:paddings), [`dock-site`](#property:dock_site), [`visibility`](#property:visibility), [`enabled`](#property:enabled), [`hit-test-visible`](#property:hit_test_visible), [`binding-context`](#property:binding_context), [`child-source`](#property:child_source), [`child-template`](#property:child_template), [`widget-name`](#property:widget_name), [`tab-title`](#property:tab_title), [`size-hint`](#property:size_hint), [`left`](#property:left), [`top`](#property:top), [`on-click`](#property:on_click)

<h3 id="widget:label">Label</h3>
This widget is used for text rendering. It will display its `text`, which can also be a multiline string.

**Properties:**

[`horizontal-alignment`](#property:horizontal_alignment), [`vertical-alignment`](#property:vertical_alignment), [`margins`](#property:margins), [`paddings`](#property:paddings), [`dock-site`](#property:dock_site), [`visibility`](#property:visibility), [`enabled`](#property:enabled), [`hit-test-visible`](#property:hit_test_visible), [`binding-context`](#property:binding_context), [`child-source`](#property:child_source), [`child-template`](#property:child_template), [`widget-name`](#property:widget_name), [`tab-title`](#property:tab_title), [`size-hint`](#property:size_hint), [`left`](#property:left), [`top`](#property:top), [`text`](#property:text), [`font-family`](#property:font_family)

<h3 id="widget:picture">Picture</h3>
This widget renders a bitmap or drawing. The image will be set using a certain size mode:

- `none`: The image will be displayed unscaled on the top-left of the Picture and will be cut off the edges of the Picture.
- `center`: The image will be centered inside the Picture without scaling. All excess will be cut off.
- `stretch`: The image will be stretched so it will fill the full Picture. This is a very nice option for background images.
- `zoom`: The image will be scaled in such a way that it will always touch at least two sides of the Picture. It will always be fully visible and no part of the image will be cut off. This mode is respecting the aspect of the image.
- `cover`: The image will be scaled in such a way that it will fully cover the Picture. This mode is respecting the aspect of the image, thus excess is cut off.
- `contain`: This is a combined mode which will behave like `zoom` if the image is larger than the Picture, otherwise it will behave like `center`.

**Properties:**

[`horizontal-alignment`](#property:horizontal_alignment), [`vertical-alignment`](#property:vertical_alignment), [`margins`](#property:margins), [`paddings`](#property:paddings), [`dock-site`](#property:dock_site), [`visibility`](#property:visibility), [`enabled`](#property:enabled), [`hit-test-visible`](#property:hit_test_visible), [`binding-context`](#property:binding_context), [`child-source`](#property:child_source), [`child-template`](#property:child_template), [`widget-name`](#property:widget_name), [`tab-title`](#property:tab_title), [`size-hint`](#property:size_hint), [`left`](#property:left), [`top`](#property:top), [`image`](#property:image), [`image-scaling`](#property:image_scaling)

<h3 id="widget:textbox">TextBox</h3>
The text box is a single line text input field. The user can enter any text that has a single line.

**Properties:**

[`horizontal-alignment`](#property:horizontal_alignment), [`vertical-alignment`](#property:vertical_alignment), [`margins`](#property:margins), [`paddings`](#property:paddings), [`dock-site`](#property:dock_site), [`visibility`](#property:visibility), [`enabled`](#property:enabled), [`hit-test-visible`](#property:hit_test_visible), [`binding-context`](#property:binding_context), [`child-source`](#property:child_source), [`child-template`](#property:child_template), [`widget-name`](#property:widget_name), [`tab-title`](#property:tab_title), [`size-hint`](#property:size_hint), [`left`](#property:left), [`top`](#property:top), [`text`](#property:text)

<h3 id="widget:checkbox">CheckBox</h3>
The combobox provides the user with a yes/no option that can be toggled when clicked. Each combobox is separate from each other, and the property `is-checked` will be toggled.

**Properties:**

[`horizontal-alignment`](#property:horizontal_alignment), [`vertical-alignment`](#property:vertical_alignment), [`margins`](#property:margins), [`paddings`](#property:paddings), [`dock-site`](#property:dock_site), [`visibility`](#property:visibility), [`enabled`](#property:enabled), [`hit-test-visible`](#property:hit_test_visible), [`binding-context`](#property:binding_context), [`child-source`](#property:child_source), [`child-template`](#property:child_template), [`widget-name`](#property:widget_name), [`tab-title`](#property:tab_title), [`size-hint`](#property:size_hint), [`left`](#property:left), [`top`](#property:top), [`is-checked`](#property:is_checked)

<h3 id="widget:radiobutton">RadioButton</h3>
Radio buttons are grouped together by an integer value and will show active when that value matches their `index`. If the user clicks the radio button, the `group` value is set to the `selected-index`.

**Properties:**

[`horizontal-alignment`](#property:horizontal_alignment), [`vertical-alignment`](#property:vertical_alignment), [`margins`](#property:margins), [`paddings`](#property:paddings), [`dock-site`](#property:dock_site), [`visibility`](#property:visibility), [`enabled`](#property:enabled), [`hit-test-visible`](#property:hit_test_visible), [`binding-context`](#property:binding_context), [`child-source`](#property:child_source), [`child-template`](#property:child_template), [`widget-name`](#property:widget_name), [`tab-title`](#property:tab_title), [`size-hint`](#property:size_hint), [`left`](#property:left), [`top`](#property:top), [`group`](#property:group), [`selected-index`](#property:selected_index)

<h3 id="widget:scrollview">ScrollView</h3>
This widget doesn't have any documentation at this moment.

**Properties:**

[`horizontal-alignment`](#property:horizontal_alignment), [`vertical-alignment`](#property:vertical_alignment), [`margins`](#property:margins), [`paddings`](#property:paddings), [`dock-site`](#property:dock_site), [`visibility`](#property:visibility), [`enabled`](#property:enabled), [`hit-test-visible`](#property:hit_test_visible), [`binding-context`](#property:binding_context), [`child-source`](#property:child_source), [`child-template`](#property:child_template), [`widget-name`](#property:widget_name), [`tab-title`](#property:tab_title), [`size-hint`](#property:size_hint), [`left`](#property:left), [`top`](#property:top)

<h3 id="widget:scrollbar">ScrollBar</h3>
This widget doesn't have any documentation at this moment.

**Properties:**

[`horizontal-alignment`](#property:horizontal_alignment), [`vertical-alignment`](#property:vertical_alignment), [`margins`](#property:margins), [`paddings`](#property:paddings), [`dock-site`](#property:dock_site), [`visibility`](#property:visibility), [`enabled`](#property:enabled), [`hit-test-visible`](#property:hit_test_visible), [`binding-context`](#property:binding_context), [`child-source`](#property:child_source), [`child-template`](#property:child_template), [`widget-name`](#property:widget_name), [`tab-title`](#property:tab_title), [`size-hint`](#property:size_hint), [`left`](#property:left), [`top`](#property:top), [`orientation`](#property:orientation), [`minimum`](#property:minimum), [`value`](#property:value), [`maximum`](#property:maximum)

<h3 id="widget:slider">Slider</h3>
This widget doesn't have any documentation at this moment.

**Properties:**

[`horizontal-alignment`](#property:horizontal_alignment), [`vertical-alignment`](#property:vertical_alignment), [`margins`](#property:margins), [`paddings`](#property:paddings), [`dock-site`](#property:dock_site), [`visibility`](#property:visibility), [`enabled`](#property:enabled), [`hit-test-visible`](#property:hit_test_visible), [`binding-context`](#property:binding_context), [`child-source`](#property:child_source), [`child-template`](#property:child_template), [`widget-name`](#property:widget_name), [`tab-title`](#property:tab_title), [`size-hint`](#property:size_hint), [`left`](#property:left), [`top`](#property:top), [`orientation`](#property:orientation), [`minimum`](#property:minimum), [`value`](#property:value), [`maximum`](#property:maximum)

<h3 id="widget:progressbar">ProgressBar</h3>
This widget doesn't have any documentation at this moment.

**Properties:**

[`horizontal-alignment`](#property:horizontal_alignment), [`vertical-alignment`](#property:vertical_alignment), [`margins`](#property:margins), [`paddings`](#property:paddings), [`dock-site`](#property:dock_site), [`visibility`](#property:visibility), [`enabled`](#property:enabled), [`hit-test-visible`](#property:hit_test_visible), [`binding-context`](#property:binding_context), [`child-source`](#property:child_source), [`child-template`](#property:child_template), [`widget-name`](#property:widget_name), [`tab-title`](#property:tab_title), [`size-hint`](#property:size_hint), [`left`](#property:left), [`top`](#property:top), [`orientation`](#property:orientation), [`minimum`](#property:minimum), [`value`](#property:value), [`maximum`](#property:maximum), [`display-progress-style`](#property:display_progress_style)

<h3 id="widget:spinedit">SpinEdit</h3>
This widget doesn't have any documentation at this moment.

**Properties:**

[`horizontal-alignment`](#property:horizontal_alignment), [`vertical-alignment`](#property:vertical_alignment), [`margins`](#property:margins), [`paddings`](#property:paddings), [`dock-site`](#property:dock_site), [`visibility`](#property:visibility), [`enabled`](#property:enabled), [`hit-test-visible`](#property:hit_test_visible), [`binding-context`](#property:binding_context), [`child-source`](#property:child_source), [`child-template`](#property:child_template), [`widget-name`](#property:widget_name), [`tab-title`](#property:tab_title), [`size-hint`](#property:size_hint), [`left`](#property:left), [`top`](#property:top), [`orientation`](#property:orientation), [`minimum`](#property:minimum), [`value`](#property:value), [`maximum`](#property:maximum)

<h3 id="widget:separator">Separator</h3>
This widget doesn't have any documentation at this moment.

**Properties:**

[`horizontal-alignment`](#property:horizontal_alignment), [`vertical-alignment`](#property:vertical_alignment), [`margins`](#property:margins), [`paddings`](#property:paddings), [`dock-site`](#property:dock_site), [`visibility`](#property:visibility), [`enabled`](#property:enabled), [`hit-test-visible`](#property:hit_test_visible), [`binding-context`](#property:binding_context), [`child-source`](#property:child_source), [`child-template`](#property:child_template), [`widget-name`](#property:widget_name), [`tab-title`](#property:tab_title), [`size-hint`](#property:size_hint), [`left`](#property:left), [`top`](#property:top)

<h3 id="widget:spacer">Spacer</h3>
This widget doesn't have any documentation at this moment.

**Properties:**

[`horizontal-alignment`](#property:horizontal_alignment), [`vertical-alignment`](#property:vertical_alignment), [`margins`](#property:margins), [`paddings`](#property:paddings), [`dock-site`](#property:dock_site), [`visibility`](#property:visibility), [`enabled`](#property:enabled), [`hit-test-visible`](#property:hit_test_visible), [`binding-context`](#property:binding_context), [`child-source`](#property:child_source), [`child-template`](#property:child_template), [`widget-name`](#property:widget_name), [`tab-title`](#property:tab_title), [`size-hint`](#property:size_hint), [`left`](#property:left), [`top`](#property:top)

<h3 id="widget:panel">Panel</h3>
This widget doesn't have any documentation at this moment.

**Properties:**

[`horizontal-alignment`](#property:horizontal_alignment), [`vertical-alignment`](#property:vertical_alignment), [`margins`](#property:margins), [`paddings`](#property:paddings), [`dock-site`](#property:dock_site), [`visibility`](#property:visibility), [`enabled`](#property:enabled), [`hit-test-visible`](#property:hit_test_visible), [`binding-context`](#property:binding_context), [`child-source`](#property:child_source), [`child-template`](#property:child_template), [`widget-name`](#property:widget_name), [`tab-title`](#property:tab_title), [`size-hint`](#property:size_hint), [`left`](#property:left), [`top`](#property:top)

<h3 id="widget:container">Container</h3>
This widget doesn't have any documentation at this moment.

**Properties:**

[`horizontal-alignment`](#property:horizontal_alignment), [`vertical-alignment`](#property:vertical_alignment), [`margins`](#property:margins), [`paddings`](#property:paddings), [`dock-site`](#property:dock_site), [`visibility`](#property:visibility), [`enabled`](#property:enabled), [`hit-test-visible`](#property:hit_test_visible), [`binding-context`](#property:binding_context), [`child-source`](#property:child_source), [`child-template`](#property:child_template), [`widget-name`](#property:widget_name), [`tab-title`](#property:tab_title), [`size-hint`](#property:size_hint), [`left`](#property:left), [`top`](#property:top)

<h3 id="widget:tab_layout">TabLayout</h3>
This widget doesn't have any documentation at this moment.

**Properties:**

[`horizontal-alignment`](#property:horizontal_alignment), [`vertical-alignment`](#property:vertical_alignment), [`margins`](#property:margins), [`paddings`](#property:paddings), [`dock-site`](#property:dock_site), [`visibility`](#property:visibility), [`enabled`](#property:enabled), [`hit-test-visible`](#property:hit_test_visible), [`binding-context`](#property:binding_context), [`child-source`](#property:child_source), [`child-template`](#property:child_template), [`widget-name`](#property:widget_name), [`tab-title`](#property:tab_title), [`size-hint`](#property:size_hint), [`left`](#property:left), [`top`](#property:top), [`selected-index`](#property:selected_index)

<h3 id="widget:canvas_layout">CanvasLayout</h3>
This widget doesn't have any documentation at this moment.

**Properties:**

[`horizontal-alignment`](#property:horizontal_alignment), [`vertical-alignment`](#property:vertical_alignment), [`margins`](#property:margins), [`paddings`](#property:paddings), [`dock-site`](#property:dock_site), [`visibility`](#property:visibility), [`enabled`](#property:enabled), [`hit-test-visible`](#property:hit_test_visible), [`binding-context`](#property:binding_context), [`child-source`](#property:child_source), [`child-template`](#property:child_template), [`widget-name`](#property:widget_name), [`tab-title`](#property:tab_title), [`size-hint`](#property:size_hint), [`left`](#property:left), [`top`](#property:top)

<h3 id="widget:flow_layout">FlowLayout</h3>
This widget doesn't have any documentation at this moment.

**Properties:**

[`horizontal-alignment`](#property:horizontal_alignment), [`vertical-alignment`](#property:vertical_alignment), [`margins`](#property:margins), [`paddings`](#property:paddings), [`dock-site`](#property:dock_site), [`visibility`](#property:visibility), [`enabled`](#property:enabled), [`hit-test-visible`](#property:hit_test_visible), [`binding-context`](#property:binding_context), [`child-source`](#property:child_source), [`child-template`](#property:child_template), [`widget-name`](#property:widget_name), [`tab-title`](#property:tab_title), [`size-hint`](#property:size_hint), [`left`](#property:left), [`top`](#property:top)

<h3 id="widget:grid_layout">GridLayout</h3>
This widget doesn't have any documentation at this moment.

**Properties:**

[`horizontal-alignment`](#property:horizontal_alignment), [`vertical-alignment`](#property:vertical_alignment), [`margins`](#property:margins), [`paddings`](#property:paddings), [`dock-site`](#property:dock_site), [`visibility`](#property:visibility), [`enabled`](#property:enabled), [`hit-test-visible`](#property:hit_test_visible), [`binding-context`](#property:binding_context), [`child-source`](#property:child_source), [`child-template`](#property:child_template), [`widget-name`](#property:widget_name), [`tab-title`](#property:tab_title), [`size-hint`](#property:size_hint), [`left`](#property:left), [`top`](#property:top), [`columns`](#property:columns), [`rows`](#property:rows)

<h3 id="widget:dock_layout">DockLayout</h3>
This widget doesn't have any documentation at this moment.

**Properties:**

[`horizontal-alignment`](#property:horizontal_alignment), [`vertical-alignment`](#property:vertical_alignment), [`margins`](#property:margins), [`paddings`](#property:paddings), [`dock-site`](#property:dock_site), [`visibility`](#property:visibility), [`enabled`](#property:enabled), [`hit-test-visible`](#property:hit_test_visible), [`binding-context`](#property:binding_context), [`child-source`](#property:child_source), [`child-template`](#property:child_template), [`widget-name`](#property:widget_name), [`tab-title`](#property:tab_title), [`size-hint`](#property:size_hint), [`left`](#property:left), [`top`](#property:top)

<h3 id="widget:stack_layout">StackLayout</h3>
This widget doesn't have any documentation at this moment.

**Properties:**

[`horizontal-alignment`](#property:horizontal_alignment), [`vertical-alignment`](#property:vertical_alignment), [`margins`](#property:margins), [`paddings`](#property:paddings), [`dock-site`](#property:dock_site), [`visibility`](#property:visibility), [`enabled`](#property:enabled), [`hit-test-visible`](#property:hit_test_visible), [`binding-context`](#property:binding_context), [`child-source`](#property:child_source), [`child-template`](#property:child_template), [`widget-name`](#property:widget_name), [`tab-title`](#property:tab_title), [`size-hint`](#property:size_hint), [`left`](#property:left), [`top`](#property:top), [`orientation`](#property:orientation)

<h3 id="widget:combobox">ComboBox</h3>
This widget doesn't have any documentation at this moment.

**Properties:**

[`horizontal-alignment`](#property:horizontal_alignment), [`vertical-alignment`](#property:vertical_alignment), [`margins`](#property:margins), [`paddings`](#property:paddings), [`dock-site`](#property:dock_site), [`visibility`](#property:visibility), [`enabled`](#property:enabled), [`hit-test-visible`](#property:hit_test_visible), [`binding-context`](#property:binding_context), [`child-source`](#property:child_source), [`child-template`](#property:child_template), [`widget-name`](#property:widget_name), [`tab-title`](#property:tab_title), [`size-hint`](#property:size_hint), [`left`](#property:left), [`top`](#property:top)

<h3 id="widget:treeview">TreeView</h3>
This widget doesn't have any documentation at this moment.

**Properties:**

[`horizontal-alignment`](#property:horizontal_alignment), [`vertical-alignment`](#property:vertical_alignment), [`margins`](#property:margins), [`paddings`](#property:paddings), [`dock-site`](#property:dock_site), [`visibility`](#property:visibility), [`enabled`](#property:enabled), [`hit-test-visible`](#property:hit_test_visible), [`binding-context`](#property:binding_context), [`child-source`](#property:child_source), [`child-template`](#property:child_template), [`widget-name`](#property:widget_name), [`tab-title`](#property:tab_title), [`size-hint`](#property:size_hint), [`left`](#property:left), [`top`](#property:top)

<h3 id="widget:listbox">ListBox</h3>
This widget doesn't have any documentation at this moment.

**Properties:**

[`horizontal-alignment`](#property:horizontal_alignment), [`vertical-alignment`](#property:vertical_alignment), [`margins`](#property:margins), [`paddings`](#property:paddings), [`dock-site`](#property:dock_site), [`visibility`](#property:visibility), [`enabled`](#property:enabled), [`hit-test-visible`](#property:hit_test_visible), [`binding-context`](#property:binding_context), [`child-source`](#property:child_source), [`child-template`](#property:child_template), [`widget-name`](#property:widget_name), [`tab-title`](#property:tab_title), [`size-hint`](#property:size_hint), [`left`](#property:left), [`top`](#property:top)

## Properties

<h3 id="property:horizontal_alignment">horizontal-alignment</h3>
This property doesn't have any documentation at this moment.

**Data Type:** `enumeration`

**Possible Values:** `left`, `center`, `right`, `stretch`
<h3 id="property:vertical_alignment">vertical-alignment</h3>
This property doesn't have any documentation at this moment.

**Data Type:** `enumeration`

**Possible Values:** `top`, `middle`, `bottom`, `stretch`
<h3 id="property:margins">margins</h3>
This property doesn't have any documentation at this moment.

**Data Type:** `margins`


<h3 id="property:paddings">paddings</h3>
This property doesn't have any documentation at this moment.

**Data Type:** `margins`


<h3 id="property:dock_site">dock-site</h3>
This property doesn't have any documentation at this moment.

**Data Type:** `enumeration`

**Possible Values:** `left`, `right`, `top`, `bottom`
<h3 id="property:visibility">visibility</h3>
This property doesn't have any documentation at this moment.

**Data Type:** `enumeration`

**Possible Values:** `visible`, `hidden`, `collapsed`
<h3 id="property:size_hint">size-hint</h3>
This property doesn't have any documentation at this moment.

**Data Type:** `size`


<h3 id="property:font_family">font-family</h3>
This property doesn't have any documentation at this moment.

**Data Type:** `enumeration`

**Possible Values:** `sans`, `serif`, `monospace`
<h3 id="property:text">text</h3>
This property doesn't have any documentation at this moment.

**Data Type:** `string`


<h3 id="property:minimum">minimum</h3>
This property doesn't have any documentation at this moment.

**Data Type:** `number`


<h3 id="property:maximum">maximum</h3>
This property doesn't have any documentation at this moment.

**Data Type:** `number`


<h3 id="property:value">value</h3>
This property doesn't have any documentation at this moment.

**Data Type:** `number`


<h3 id="property:display_progress_style">display-progress-style</h3>
This property doesn't have any documentation at this moment.

**Data Type:** `enumeration`

**Possible Values:** `none`, `percent`, `absolute`
<h3 id="property:is_checked">is-checked</h3>
This property doesn't have any documentation at this moment.

**Data Type:** `boolean`


<h3 id="property:tab_title">tab-title</h3>
This property doesn't have any documentation at this moment.

**Data Type:** `string`


<h3 id="property:selected_index">selected-index</h3>
This property doesn't have any documentation at this moment.

**Data Type:** `integer`


<h3 id="property:group">group</h3>
This property doesn't have any documentation at this moment.

**Data Type:** `integer`


<h3 id="property:columns">columns</h3>
This property doesn't have any documentation at this moment.

**Data Type:** `sizelist`


<h3 id="property:rows">rows</h3>
This property doesn't have any documentation at this moment.

**Data Type:** `sizelist`


<h3 id="property:left">left</h3>
This property doesn't have any documentation at this moment.

**Data Type:** `integer`


<h3 id="property:top">top</h3>
This property doesn't have any documentation at this moment.

**Data Type:** `integer`


<h3 id="property:enabled">enabled</h3>
This property doesn't have any documentation at this moment.

**Data Type:** `boolean`


<h3 id="property:image_scaling">image-scaling</h3>
This property doesn't have any documentation at this moment.

**Data Type:** `enumeration`

**Possible Values:** `none`, `center`, `stretch`, `zoom`, `contain`, `cover`
<h3 id="property:image">image</h3>
This property doesn't have any documentation at this moment.

**Data Type:** `resource`


<h3 id="property:binding_context">binding-context</h3>
This property doesn't have any documentation at this moment.

**Data Type:** `object`


<h3 id="property:child_source">child-source</h3>
This property doesn't have any documentation at this moment.

**Data Type:** `objectlist`


<h3 id="property:child_template">child-template</h3>
This property doesn't have any documentation at this moment.

**Data Type:** `resource`


<h3 id="property:hit_test_visible">hit-test-visible</h3>
This property doesn't have any documentation at this moment.

**Data Type:** `boolean`


<h3 id="property:on_click">on-click</h3>
This property doesn't have any documentation at this moment.

**Data Type:** `event`


<h3 id="property:orientation">orientation</h3>
This property doesn't have any documentation at this moment.

**Data Type:** `enumeration`

**Possible Values:** `horizontal`, `vertical`
<h3 id="property:widget_name">widget-name</h3>
This property doesn't have any documentation at this moment.

**Data Type:** `widget`


