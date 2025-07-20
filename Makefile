SCRIPT := ./build-metallib.sh
SRC_DIR := Sources/SwiftGLTFRenderer/Shader
OUT_DIR := Sources/SwiftGLTFRenderer/Shader/lib
PLATFORMS := macosx iphoneos iphonesimulator xros

# Use wildcard to find all .metal files in the source directory
METAL_SRCS := $(wildcard $(SRC_DIR)/*.metal)

# Define output paths for each platform's metallib
METALLIBS := $(foreach sdk, $(PLATFORMS), $(OUT_DIR)/SwiftGLTFRenderer.$(sdk).metallib)

.PHONY: all
all: $(METALLIBS)

# en: Generate metallib for each platform
$(OUT_DIR)/SwiftGLTFRenderer.%.metallib: $(METAL_SRCS) $(SCRIPT)
	sh $(SCRIPT) $*

# Generate metallib for each specified platform
.PHONY: $(PLATFORMS)
$(PLATFORMS):
	$(MAKE) $(OUT_DIR)/SwiftGLTFRenderer.$@.metallib

.PHONY: clean
clean:
	rm -f $(OUT_DIR)/*.air
	rm -f $(OUT_DIR)/*.metallib
