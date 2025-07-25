# SwiftGLTF
glTFおよびGLBファイルをSwiftで利用できるようにするプロジェクト

![preview1](./Screenshots/preview1.png)
![preview2](./Screenshots/preview2.png)
![preview3](./Screenshots/preview3.png)

## Features
- glTFおよびGLBファイルをデコードし、 `MDLAsset` としてSwiftで扱えるようにする
- MetalによるglTFファイルの高速レンダリング

### 将来的な機能
- glTFのアニメーションをサポート
- glTFの拡張機能をサポート
- カスタマイズ可能なレンダリングパイプライン
- 3Dモデルの編集およびエクスポート機能
- VRMフォーマットのサポート
など

## Usage
### Platform
- iOS 15.0+
- macOS 13.0+

### Install
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
import SwiftGLTFRenderer

// ...

let renderer = try await GLTFRenderer()
let gltfView = GLTFView(frame: view.frame, renderer: renderer)
view.addSubview(gltfView)

let gltfUrl = // glTFまたはGLBファイルのURL
let asset = try makeMDLAsset(from: gltfUrl)
renderer.load(from: asset)
```

#### SwiftUI
```swift
import SwiftGLTF
import SwiftGLTFRenderer

let renderer = try await GLTFRenderer()

// ...

var body: some View {
    GLTFMetalView(renderer: renderer)
        .task {
            let gltfUrl = // glTFまたはGLBファイルのURL
            let asset = try! makeMDLAsset(from: gltfUrl)
            try! renderer.load(from: asset)
        }
}
```

## Supported glTF features
- 非対応の機能は今後のアップデートでサポート予定です

### File formats
| Format              | Supported |
|---------------------|-----------|
| glTF Binary (.glb)  | ✅         |
| glTF JSON (.gltf)   | ✅         |

### Buffer formats
| Format                              | Supported |
|-------------------------------------|-----------|
| External .bin file                  | ✅         |
| Embedded (data URI in .gltf)        | ✅         |

### Image formats
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
| alphaMode            | ❌         |
| alphaCutoff          | ❌         |
| doubleSided          | ❌         |

### Vertex Attributes
| Attribute     | Supported |
|---------------|-----------|
| POSITION      | ✅         |
| NORMAL        | ✅         |
| TANGENT       | ✅         |
| TEXCOORD_0    | ✅         |
| TEXCOORD_1    | ❌         |
| COLOR_0       | ✅         |
| JOINTS_0      | ❌         |
| WEIGHTS_0     | ❌         |

### Node Hierarchy and Transforms
| Feature                                 | Supported |
|-----------------------------------------|-----------|
| Node hierarchy                          | ✅         |
| matrix (4x4 transform matrix)           | ✅         |
| translation / rotation / scale (TRS)    | ✅         |

### Animation
| Channel                  | Supported |
|--------------------------|-----------|
| translation              | ❌         |
| rotation                 | ❌         |
| scale                    | ❌         |
| morph target weights     | ❌         |

### Scenes
| Feature                 | Supported |
|-------------------------|-----------|
| Multiple scenes         | ❌         |

### Cameras
| Feature                 | Supported |
|-------------------------|-----------|
| Camera                  | ❌         |

## Build
### Sample Project
- SwiftGLTFSample.xcodeproj を開くことでサンプルプロジェクトをビルドできます

### Project Structure
#### SwiftGLTFRenderer
- glTFファイルをMetalでレンダリングするためのライブラリ

#### SwiftGLTF
- glTFを解析し、 `MDLAsset` としてSwiftで扱えるようにするライブラリ

#### SwiftGLTFCore
- glTFの基本的なデータ構造を定義するライブラリ

#### MikkTSpace
- glTFの法線計算を行う
- [mmikk/MikkTSpace](https://github.com/mmikk/MikkTSpace) からの流用
