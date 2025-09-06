import ModelIO

extension MDLObject {
    var root: MDLObject {
        var current: MDLObject = self
        while let parent = current.parent {
            current = parent
        }
        return current
    }

    // ex: ancestor → ... → parent → self
    var parentTreeWithSelf: [MDLObject] {
        var parents: [MDLObject] = [self]
        var current: MDLObject? = self.parent
        while let parent = current {
            parents.insert(parent, at: 0)
            current = parent.parent
        }
        return parents
    }

    func isChild(of ancestor: MDLObject) -> Bool {
        var current: MDLObject? = self
        while let parent = current?.parent {
            if parent === ancestor {
                return true
            }
            current = parent
        }
        return false
    }

    func component<T: MDLComponent>(ofType type: T.Type) -> T? {
        return self.components.first(where: { $0 is T }) as? T
    }
}
