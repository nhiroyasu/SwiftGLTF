# SwiftGLTF
[![Swift](https://github.com/nhiroyasu/SwiftGLTF/actions/workflows/swift.yml/badge.svg)](https://github.com/nhiroyasu/SwiftGLTF/actions/workflows/swift.yml)

A project that enables using glTF files in Swift.

<div>
    <img height="400" alt="preview1" src="https://github.com/user-attachments/assets/c84b561e-7260-4221-8535-b3b894dfe660" />
    <img height="400" alt="preview2" src="https://github.com/user-attachments/assets/ca5b82de-4fc1-4b0e-8a61-dc1c855a1e3b" />
    <img height="400" alt="preview1" src="https://github.com/user-attachments/assets/9bc8de85-b574-431e-ac05-49439461c704" />
</div>

## Features

SwiftGLTF provides a **high-performance, Metal-powered rendering system** specialized for glTF.  
It’s **independent of SceneKit**, supports **a wide range of glTF features**, and is designed as a **lightweight, easy-to-integrate Swift package** for your app.  
By leveraging Metal’s low-level GPU capabilities, SwiftGLTF delivers **fast, efficient, and visually accurate rendering** of glTF models on Apple platforms.

## Usage
### Platform
- iOS 15.0+
- macOS 13.0+
- Metal 3 & 4

### Installation
#### Swift Package Manager
```swift
dependencies: [
    .package(url: "https://github.com/nhiroyasu/SwiftGLTF.git", branch: "main")
]
```

### Sample Code
#### UIKit
```swift
import SwiftGLTF

let gltfUrl = // URL to your glTF or GLB file
let gltfView = GLTFView(frame: view.frame)
await gltfView.load(gltf: gltfUrl)
view.addSubview(gltfView)
```

#### SwiftUI
```swift
import SwiftGLTF

var body: some View {
    @State private var gltfUrl = // URL to your glTF or GLB file
    GLTFSwiftUIView(url: gltfUrl)
}
```

## Supported glTF Features
- Unsupported features are planned to be added in future updates.

### File Formats
| Format              | Supported |
|---------------------|-----------|
| glTF Binary (.glb)  | ✅         |
| glTF JSON (.gltf)   | ✅         |

### Buffer Formats
| Format                              | Supported |
|-------------------------------------|-----------|
| External .bin file                  | ✅         |
| Embedded (data URI in .gltf)        | ✅         |

### Image Formats
| Format     | Supported |
|------------|-----------|
| PNG        | ✅         |
| JPEG       | ✅         |
| KTX2       | ❌         |

### Mesh Compression
| Extension                        | Supported |
|----------------------------------|-----------|
| KHR_draco_mesh_compression       | ❌         |

### PBR Materials (metallic-roughness)
| Property                    | Supported |
|-----------------------------|-----------|
| baseColorFactor             | ✅         |
| baseColorTexture            | ✅         |
| metallicFactor              | ✅         |
| roughnessFactor             | ✅         |
| metallicRoughnessTexture    | ✅         |

### Additional Material Properties
| Property             | Supported |
|----------------------|-----------|
| normalTexture        | ✅         |
| occlusionTexture     | ✅         |
| emissiveTexture      | ✅         |
| emissiveFactor       | ✅         |
| alphaMode            | ✅         |
| alphaCutoff          | ✅         |
| doubleSided          | ✅         |
| extensions           | ✅ (see blow) |

#### Supported Extensions for Materials
- `KHR_materials_transmission`
- `KHR_materials_volume`
- `KHR_materials_ior`
- `KHR_materials_clearcoat`
- `KHR_materials_specular`
- `KHR_materials_sheen`
- `KHR_materials_unlit`
- `KHR_texture_transform`

### Vertex Attributes
| Attribute     | Supported |
|---------------|-----------|
| POSITION      | ✅         |
| NORMAL        | ✅         |
| TANGENT       | ✅         |
| TEXCOORD_0    | ✅         |
| TEXCOORD_1    | ✅         |
| COLOR_0       | ✅         |
| JOINTS_0      | ✅         |
| WEIGHTS_0     | ✅         |

### Node Hierarchy and Transforms
| Feature                                 | Supported |
|-----------------------------------------|-----------|
| Node hierarchy                          | ✅         |
| matrix (4x4 transform matrix)           | ✅         |
| translation / rotation / scale (TRS)    | ✅         |

### Animation
| Channel                  | Supported |
|--------------------------|-----------|
| translation              | ✅         |
| rotation                 | ✅         |
| scale                    | ✅         |
| morph target weights     | ✅         |

### Scenes
| Feature                 | Supported |
|-------------------------|-----------|
| Multiple scenes         | ✅        |

### Cameras
| Feature                 | Supported |
|-------------------------|-----------|
| Perspective             | ✅        |
| Orthographic            | ✅        |

## Build
### Sample Project
- You can build the sample project by opening `SwiftGLTFSample.xcodeproj`.

### Project Structure
#### SwiftGLTF
- Provides `GLTFView` and `GLTFMetalView` components to display glTF files in UIKit and SwiftUI views.

#### SwiftGLTFRenderer
- A library for rendering glTF files using Metal.

#### SwiftGLTFParser
- A library that parses glTF and converts it into `MDLAsset` for use in Swift.

#### SwiftGLTFCore
- A library that defines the core data structures of glTF.

#### MikkTSpace
- Performs normal vector computation for glTF  
- Based on [mmikk/MikkTSpace](https://github.com/mmikk/MikkTSpace)
