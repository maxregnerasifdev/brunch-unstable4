#!/bin/bash

# Determine the number of threads
if [ ! -d /home/runner/work ]; then
    NTHREADS=$(nproc)
else
    NTHREADS=$(( $(nproc) * 4 ))
fi

# If no kernel specified, get a list of all kernels
if [ -z "$1" ]; then
    kernels=$(ls -d ./kernels/* | sed 's#./kernels/##g')
else
    kernels="$1"
fi

# Function to build the kernel
build_kernel() {
    local kernel=$1
    echo "Building kernel $kernel"
    KCONFIG_NOTIMESTAMP=1 KBUILD_BUILD_TIMESTAMP='' KBUILD_BUILD_USER=chronos KBUILD_BUILD_HOST=localhost \
    make -C "./kernels/$kernel" -j"$NTHREADS" O=out || { echo "Kernel build failed for $kernel"; exit 1; }
}

# Function to sign the kernel
sign_kernel() {
    local kernel=$1
    echo "Signing kernel $kernel"
    mv "./kernels/$kernel/out/arch/x86/boot/bzImage" "./kernels/$kernel/out/arch/x86/boot/bzImage.unsigned" || { echo "Kernel signing failed for $kernel"; exit 1; }
    sbsign --key /persist/keys/brunch.priv --cert /persist/keys/brunch.pem \
    "./kernels/$kernel/out/arch/x86/boot/bzImage.unsigned" --output "./kernels/$kernel/out/arch/x86/boot/bzImage" || { echo "Kernel signing failed for $kernel"; exit 1; }
}

# Function to include kernel headers
include_kernel_headers() {
    local kernel=$1
    echo "Including kernel $kernel headers"
    srctree="./kernels/$kernel"
    objtree="./kernels/$kernel/out"
    SRCARCH="x86"
    KCONFIG_CONFIG="$objtree/.config"
    destdir="$srctree/headers"
    mkdir -p "${destdir}"
    
    (
        cd "${srctree}"
        echo Makefile
        find "arch/${SRCARCH}" -maxdepth 1 -name 'Makefile*'
        find include scripts -type f -o -type l
        find "arch/${SRCARCH}" -name Kbuild.platforms -o -name Platform
        find "arch/${SRCARCH}" -name include -o -name scripts -type d
    ) | tar -c -f - -C "${srctree}" -T - | tar -xf - -C "${destdir}"
    
    (
        cd "${objtree}"
        if grep -q "^CONFIG_OBJTOOL=y" include/config/auto.conf; then
            echo tools/objtool/objtool
        fi
        find "arch/${SRCARCH}/include" Module.symvers include scripts -type f
        if grep -q "^CONFIG_GCC_PLUGINS=y" include/config/auto.conf; then
            find scripts/gcc-plugins -name '*.so'
        fi
    ) | tar -c -f - -C "${objtree}" -T - | tar -xf - -C "${destdir}"
    
    cp "${KCONFIG_CONFIG}" "${destdir}/.config"
}

# Main loop to process each kernel
for kernel in $kernels; do
    build_kernel "$kernel"
    
    if [ -f /persist/keys/brunch.priv ] && [ -f /persist/keys/brunch.pem ]; then
        sign_kernel "$kernel"
    fi
    
    include_kernel_headers "$kernel"
done
