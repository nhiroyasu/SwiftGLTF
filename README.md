# SwiftGLTF
[![Swift](https://github.com/nhiroyasu/SwiftGLTF/actions/workflows/swift.yml/badge.svg)](https://github.com/nhiroyasu/SwiftGLTF/actions/workflows/swift.yml)

A project that enables using glTF files in Swift.

<div>
    <img height="400" alt="preview1" src="https://github.com/user-attachments/assets/c84b561e-7260-4221-8535-b3b894dfe660" />
    <img height="400" alt="preview2" src="https://github.com/user-attachments/assets/ca5b82de-4fc1-4b0e-8a61-dc1c855a1e3b" />
    <img height="400" alt="preview1" src="https://github.com/user-attachments/assets/9bc8de85-b574-431e-ac05-49439461c704" />
</div>

## Features

SwiftGLTF offers:

- **High-performance rendering** fully powered by Metal
- **Lightweight and modular design**, easy to integrate into any Swift project
- **Wide glTF specification support**, covering materials, animations, cameras, and more
- **Optimized GPU resource management**, enabling fast and efficient rendering on Apple platforms

## Performance

SwiftGLTF has been tested using the official **NodePerformanceTest** model from the glTF Sample Assets, demonstrating the following performance results: This model contains:

- **10,000 nodes**
- **10,000 meshes / primitives / materials**
- **100 textures** with randomized usage

Despite the extremely high node and material count, SwiftGLTF is capable of:

- **Maintaining a stable 60 FPS during rendering** on supported Apple platforms

**MacBookPro (M1 Pro)**

https://github.com/user-attachments/assets/07112f37-ad10-40d4-b14a-dbed75b3cd17

**iPhone16 (A18)**

https://github.com/user-attachments/assets/0cba90bc-c30a-467b-bbeb-3e26714e4960




## Usage
### Platform
- iOS 16.0+
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
| WebP       | ✅         |
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
- `KHR_materials_emissive_strength`
- `KHR_materials_transmission`
- `KHR_materials_volume`
- `KHR_materials_ior`
- `KHR_materials_clearcoat`
- `KHR_materials_specular`
- `KHR_materials_sheen`
- `KHR_materials_unlit`
- `KHR_materials_variants`
- `KHR_texture_transform`
- `EXT_texture_webp`

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

## VRM Support
- VRM support is currently under development.
- Current support focuses on decoding VRM extension data and using humanoid bone mappings during rendering.
- VRM 1.0 features are based on the [VRMC_vrm 1.0 specification](https://github.com/vrm-c/vrm-specification/blob/master/specification/VRMC_vrm-1.0/README.md).

### Supported VRM Features
| VRM Feature | Supported | Notes |
|-------------|-----------|-------|
| `.vrm` file loading | ✅ | Loaded through the existing GLB/glTF pipeline |
| `VRMC_vrm.meta` | ✅ | Model information and license metadata decoding |
| `VRMC_vrm.humanoid` | ✅ | Humanoid bone decoding and node mapping |
| Humanoid bone transforms | ✅ | Runtime rotations can be applied through `vrmHumanoidRotations` |
| `VRMC_vrm.firstPerson` | ⚠️ Decoding only | First-person rendering behavior is in progress |
| `VRMC_vrm.expressions` | ⚠️ Decoding only | Runtime expression application is in progress |
| `VRMC_vrm.lookAt` | ⚠️ Decoding only | Runtime eye control is in progress |
| `KHR_materials_unlit` / `KHR_texture_transform` / `KHR_materials_emissive_strength` | ✅ | Supported as glTF material extensions |
| `VRMC_materials_mtoon` | ❌ | MToon-specific shading is not yet supported |
| `VRMC_springBone` | ❌ | Spring bone decoding and simulation are not yet supported |
| `VRMC_node_constraint` | ❌ | Node constraint decoding and evaluation are not yet supported |

### Supported VRM Versions
| VRM Version | Extension | Supported | Notes |
|-------------|-----------|-----------|-------|
| VRM 0.x | `VRM` | ⚠️ Partial | Extension data decoding and humanoid node mapping are supported |
| VRM 1.0 | `VRMC_vrm` | ⚠️ Partial | Core extension data decoding and humanoid node mapping are supported |
| Future VRM versions | - | ❌ | Not supported |

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
