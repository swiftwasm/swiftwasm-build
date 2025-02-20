require "json"
require "optparse"

BASE_MATRIX_ENTRIES = [
  {
    "build_os": "ubuntu-20.04",
    "agent_query": "ubuntu-20.04",
    "target": "ubuntu20.04_x86_64",
    "containers": {
      "main": "ghcr.io/swiftwasm/swift-ci:main-ubuntu-20.04",
      "release-6.0": "ghcr.io/swiftwasm/swift-ci:main-ubuntu-20.04@sha256:9007661fb6d57ebef902618e831458e88068350b0ecc8d85e56441d25a9f4312",
      "release-6.1": "ghcr.io/swiftwasm/swift-ci:main-ubuntu-20.04@sha256:9007661fb6d57ebef902618e831458e88068350b0ecc8d85e56441d25a9f4312",
    },
    "run_stdlib_test": true,
    "run_full_test": false,
    "run_e2e_test": true,
    "build_hello_wasm": true,
    "clean_build_dir": false,
    "free_disk_space": true,
    "only_swift_sdk": false,
  },
  {
    "build_os": "ubuntu-22.04",
    "agent_query": "ubuntu-22.04",
    "target": "ubuntu22.04_x86_64",
    "containers": {
      "main": "ghcr.io/swiftwasm/swift-ci:main-ubuntu-22.04",
      "release-6.0": "ghcr.io/swiftwasm/swift-ci:main-ubuntu-20.04@sha256:8060adba9c044b1fc751b9671167320c9cc0094d0a45d7b8fedb707c49b764c2",
      "release-6.1": "ghcr.io/swiftwasm/swift-ci:main-ubuntu-20.04@sha256:8060adba9c044b1fc751b9671167320c9cc0094d0a45d7b8fedb707c49b764c2",
    },
    "run_stdlib_test": true,
    "run_full_test": false,
    "run_e2e_test": true,
    "build_hello_wasm": true,
    "clean_build_dir": false,
    "free_disk_space": true,
    "only_swift_sdk": false,
  },
  {
    "build_os": "amazon-linux-2",
    "agent_query": "ubuntu-22.04",
    "target": "amazonlinux2_x86_64",
    "containers": {
      "main": "ghcr.io/swiftwasm/swift-ci:main-amazon-linux-2",
      "release-6.0": "ghcr.io/swiftwasm/swift-ci:main-amazon-linux-2@sha256:fc95912c595faecacbb869635fa871f8f31b8d6ed2f0df6792b53628db7ada94",
      "release-6.1": "ghcr.io/swiftwasm/swift-ci:main-amazon-linux-2@sha256:fc95912c595faecacbb869635fa871f8f31b8d6ed2f0df6792b53628db7ada94",
    },
    "run_stdlib_test": false,
    "run_full_test": false,
    "run_e2e_test": false,
    "build_hello_wasm": true,
    "clean_build_dir": false,
    "free_disk_space": true,
    "only_swift_sdk": false,
  },
  {
    "build_os": "macos-13",
    "agent_query": "macos-13",
    "schemes": ["release-6.0", "release-6.1", "main"],
    "target": "macos_x86_64",
    "run_stdlib_test": false,
    "run_full_test": false,
    "run_e2e_test": false,
    "build_hello_wasm": false,
    "clean_build_dir": false,
    "only_swift_sdk": false,
  },
  {
    "build_os": "macos-14",
    "agent_query": "macos-14",
    "schemes": ["release-6.0", "release-6.1", "main"],
    "target": "macos_arm64",
    "run_stdlib_test": true,
    "run_full_test": false,
    "run_e2e_test": true,
    "build_hello_wasm": true,
    "clean_build_dir": true,
    "free_disk_space": true,
    "only_swift_sdk": false,
  },
  # Generic Swift SDK build
  {
    "job_name": "Swift SDK",
    "build_os": "ubuntu-22.04",
    "agent_query": "ubuntu-22.04",
    "target": "ubuntu22.04_x86_64",
    "containers": {
      "main": "ghcr.io/swiftwasm/swift-ci:main-ubuntu-22.04",
      "release-6.0": "ghcr.io/swiftwasm/swift-ci:main-ubuntu-20.04@sha256:8060adba9c044b1fc751b9671167320c9cc0094d0a45d7b8fedb707c49b764c2",
      "release-6.1": "ghcr.io/swiftwasm/swift-ci:main-ubuntu-20.04@sha256:8060adba9c044b1fc751b9671167320c9cc0094d0a45d7b8fedb707c49b764c2",
    },
    "run_stdlib_test": true,
    "run_full_test": false,
    "run_e2e_test": true,
    "build_hello_wasm": true,
    "clean_build_dir": false,
    "free_disk_space": true,
    "only_swift_sdk": true,
  },
]

def affected_schemes(changes, schemes)
  schemes.select do |scheme|
    prefixes = [
      "schemes/#{scheme}/",
      "tools/build/",
      "tools/swift-sdk-generator",
      "tools/git-swift-workspace",
    ]
    changes.any? do |change|
      prefixes.any? { |prefix| change.start_with?(prefix) }
    end
  end
end

def derive_schemes(options)
  schemes_dir = File.expand_path("../../../schemes", __FILE__)
  schemes = Dir.glob("#{schemes_dir}/*/manifest.json").map do |path|
    File.basename(File.dirname(path))
  end

  if ENV["GITHUB_EVENT_NAME"] == "workflow_dispatch"
    event = JSON.parse(File.read(ENV["GITHUB_EVENT_PATH"]))
    inputs = event["inputs"]
    if inputs && inputs["scheme"]
      schemes = [inputs["scheme"]]
      return schemes
    end
  end

  if options[:changes]
    schemes = affected_schemes(JSON.parse(File.read(options[:changes])), schemes)
  end
  schemes
end

def main
  options = {}
  OptionParser.new do |opts|
    opts.banner = "Usage: build-matrix.rb [options]"
    opts.on("--runner [JSON FILE]", "Path to runner data file") do |v|
      options[:runner] = v
    end
    opts.on("--changes [JSON FILE]", "Path to list of changed files") do |v|
      options[:changes] = v
    end
  end.parse!

  matrix_entries = BASE_MATRIX_ENTRIES.dup
  if options[:runner]
    runner = JSON.parse(File.read(options[:runner]))
    if label = runner["outputs"]["ubuntu20_04_aarch64-label"]
      matrix_entries << {
        "build_os": "ubuntu-20.04",
        "agent_query": label,
        "target": "ubuntu20.04_aarch64",
        "containers": {
          "main": "ghcr.io/swiftwasm/swift-ci:main-ubuntu-20.04",
          "release-6.0": "ghcr.io/swiftwasm/swift-ci:main-ubuntu-20.04@sha256:2a977060476a0f6f702d59ed0cd4e8506c7c1f1ed48d85a1a684d2d3fb62c297",
          "release-6.1": "ghcr.io/swiftwasm/swift-ci:main-ubuntu-20.04@sha256:2a977060476a0f6f702d59ed0cd4e8506c7c1f1ed48d85a1a684d2d3fb62c297",
        },
        "run_stdlib_test": false,
        "run_full_test": false,
        "run_e2e_test": false,
        "build_hello_wasm": true,
        "clean_build_dir": false,
        "free_disk_space": false,
        "only_swift_sdk": false,
      }
    end
  end

  schemes = derive_schemes(options)
  schemes = schemes

  matrix_entries = schemes.flat_map do |scheme|
    if scheme == "main"
      toolchain_channel = "DEVELOPMENT"
    elsif scheme.start_with?("release-")
      toolchain_channel = scheme.sub("release-", "")
    else
      raise "Unknown scheme: #{scheme}"
    end
    matrix_entries.filter_map do |entry|
      if entry[:schemes]
        next nil unless entry[:schemes].include?(scheme)
      end
      container = if containers = entry[:containers]
        found = containers[scheme.to_sym]
        next nil unless found # Skip if container for the scheme is not specified
        found
      end
      if entry[:job_name]
        job_name = "#{entry[:job_name]} (#{scheme})"
      else
        job_name = "Target #{scheme}/#{entry[:target]}"
      end
      entry.merge(
        "scheme": scheme, toolchain_channel: toolchain_channel, container: container,
        job_name: job_name,
      )
    end
  end

  print JSON.generate(matrix_entries)
end

if $0 == __FILE__
  main
end
