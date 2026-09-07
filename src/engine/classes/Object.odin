package classes

import "core:fmt"

Class_Info :: struct {
    name:   string,
    parent: ^Class_Info,
}

Object_Class := Class_Info{
    name   = "Object",
    parent = nil,
}

Object :: struct {
    class:    ^Class_Info,
    name:     string,
    parent:   ^Object,
    children: [dynamic]^Object,
}

Object_Init :: proc(class: ^Class_Info = &Object_Class, name: string = "Object") -> Object {
    return Object{
        class    = class,
        name     = name,
        parent   = nil,
        children = nil,
    }
}

Object_Destroy :: proc(self: ^Object) {
    if self == nil {
        return
    }

    for child in self.children {
        Object_Destroy(child)
    }
    delete(self.children)
    self.children = nil

    Set_Parent(self, nil)
}

Get_Class_Name :: proc(self: ^Object) -> string {
    if self == nil || self.class == nil {
        return "Object"
    }

    return self.class.name
}

Get_Name :: proc(self: ^Object) -> string {
    if self == nil {
        return ""
    }

    return self.name
}

Set_Name :: proc(self: ^Object, name: string) {
    if self == nil {
        return
    }

    self.name = name
}

Is_A :: proc(self: ^Object, class_name: string) -> bool {
    if self == nil {
        return false
    }

    class := self.class

    for class != nil {
        if class.name == class_name {
            return true
        }

        class = class.parent
    }

    return false
}

Get_Parent :: proc(self: ^Object) -> ^Object {
    if self == nil {
        return nil
    }

    return self.parent
}

Set_Parent :: proc(self: ^Object, new_parent: ^Object) {
    if self == nil {
        return
    }

    if self.parent != nil {
        for child, i in self.parent.children {
            if child == self {
                ordered_remove(&self.parent.children, i)
                break
            }
        }
    }

    self.parent = new_parent

    if new_parent != nil {
        append(&new_parent.children, self)
    }
}

Get_Children :: proc(self: ^Object) -> []^Object {
    if self == nil {
        return nil
    }

    return self.children[:]
}

Find_First_Child :: proc(self: ^Object, name: string) -> ^Object {
    if self == nil {
        return nil
    }

    for child in self.children {
        if child.name == name {
            return child
        }
    }

    return nil
}

Find_First_Child_Of_Class :: proc(self: ^Object, class_name: string) -> ^Object {
    if self == nil {
        return nil
    }

    for child in self.children {
        if Is_A(child, class_name) {
            return child
        }
    }

    return nil
}

Is_Descendant_Of :: proc(self: ^Object, ancestor: ^Object) -> bool {
    if self == nil || ancestor == nil {
        return false
    }

    current := self.parent
    for current != nil {
        if current == ancestor {
            return true
        }
        current = current.parent
    }

    return false
}

Is_Ancestor_Of :: proc(self: ^Object, descendant: ^Object) -> bool {
    return Is_Descendant_Of(descendant, self)
}

To_String :: proc(self: ^Object) -> string {
    if self == nil {
        return "nil"
    }

    return fmt.tprintf("%s (%s)", self.name, Get_Class_Name(self))
}
