require "json"
require "optparse"

BASE_MATRIX_ENTRIES = [
  # Generic Swift SDK build
  {
    "job_name": "Swift SDK",
    "build_os": "ubuntu-22.04",
    "agent_query": "ubuntu-22.04",
    "target": "ubuntu22.04_x86_64",
    "containers": {
      "main": "ghcr.io/swiftwasm/swift-ci:main-ubuntu-22.04",
      "release-6.0": "ghcr.io/swiftwasm/swift-ci:main-ubuntu-20.04@sha256:06faf7795ea077b64986b1c821a27b2756242ebe6d73adcdae17f4e424c17dc5",
      "release-6.1": "ghcr.io/swiftwasm/swift-ci:main-ubuntu-20.04@sha256:06faf7795ea077b64986b1c821a27b2756242ebe6d73adcdae17f4e424c17dc5",
      "release-6.2": "ghcr.io/swiftwasm/swift-ci:main-ubuntu-20.04@sha256:ef0e9e4ff5b457103d8a060573050d9b33c91d9f680f7d4202412a99dc52cde0",
      "release-6.3": "ghcr.io/swiftwasm/swift-ci:main-ubuntu-20.04@sha256:ef0e9e4ff5b457103d8a060573050d9b33c91d9f680f7d4202412a99dc52cde0",
    },
    "run_stdlib_test": true,
    "run_full_test": false,
    "run_e2e_test": true,
    "build_hello_wasm": true,
    "clean_build_dir": false,
    "free_disk_space": true,
  },
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
