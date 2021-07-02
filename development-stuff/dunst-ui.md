# Dunstwolke™ User Interface

- Unterstützt nur Standard-Widgets
	- [x] Button
	- [x] Label
	- [x] RadioButton
	- [x] CheckBox
	- [ ] TextBox
	- [ ] Picture (Bitmap-Grafik, Vektor-Grafik)
	- [ ] ListBox
	- [ ] ListBoxItem
	- [ ] TreeView
	- [ ] TreeItem
	- [ ] DataGrid
	- [ ] ComboBox
	- [ ] ScrollView
	- [x] Slider
	- [x] ProgressBar
	- [ ] NumberSpin
	- [x] Separator
	- [x] StackLayout
	- [x] DockLayout
	- [x] CanvasLayout
	- [x] GridLayout
	- [x] FlowLayout
	- [x] Spacer
	- [x] Panel
	- [x] TabPanel
- Supported modale und nonmodale Dialoge/Kind-Fenster
	- Dialoge wie ein "Inventarfenster" können geöffnet werden
	- Dialoge sind immer floating
- Layouts ermöglichen Bindings auf Listen
	- Angabe von Template-ID + List-Binding
	- Instanzen von Templates werden wiederverwendet (korrektes insert/remove-verhalten)
- Widgets können Tastatur-Filter haben
	- Widget verschickt *alle* Tastatur-Events
	- Widget verschickt nur Accelerators (Hotkeys)
		- TODO: Globale Hotkey-Table?
		- TODO: Hotkey-Table per Widget?
- Widgets haben Standard-Hotkeys
	- Clipboard: *Ctrl-C*, *Ctrl-V*, *Ctrl-X*
	- Selektion: *Ctrl-A*, Shift+Pfeiltaste, Ctrl+Pfeiltaste
	- Tab-Navigation: *Tab*, *Shift-Tab*
- Ist 100% deklarativ
	- Templates erlauben
	- Widgets können nur über Templates+Listen dynamisch erstellt/gelöscht werden
- Nutzt eine Art MVVM-Pattern
	- Widgets können auf manche Properties einen Wert binden
	- Bindung kann ToWidget, FromWidget, Bidirektional sein
	- Als Werte werden nur `object`, `number`, `string`, `bool` sowie `list` unterstützt
		- JSON-ähnliches Format
		- Anwendung kann beliebige Sub-Bäume der Datenstruktur aktualisieren
			- Aktualisierung einer Eigenschaft → Regeneration und Refresh der davon abhängigen UI
		- Objekte benötigen eine eindeutige ID für Callbacks
	- Bindbare Properties
		- Text (`string`)
		- Value (`number`)
		- Minimum (`number`)
		- Maximum (`number`)
		- Children (`list`)
- Kann auch Remote benutzt werden
	- Voll asynchrones Interface
	- Benutzt nur "Message Passing" als Interface
- Kann Resourcen cachen
	- UI besteht aus Beschreibungsdaten, alle Resouren also im Voraus bekannt
	- Resourcen haben eine ID
	- Anwendung überträgt Resourcen-Liste + Hashes
		- Falls Hash gleich, kann Resource wiederverwendet werden
		→ reduziert bandbreite
- Rendering sehr schlicht
	- Einfarbige Linien + Flächen
	- Vektorgrafiken für Icons
	- Drei Schriftarten
		- Monospace
		- Serif
		- Sans