import os
import sys
import pathlib
import subprocess
import argparse
from . import platform


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
    def __init__(self, options, repo: str, branch: str):
        super().__init__(options)
        self.repo = repo
        self.repo_basename = repo.split('/')[-1]
        self.branch = branch

    def run(self):
        repo_dir = os.path.join('..', self.repo_basename)
        if os.path.exists(os.path.join(repo_dir, '.git')):
            return
        print('=====> Cloning Swift repository')
        git_options = []
        if self.options.skip_history:
            git_options += ['--depth', '1', '--branch', self.branch]

        args = ['git', 'clone'] + git_options + [f'https://github.com/{self.repo}.git', repo_dir]
        self.system(*args)
        print('=====> Checking out Swift tag {}'.format(self.branch))
        self.system('git', '-C', repo_dir, 'checkout', self.branch)

class UpdateCheckoutAction(Action):
    def run(self):
        print('=====> Updating checkout for scheme {} with tag {}'.format(self.options.update_checkout_scheme, self.options.tag))
        args = ['../swift/utils/update-checkout', '--clone',
                '--scheme', self.options.update_checkout_scheme,
                '--tag', self.options.tag]
        if self.options.skip_history:
            args += ['--skip-history']
        args += self.options.extra_update_checkout_args
        self.system(*args)

class ApplyPatchesAction(Action):

    def __init__(self, options, repo: str):
        super().__init__(options)
        self.repo = repo
        self.repo_dir = f'../{repo}'

    def run(self):
        patches_dir = os.path.join('schemes', self.options.scheme, self.repo)
        if not os.path.exists(patches_dir):
            print("=====> No patches for scheme {} for repo {}".format(self.options.scheme, self.repo))
            return

        patches = [os.path.join(patches_dir, path) for path in os.listdir(patches_dir)]
        patches.sort()
        print('=====> Applying {} patches for scheme {}'.format(len(patches), self.options.scheme))

        # If the repository is not clean, abort
        status = subprocess.run(['git', '-C', self.repo_dir, 'status', '--porcelain']).returncode
        if status != 0:
            raise Exception('Repository is not clean. Please commit or stash your changes.')

        # Reset "am" state
        try:
            self.system('git', '-C', self.repo_dir, 'am', '--abort')
        except Exception:
            pass  # Ignore errors if there's no "am" in progress

        staging_branch = self.compute_unique_branch_name('swiftwasm-staging/{}'.format(self.options.tag))
        self.system('git', '-C', self.repo_dir, 'switch', '-c', staging_branch)
        for patch in patches:
            repo_root_dirname = pathlib.Path(".").resolve().name
            relative_path = os.path.join("..", repo_root_dirname, patch)
            self.system('git', '-C', self.repo_dir, 'am', '--keep-non-patch', str(relative_path))

    def compute_unique_branch_name(self, basename):
        name = basename
        suffix = 0
        while True:
            result = subprocess.run(['git', '-C', self.repo_dir, 'branch', '--list', name], stdout=subprocess.PIPE)
            if len(result.stdout) == 0:
                return name
            suffix += 1
            name = '{}-{}'.format(basename, suffix)

class CheckoutCorelibsAction(Action):
    def run(self):
        print('=====> Checking out swift-corelibs for scheme {}'.format(self.options.scheme))
        for repo, rev in self.options.repos.items():
            fork_repo = f'https://github.com/swiftwasm/{repo}.git'
            status = subprocess.run(['git', '-C', f'../{repo}', 'remote', 'get-url', 'swiftwasm'], stderr=subprocess.PIPE).returncode
            if status != 0:
                self.system('git', '-C', f'../{repo}', 'remote', 'add', 'swiftwasm', fork_repo)
            print(f'Checking out {repo} at {rev}')
            self.system('git', '-C', f'../{repo}', 'fetch', 'swiftwasm', rev)
            self.system('git', '-C', f'../{repo}', 'checkout', rev)

class DownloadBaseSnapshotAction(Action):
    def run(self):
        platform_info = platform.PlatformInfo.derive()
        snapshot_url, tarball_name = platform_info.snapshot_url(self.options.swift_org_download_channel, self.options.tag)
        extension = platform_info.package_extension

        tarball_path = os.path.join('..', 'build', 'Packaging', f'base-snapshot.{extension}')
        base_snapshot_dir = os.path.join('..', 'build', 'Packaging', 'base-snapshot')

        if os.path.exists(os.path.join(base_snapshot_dir, 'usr')):
            print(f"=====> Base snapshot '{base_snapshot_dir}' already exists")
            return

        if not os.path.exists(tarball_path):
            print(f"=====> Downloading base snapshot {tarball_name}")
            os.makedirs(os.path.dirname(tarball_path), exist_ok=True)
            self.system('curl', '--fail', '-L', '-o', tarball_path, snapshot_url)

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

        if self.options.optimize_disk_footprint:
            print(f"=====> Cleaning up base snapshot tarball '{tarball_path}'")
            os.remove(tarball_path)

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
    parser.add_argument('--optimize-disk-footprint',
                        help='Minimize disk footprint',
                        action='store_true', default=os.environ.get('CI', None) is not None)

    options = parser.parse_args(argv)

    import json
    manifest = json.load(open(os.path.join(REPO_ROOT, 'schemes', options.scheme, 'manifest.json')))

    if options.tag is None:
        options.tag = manifest['base-tag']
        if options.tag is None:
            raise Exception('Missing --tag option and no default tag for scheme {}'.format(options.scheme))

    options.repos = manifest.get('repos', {})
    options.update_checkout_scheme = options.scheme
    if 'update-checkout-scheme' in manifest:
        options.update_checkout_scheme = manifest['update-checkout-scheme']
    options.swift_org_download_channel = manifest['swift-org-download-channel']
    options.download_wasi_sysroot = manifest.get('wasi-sysroot', False)
    return options
