import os
from dataclasses import dataclass
from typing import Optional

@dataclass
class PlatformInfo:
    name: str
    full_name: str
    package_extension: str
    arch: str

    def derive():
        uname = os.uname()
        if uname.sysname == "Darwin":
            # https://download.swift.org/development/xcode/swift-DEVELOPMENT-SNAPSHOT-2023-06-17-a/swift-DEVELOPMENT-SNAPSHOT-2023-06-17-a-osx.pkg
            return PlatformInfo("xcode", "osx", "pkg", uname.machine)
        elif uname.sysname == "Linux":
            release_lines = open("/etc/os-release").read().splitlines()
            if "ID=ubuntu" in release_lines:
                # https://download.swift.org/development/ubuntu2004/swift-DEVELOPMENT-SNAPSHOT-2023-06-17-a/swift-DEVELOPMENT-SNAPSHOT-2023-06-17-a-ubuntu20.04.tar.gz
                # https://download.swift.org/development/ubuntu2004-aarch64/swift-DEVELOPMENT-SNAPSHOT-2023-06-17-a/swift-DEVELOPMENT-SNAPSHOT-2023-06-17-a-ubuntu20.04-aarch64.tar.gz
                if 'VERSION_ID="18.04"' in release_lines:
                    info = ["ubuntu1804", "ubuntu18.04"]
                elif 'VERSION_ID="20.04"' in release_lines:
                    info = ["ubuntu2004", "ubuntu20.04"]
                elif 'VERSION_ID="22.04"' in release_lines:
                    info = ["ubuntu2204", "ubuntu22.04"]
                elif 'VERSION_ID="22.04"' in release_lines:
                    info = ["ubuntu2204", "ubuntu22.04"]
                else:
                    raise Exception("Unsupported Ubuntu version!?")
                return PlatformInfo(info[0], info[1], "tar.gz", uname.machine)
            elif "ID=amzn" in release_lines:
                # https://download.swift.org/development/amazonlinux2/swift-DEVELOPMENT-SNAPSHOT-2023-06-17-a/swift-DEVELOPMENT-SNAPSHOT-2023-06-17-a-amazonlinux2.tar.gz
                if 'VERSION_ID="2"' in release_lines:
                    return PlatformInfo("amazonlinux2", "amazonlinux2", "tar.gz", uname.machine)
                raise Exception("Unsupported AmazonLinux version!?")
            raise Exception("Unsupported Linux distribution")

    def snapshot_url(self, channel: str, tag: str) -> str:
        arch_suffix = f"-{self.arch}" if self.arch != "x86_64" else ""
        tarball_name = f"{tag}-{self.full_name + arch_suffix}.{self.package_extension}"
        return [f"https://download.swift.org/{channel}/{self.name + arch_suffix}/{tag}/{tarball_name}", tarball_name]
