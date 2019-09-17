# Common

# Types
- string
- integer
- number
- boolean
- object-id (references globally known object)
- list<object-id>
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

# Messages

rid   = resource id
oid   = object id
obj   = object data
data  = raw data
eid   = event id
value = One possible value of an UIValue. Must have a known type to deserialize
type  = UIType enumeration

## Client Messages

- UploadResource(rid, data)
- AddOrUpdateObject(obj)
- RemoveObject(oid)
- SetView(rid)
- SetRoot(oid)
- SetProperty(oid, name, value) // "unsafe command", uses the serverside object type or fails of property does not exist
- Clear(oid, name)
- InsertRange(oid, name, index, count, value …) // manipulate lists
- RemoveRange(oid, name, index, count) // manipulate lists
- MoveRange(oid, name, indexFrom, indexTo, count) // manipulate lists

# Server Messages

- EventCallback(eid)
- PropertyChanged(oid, name, value)

