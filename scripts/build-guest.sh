#!/bin/bash
# Build risc0 guest binary with Docker build cache enabled.
#
# Problem: cargo risczero build generates Dockerfile WITHOUT --mount=type=cache
# despite risc0-build 3.0.5 source code having it (likely docker-generate crate
# strips --mount prefix from RUN args).
#
# Solution: Create a docker wrapper that patches the Dockerfile before running.
set -euo pipefail

cd "$(dirname "$0")/.."
echo "📦 Building risc0 guest in $(pwd)"

# Create docker wrapper
WRAPPER_DIR=$(mktemp -d)
cat > "$WRAPPER_DIR/docker" << 'WRAPPER'
#!/bin/bash
# Docker wrapper that patches risc0 Dockerfiles to add build cache mounts.
REAL_DOCKER=/usr/bin/docker

# Find -f argument (Dockerfile path)
DOCKERFILE=""
ARGS=("$@")
for i in "${!ARGS[@]}"; do
    if [ "${ARGS[$i]}" = "-f" ]; then
        DOCKERFILE="${ARGS[$((i+1))]}"
        break
    fi
done

# Patch Dockerfile if it's a risc0 build (has risc0-guest-builder)
if [ -n "$DOCKERFILE" ] && [ -f "$DOCKERFILE" ] && grep -q "risc0-guest-builder" "$DOCKERFILE"; then
    if ! grep -q "mount=type=cache" "$DOCKERFILE"; then
        echo "🔧 [docker-wrapper] Patching $DOCKERFILE with cache mounts..." >&2
        # Add syntax directive
        sed -i '1i # syntax=docker/dockerfile:1' "$DOCKERFILE"
        # Add cache mounts to RUN lines
        sed -i 's/^RUN cargo/RUN --mount=type=cache,target=\/usr\/local\/cargo\/registry --mount=type=cache,target=\/usr\/local\/cargo\/git\/db cargo/' "$DOCKERFILE"
    fi
fi

exec "$REAL_DOCKER" "$@"
WRAPPER
chmod +x "$WRAPPER_DIR/docker"

# Run build with wrapper in PATH
echo "🚀 Starting build with Docker cache wrapper..."
source ~/.cargo/env
export PATH="$WRAPPER_DIR:$PATH"
export DOCKER_BUILDKIT=1

cargo risczero build -p multisig-guest
EXIT=$?

# Cleanup
rm -rf "$WRAPPER_DIR"

if [ $EXIT -eq 0 ]; then
    echo ""
    echo "✅ Build succeeded!"
    ls -la target/riscv32im-risc0-zkvm-elf/docker/
else
    echo ""
    echo "❌ Build failed with exit code $EXIT"
fi

exit $EXIT
