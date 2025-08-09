import ModelIO

public extension MDLMaterial {
    func propertyNamed(_ materialPropertyName: MaterialPropertyName) -> MDLMaterialProperty? {
        return propertyNamed(materialPropertyName.rawValue)
    }
}
