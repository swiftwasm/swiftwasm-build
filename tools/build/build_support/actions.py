import os
import sys
import pathlib
import subprocess
import argparse


REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(__file__))))

class Action:
    def __init__(self, options):
        self.options = options

    def run(self):
        raise Exception('Not implemented')

    def system(self, *args):
        if self.options.verbose or self.options.dry_run:
            print(' '.join(args), file=sys.stderr)
        if self.options.dry_run:
            return
        result = subprocess.run(args)
        if result.returncode != 0:
            raise Exception('Command failed: {}'.format(' '.join(args)))

class CloneAction(Action):
    def run(self):
        if os.path.exists("../swift/.git"):
            return
        print('=====> Cloning Swift repository')
        git_options = []
        if self.options.skip_history:
            git_options += ['--depth', '1', '--branch', self.options.tag]

        args = ['git', 'clone'] + git_options + ['https://github.com/apple/swift.git', '../swift']
        self.system(*args)

class UpdateCheckoutAction(Action):
    def run(self):
        print('=====> Updating checkout for scheme {} with tag {}'.format(self.options.scheme, self.options.tag))
        args = ['../swift/utils/update-checkout', '--clone', '--scheme', self.options.scheme, '--tag', self.options.tag]
        if self.options.skip_history:
            args += ['--skip-history']
        self.system(*args)

class ApplyPatchesAction(Action):
    def run(self):
        patches_dir = os.path.join('schemes', self.options.scheme, 'swift')
        patches = [os.path.join(patches_dir, path) for path in os.listdir(patches_dir)]
        patches.sort()
        print('=====> Applying {} patches for scheme {}'.format(len(patches), self.options.scheme))

        # If the repository is not clean, abort
        status = subprocess.run(['git', '-C', '../swift', 'status', '--porcelain']).returncode
        if status != 0:
            raise Exception('Repository is not clean. Please commit or stash your changes.')

        staging_branch = self.compute_unique_branch_name('swiftwasm-staging/{}'.format(self.options.tag))
        self.system('git', '-C', '../swift', 'switch', '-c', staging_branch)
        for patch in patches:
            repo_root_dirname = pathlib.Path(".").resolve().name
            relative_path = os.path.join("..", repo_root_dirname, patch)
            self.system('git', '-C', '../swift', 'am', '--keep-non-patch', str(relative_path))

    def compute_unique_branch_name(self, basename):
        name = basename
        suffix = 0
        while True:
            result = subprocess.run(['git', '-C', '../swift', 'branch', '--list', name], stdout=subprocess.PIPE)
            if len(result.stdout) == 0:
                return name
            suffix += 1
            name = '{}-{}'.format(basename, suffix)

class CheckoutCorelibsAction(Action):
    def run(self):
        print('=====> Checking out swift-corelibs for scheme {}'.format(self.options.scheme))
        for repo, rev in self.options.repos.items():
            fork_repo = f'https://github.com/swiftwasm/{repo}.git'
            status = subprocess.run(['git', '-C', f'../{repo}', 'remote', 'get-url', 'swiftwasm']).returncode
            if status != 0:
                self.system('git', '-C', f'../{repo}', 'remote', 'add', 'swiftwasm', fork_repo)
            print(f'Checking out {repo} at {rev}')
            self.system('git', '-C', f'../{repo}', 'fetch', 'swiftwasm', rev)
            self.system('git', '-C', f'../{repo}', 'checkout', rev)

class DownloadBaseSnapshotAction(Action):
    def run(self):
        base_tag = self.options.tag
        platform = self.platform_info()
        extension = platform[2]
        tarball_name = f"{base_tag}-{platform[1]}.{extension}"
        snapshot_url = f"https://download.swift.org/{self.options.swift_org_download_channel}/{platform[0]}/{base_tag}/{tarball_name}"

        tarball_path = os.path.join('..', 'build', 'Packaging', f'base-snapshot.{extension}')
        if not os.path.exists(tarball_path):
            print(f"=====> Downloading base snapshot {tarball_name}")
            os.makedirs(os.path.dirname(tarball_path), exist_ok=True)
            self.system('curl', '-L', '-o', tarball_path, snapshot_url)

        base_snapshot_dir = os.path.join('..', 'build', 'Packaging', 'base-snapshot')

        if not os.path.exists(os.path.join(base_snapshot_dir, 'usr')):
            print(f"=====> Unpacking base snapshot {tarball_name}")
            os.makedirs(base_snapshot_dir, exist_ok=True)
            if extension == "tar.gz":
                self.system('tar', '-C', base_snapshot_dir, '--strip-components', '1', '-xzf', tarball_path)
            elif extension == "pkg":
                import tempfile
                with tempfile.TemporaryDirectory() as tmpdir:
                    self.system('xar', '-xf', tarball_path, '-C', tmpdir)
                    old_cwd = os.getcwd()
                    os.chdir(base_snapshot_dir)
                    pkg_name = tarball_name.replace(".pkg", "-package.pkg")
                    self.system('cpio', '-i', '-I', os.path.join(tmpdir, pkg_name, 'Payload'))
                    os.chdir(old_cwd)

    def platform_info(self):
        uname = os.uname()
        if uname.sysname == "Darwin":
            # https://download.swift.org/development/xcode/swift-DEVELOPMENT-SNAPSHOT-2023-06-17-a/swift-DEVELOPMENT-SNAPSHOT-2023-06-17-a-osx.pkg
            return ["xcode", "osx", "pkg"]
        elif uname.sysname == "Linux":
            release_lines = open("/etc/os-release").read().splitlines()
            if "ID=ubuntu" in release_lines:
                # https://download.swift.org/development/ubuntu2004/swift-DEVELOPMENT-SNAPSHOT-2023-06-17-a/swift-DEVELOPMENT-SNAPSHOT-2023-06-17-a-ubuntu20.04.tar.gz
                # https://download.swift.org/development/ubuntu2004-aarch64/swift-DEVELOPMENT-SNAPSHOT-2023-06-17-a/swift-DEVELOPMENT-SNAPSHOT-2023-06-17-a-ubuntu20.04-aarch64.tar.gz
                arch_suffix = f"-{uname.machine}" if uname.machine != "x86_64" else ""
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
                return [info[0] + arch_suffix, info[1] + arch_suffix, "tar.gz"]
            elif "ID=amzn" in release_lines:
                # https://download.swift.org/development/amazonlinux2/swift-DEVELOPMENT-SNAPSHOT-2023-06-17-a/swift-DEVELOPMENT-SNAPSHOT-2023-06-17-a-amazonlinux2.tar.gz
                if 'VERSION_ID="2"' in release_lines:
                    return ["amazonlinux2", "amazonlinux2", "tar.gz"]
                raise Exception("Unsupported AmazonLinux version!?")
            raise Exception("Unsupported Linux distribution")


class ActionRunner:
    def __init__(self, actions):
        self.actions = actions

    def run(self):
        os.chdir(REPO_ROOT)
        for action in self.actions:
            action.run()

def derive_options_from_args(argv, parser: argparse.ArgumentParser):
    schemes = [os.path.basename(path) for path in os.listdir(os.path.join(REPO_ROOT, 'schemes'))]

    parser.add_argument('--scheme', help='The scheme to use', required=True, choices=schemes)
    parser.add_argument('--tag', help='The upstream Swift tag to use as the base')
    parser.add_argument('--dry-run', help='Prints the commands that would be executed', action='store_true')
    parser.add_argument('-v', '--verbose', help='Prints the commands that are executed', action='store_true')
    parser.add_argument('--skip-history', help='Skip histories when obtaining sources', action='store_true')

    options = parser.parse_args(argv)

    import json
    manifest = json.load(open(os.path.join(REPO_ROOT, 'schemes', options.scheme, 'manifest.json')))

    if options.tag is None:
        options.tag = manifest['base-tag']
        if options.tag is None:
            raise Exception('Missing --tag option and no default tag for scheme {}'.format(options.scheme))

    options.repos = manifest['repos'] or {}
    options.swift_org_download_channel = manifest['swift-org-download-channel']
    return options
