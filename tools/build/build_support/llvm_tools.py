WASM_SPECIFIC_TOOLS_TO_INSTALL = [
    'wasm-ld',
    'llvm-ar',
    'llvm-ranlib',
]

WASM_SPECIFIC_TOOLS = WASM_SPECIFIC_TOOLS_TO_INSTALL + [
    # These tools are used by Swift test suite
    'llvm-nm',
    'FileCheck',
]