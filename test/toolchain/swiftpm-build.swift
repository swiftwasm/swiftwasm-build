// RUN: rm -rf %t.dir
// RUN: mkdir -p %t.dir
// RUN: %{swift} package init --package-path %t.dir --name Example
// RUN: cp %S/Inputs/imports.swift %t.dir/Sources/Example/Imports.swift
// RUN: %{swift} build --package-path %t.dir --triple wasm32-unknown-wasi -Xswiftc -static-stdlib -Xswiftc -resource-dir -Xswiftc %{package_path}/usr/lib/swift_static
