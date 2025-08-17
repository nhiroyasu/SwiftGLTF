import ModelIO

extension MDLObject {
    var root: MDLObject {
        var current: MDLObject = self
        while let parent = current.parent {
            current = parent
        }
        return current
    }
}
