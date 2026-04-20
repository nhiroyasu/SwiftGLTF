# SwiftGLTF
glTFおよびGLBファイルをSwiftで利用できるようにするプロジェクト

<div>
    <img height="400" alt="preview1" src="https://github.com/user-attachments/assets/c84b561e-7260-4221-8535-b3b894dfe660" />
    <img height="200" alt="preview1" src="https://github.com/user-attachments/assets/9bc8de85-b574-431e-ac05-49439461c704" />
    <img height="200" alt="preview2" src="https://github.com/user-attachments/assets/bb2c9ec4-66b3-4c34-baa7-ae36f04624d1" />
</div>

## 機能
SwiftGLTFは以下の機能を提供します：
- **Metalによる完全なサポートによる高性能レンダリング**
- **軽量かつモジュール式の設計**で、あらゆるSwiftプロジェクトへの統合が容易
- **広範なglTF仕様のサポート**（マテリアル、アニメーション、カメラなどを含む）
- **最適化されたGPUリソース管理**により、Appleプラットフォーム上で高速かつ効率的なレンダリングを実現

## パフォーマンス
SwiftGLTFはglTFサンプルアセットの公式モデル**NodePerformanceTest**を用いてテストされ、以下のパフォーマンス結果を示しました。このモデルには以下が含まれます：
- **10,000個のノード**
- **10,000個のメッシュ/プリミティブ/マテリアル**
- ランダム使用の**100テクスチャ**

極めて高いノード数とマテリアル数にもかかわらず、SwiftGLTFは以下の性能を発揮します：

- 対応Appleプラットフォーム上で**レンダリング中も安定した60 FPSを維持**

**MacBookPro (M1 Pro)**

https://github.com/user-attachments/assets/07112f37-ad10-40d4-b14a-dbed75b3cd17

**iPhone16 (A18)**

https://github.com/user-attachments/assets/0cba90bc-c30a-467b-bbeb-3e26714e4960

## Usage
### Platform
- iOS 16.0+
- macOS 13.0+
- Metal 3 & 4

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
| extensions           | ✅ (以下を参照)  |

#### Supported Extensions for Materials
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

## Build
### Sample Project
- SwiftGLTFSample.xcodeproj を開くことでサンプルプロジェクトをビルドできます

### Project Structure
#### SwiftGLTF
- glTFファイルをViewに表示する機能を提供するライブラリ（UIKitの`GLTFView`およびSwiftUIの`GLTFMetalView`を含む）

#### SwiftGLTFRenderer
- glTFファイルをMetalでレンダリングするためのライブラリ

#### SwiftGLTFParser
- glTFを解析し、 `MDLAsset` としてSwiftで扱えるようにするライブラリ

#### SwiftGLTFCore
- glTFの基本的なデータ構造を定義するライブラリ

#### MikkTSpace
- glTFの法線計算を行う
- [mmikk/MikkTSpace](https://github.com/mmikk/MikkTSpace) からの流用
