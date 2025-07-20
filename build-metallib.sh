#!/bin/bash
set -e

SDK="$1"

echo "📦 Building for $SDK"

SRC_DIR="Sources/SwiftGLTFRenderer/Shader"
OUT_DIR="Sources/SwiftGLTFRenderer/Shader/lib"
LIB_PATH="${OUT_DIR}/SwiftGLTFRenderer.${SDK}.metallib"

mkdir -p "$OUT_DIR"

AIR_FILES=()
for metal_file in "$SRC_DIR"/*.metal; do
    air_file="${metal_file%.metal}.${SDK}.air"
    xcrun -sdk "$SDK" metal -c "$metal_file" -o "$air_file"
    AIR_FILES+=("$air_file")
done

xcrun -sdk "$SDK" metallib "${AIR_FILES[@]}" -o "$LIB_PATH"

rm "${AIR_FILES[@]}"
echo "✅ Created: $LIB_PATH"