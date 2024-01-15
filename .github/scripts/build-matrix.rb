require "json"
require "optparse"

BASE_MATRIX_ENTRIES = [
  {
    "build_os": "ubuntu-18.04",
    "agent_query": "ubuntu-20.04",
    "target": "ubuntu18.04_x86_64",
    "containers": {
      "main": "ghcr.io/swiftwasm/swift-ci:main-ubuntu-18.04",
      "release/5.9": "ghcr.io/swiftwasm/swift-ci:main-ubuntu-18.04@sha256:c996b1fe2babba4e468a6422d9fbe1a9e080e4745c5cb933e4eeaed0a5a95840",
    },
    "run_stdlib_test": true,
    "run_full_test": false,
    "run_e2e_test": true,
    "build_hello_wasm": true,
    "clean_build_dir": false,
    "free_disk_space": true
  },
  {
    "build_os": "ubuntu-20.04",
    "agent_query": "ubuntu-20.04",
    "target": "ubuntu20.04_x86_64",
    "containers": {
      "main": "ghcr.io/swiftwasm/swift-ci:main-ubuntu-20.04",
      "release/5.9": "ghcr.io/swiftwasm/swift-ci:main-ubuntu-20.04@sha256:61d40c32e63abbebb35fa682d78991e0cb9b186f280ba42adec89443905af2f4",
    },
    "run_stdlib_test": true,
    "run_full_test": false,
    "run_e2e_test": true,
    "build_hello_wasm": true,
    "clean_build_dir": false,
    "free_disk_space": true
  },
  {
    "build_os": "ubuntu-22.04",
    "agent_query": "ubuntu-22.04",
    "target": "ubuntu22.04_x86_64",
    "containers": {
      "main": "ghcr.io/swiftwasm/swift-ci:main-ubuntu-22.04",
      "release/5.9": "ghcr.io/swiftwasm/swift-ci:main-ubuntu-22.04@sha256:a55c1ab110d3ef8b1605234245803b5917484990d0b3a00077f9957ae386da97",
    },
    "run_stdlib_test": true,
    "run_full_test": false,
    "run_e2e_test": true,
    "build_hello_wasm": true,
    "clean_build_dir": false,
    "free_disk_space": true
  },
  {
    "build_os": "amazon-linux-2",
    "agent_query": "ubuntu-22.04",
    "target": "amazonlinux2_x86_64",
    "containers": {
      "main": "ghcr.io/swiftwasm/swift-ci:main-amazon-linux-2",
      "release/5.9": "ghcr.io/swiftwasm/swift-ci:main-amazon-linux-2@sha256:5aa7643df1a0d2ea43d86e1dfa603848760deb6efba50349bd00fee9395d0ded",
    },
    "run_stdlib_test": false,
    "run_full_test": false,
    "run_e2e_test": false,
    "build_hello_wasm": true,
    "clean_build_dir": false,
    "free_disk_space": true
  },
  {
    "build_os": "macos-12",
    "agent_query": "macos-12",
    "target": "macos_x86_64",
    "run_stdlib_test": false,
    "run_full_test": false,
    "run_e2e_test": false,
    "build_hello_wasm": false,
    "clean_build_dir": false
  },
  {
    "build_os": "macos-11",
    "agent_query": ["self-hosted", "macOS", "ARM64"],
    "target": "macos_arm64",
    "run_stdlib_test": true,
    "run_full_test": false,
    "run_e2e_test": true,
    "build_hello_wasm": true,
    "clean_build_dir": true
  }
]

def affected_schemes(changes, schemes)
  schemes.select do |scheme|
    prefixes = [
      "schemes/#{scheme}/",
      "tools/build/",
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
    event = JSON.parse(ENV["GITHUB_EVENT_PATH"])
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
          "release/5.9": "ghcr.io/swiftwasm/swift-ci:main-ubuntu-20.04@sha256:61d40c32e63abbebb35fa682d78991e0cb9b186f280ba42adec89443905af2f4",
        },
        "run_stdlib_test": false,
        "run_full_test": false,
        "run_e2e_test": false,
        "build_hello_wasm": true,
        "clean_build_dir": false
      }
    end
  end

  schemes = derive_schemes(options)

  matrix_entries = schemes.flat_map do |scheme|
    if scheme == "main"
      toolchain_channel = "DEVELOPMENT"
    elsif scheme.start_with?("release-")
      toolchain_channel = scheme.sub("release-", "")
    else
      raise "Unknown scheme: #{scheme}"
    end
    matrix_entries.map do |entry|
      container = if containers = entry[:containers]
        containers[scheme.to_sym] || containers[:main]
      end
      entry.merge("scheme": scheme, toolchain_channel: toolchain_channel, container: container)
    end
  end

  print JSON.generate(matrix_entries)
end

if $0 == __FILE__
  main
end
