// RUN: rm -rf %t.dir
// RUN: mkdir -p %t.dir
// RUN: %{swift} package init --package-path %t.dir --name Example
// RUN: cp %S/Inputs/imports.swift %t.dir/Sources/Example/Imports.swift
// RUN: %{target_swift_build} --package-path %t.dir
// XFAIL: scheme=main
