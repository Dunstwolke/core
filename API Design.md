# Common
rid  = resource id
oid  = object id
obj  = object data
data = raw data

# Types
- string
- integer
- number
- boolean
- object (locally stored object, has no id)
- object-id (references globally known object)
- list<object | object-id>
- resource-id

object = [](key,type,value)
key ist der "Name" der Property

# Known Conversions
string  → number
integer → number
boolean → number

boolean → string
integer → string
number  → string

number  → integer
string  → integer
boolean → integer

# Lists
listen können nur in objekten speichert sein, haben folgende API
- clear()
- insertRange(oid, prop, index, []value)
- removeRange(oid, prop, index, count=1)
- move(oid, prop, indexFrom, indexTo, count=1)

AnyWidget {
	binding-context: resource(…); // use global object
}

AnyWidget {
	binding-context: bind(…);
}

AnyWidget {
	child-source: bind(…);
	child-template: resource(…);
}
Kinder werden alle ersetzt durch template-varianten die
an eine liste gebunden sind. für jedes kind wird das
template instanziert.
problem für die zukunft: template selector für versch. untertypen?!


# Client Commands

- UploadResource(rid, data)
- SetView(rid)
- SetRoot(obj)
- SetProperty(oid, idx, type, value)

