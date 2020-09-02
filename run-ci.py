from typing import Dict, List

import argparse
import re
import shutil
import sys
import tempfile
from enum import Enum

import tankerci
import tankerci.conan
import tankerci.cpp
import tankerci.gcp
import tankerci.git
import tankerci.gitlab
import cli_ui as ui
from path import Path

DEPLOYED_TANKER = "tanker/2.5.1@tanker/stable"
LOCAL_TANKER = "tanker/dev@"

ARCHS = ["armv7", "armv7s", "armv8", "x86", "x86_64"]


class TankerSource(Enum):
    LOCAL = "local"
    SAME_AS_BRANCH = "same-as-branch"
    DEPLOYED = "deployed"
    UPSTREAM = "upstream"


def _copy_folder_content(src_path: Path, dest_path: Path) -> None:
    ui.info_1("Moving content of", src_path, "to", dest_path)
    for src_dir in src_path.dirs():
        dest_dir = dest_path / src_dir.basename()
        dest_dir.rmtree_p()
        ui.info_2(src_dir, "->", dest_dir)
        src_dir.copytree(dest_dir)
    for src_file in src_path.files():
        dest_file = dest_path / src_file.basename()
        dest_file.remove_p()
        ui.info_2(src_file, "->", dest_file)
        src_file.copy2(dest_file)


class Builder:
    def __init__(self, *, src_path: Path, debug: bool, archs: List[str]):
        self.src_path = src_path
        self.pod_path = self.src_path / "Tanker"
        self.conan_path = self.pod_path / "conan"
        self.conan_out_path = self.conan_path / "out"
        self.libraries_path = self.pod_path / "Libraries"
        self.headers_path = self.pod_path / "Headers"
        self.example_path = self.pod_path / "Example"
        self.debug = debug
        self.archs = archs

    def generate_podspec(self) -> None:
        static_libs = self.get_static_libs()
        in_path = self.src_path / "Tanker/Tanker.in.podspec"
        contents = in_path.text()
        link_flags = [
            f"-l{x.name[3:-2]}" for x in static_libs
        ]  # strip 'lib' prefix and '.a' suffix
        contents = contents.replace("@static_libs_link_flags@", " ".join(link_flags))
        out_path = self.src_path / "Tanker/Tanker.podspec"
        out_path.write_text(contents)
        ui.info_2("Generated", out_path)

    def get_static_libs(self) -> List[Path]:
        libs_path = self.src_path / "Tanker/Libraries"
        return libs_path.glob("*.a")  # type: ignore

    def get_build_path(self, arch: str) -> Path:
        res = self.conan_out_path / arch
        res.makedirs_p()
        return res

    def get_all_dependency_libs(self) -> Dict[str, List[Path]]:
        all_libs: Dict[str, List[Path]] = dict()
        for arch in self.archs:
            deps = tankerci.conan.get_dependencies_libs(
                self.get_build_path(arch) / "conanbuildinfo.json"
            )
            for _, libs in deps.items():
                if not libs:
                    continue
                for lib in libs:
                    all_libs.setdefault(lib.name, []).extend([lib])
        return all_libs

    def generate_fat_libraries(self) -> None:
        ui.info_1("Generating fat libraries")
        self.libraries_path.rmtree_p()
        self.libraries_path.makedirs_p()

        for lib_name, libs in self.get_all_dependency_libs().items():
            output = self.libraries_path / lib_name
            tankerci.run(
                "lipo", "-create", "-output", output, *libs, cwd=self.conan_out_path
            )

    def copy_headers(self) -> None:
        first_arch = list(self.archs)[0]
        # we assume that all archs have the same includes
        conan_info = self.get_build_path(first_arch) / "conanbuildinfo.json"
        include_paths = tankerci.conan.get_dependencies_include_paths(conan_info)
        for src_include_path in include_paths["tanker"]:
            _copy_folder_content(src_include_path, self.headers_path)

    def get_profile_name(self, arch: str) -> str:
        if self.debug:
            build_type = "debug"
        else:
            build_type = "release"
        return f"ios-{arch}-{build_type}"

    def install_sdk_native(self, tanker_source: TankerSource) -> None:
        if tanker_source in [TankerSource.LOCAL, TankerSource.SAME_AS_BRANCH]:
            tanker_conan_ref = LOCAL_TANKER
            tanker_conan_extra_flags = ["--build=tanker"]
        elif tanker_source == TankerSource.UPSTREAM:
            tanker_conan_ref = LOCAL_TANKER
            tanker_conan_extra_flags = []
        else:
            tanker_conan_ref = DEPLOYED_TANKER
            tanker_conan_extra_flags = []

        for arch in self.archs:
            # fmt: off
            tankerci.conan.run(
                "install", tanker_conan_ref,
                *tanker_conan_extra_flags,
                "--update",
                "--profile", self.get_profile_name(arch),
                "--install-folder", self.get_build_path(arch),
                "--generator", "json"
            )
            # fmt: on

    def handle_sdk_deps(self, *, tanker_source: TankerSource) -> None:
        ui.info_1("Installing sdk-native for archs: ", self.archs)
        # clean last build files, to avoid losing 2 days when an unexpected binary is used.
        self.conan_out_path.rmtree_p()
        self.install_sdk_native(tanker_source)
        self.generate_fat_libraries()
        self.copy_headers()

    def handle_ios_deps(self) -> None:
        ui.info_2("Installing Tanker pod dependencies")
        tankerci.run("pod", "deintegrate", cwd=self.example_path)
        tankerci.run("pod", "install", "--repo-update", cwd=self.example_path)

    def build_and_test_pod(self) -> None:
        ui.info_2("building pod and launching tests")
        tankerci.run(
            "pod",
            "lib",
            "lint",
            "--verbose",
            "--allow-warnings",
            self.pod_path / "Tanker.podspec",
        )


class PodPublisher:
    def __init__(self, *, src_path: Path) -> None:
        self.src_path = src_path
        self.dest_path = self.src_path / "artifacts"
        self.dest_path.rmtree_p()
        self.conan_out_path = self.src_path / "Tanker/conan/out"

    def copy_static_libs(self) -> None:
        ui.info_1("Copying static libs")
        libraries_path = self.src_path / "Tanker/Libraries"
        dest_path = self.dest_path / "Libraries"
        ui.info_2(libraries_path, "->", dest_path)
        libraries_path.copytree(dest_path)

    def copy_sources(self) -> None:
        ui.info_1("Copying sources")
        sources_path = self.src_path / "Tanker/Sources"

        ui.info_2(sources_path, "->", self.dest_path)
        sources_path.copytree(self.dest_path / "Sources")

        export_list_src = self.src_path / "Tanker/export_symbols.list"
        export_list_dest = self.dest_path / "export_symbols.list"

        ui.info_2(export_list_src, "->", export_list_dest)
        export_list_src.copy(export_list_dest)

    def copy_top_files(self) -> None:
        ui.info_1("Copying top files")
        for name in ("Tanker/LICENSE", "Tanker/Tanker.podspec"):
            src = self.src_path / name
            ui.info_2(src, "->", self.dest_path)
            src.copy(self.dest_path)

    def copy_headers(self) -> None:
        ui.info_1("Copying headers")
        headers_path = self.src_path / "Tanker" / "Headers"
        dest_path = self.dest_path / "Headers"
        ui.info_2(headers_path, "->", dest_path)
        headers_path.copytree(dest_path)

    def copy_test_sources(self) -> None:
        # trick cocoapods copy the Dummy.m to avoid error during validation
        ui.info_1("Copying dummy test file")
        dummy_test_path = self.src_path / "Tanker/Tests/Dummy.m"
        dest_path = self.dest_path / "Tests"
        dest_path.makedirs_p()
        ui.info_2(dummy_test_path, "->", dest_path)
        dummy_test_path.copy(dest_path)

    def get_version_from_spec(self) -> str:
        contents = (self.src_path / "Tanker/Tanker.podspec").text()
        for line in contents.splitlines():
            match = re.match(r"^\s+s\.version\s+=\s+'(.*?)'", line)
            if match:
                return match.groups()[0]  # type: ignore
        sys.exit("Could not find version from Tanker.podspec")

    def generate_archive(self) -> Path:
        version = self.get_version_from_spec()
        ui.info_1("Generating archive, version:", version)
        archive_name = "tanker-ios-sdk-%s.tar.gz" % version
        with self.dest_path:
            tankerci.run("tar cfvz %s *" % archive_name, shell=True)
            shutil.copy(archive_name, self.src_path)
            res = self.src_path / archive_name
        ui.info_2("Generated", res)
        return res

    def upload_archive(self, archive_path: Path) -> None:
        tankerci.gcp.GcpProject("tanker-prod").auth()
        tankerci.run("gsutil", "cp", archive_path, "gs://cocoapods.tanker.io/ios/")

    def build_pod(self) -> None:
        # fmt: off
        tankerci.run(
            "pod", "spec", "lint", "Tanker/Tanker.podspec",
            "--verbose",
            "--allow-warnings",
            "--skip-tests",
            cwd=self.src_path,
        )
        # fmt: on

    def publish_pod(self) -> None:
        # fmt: off
        tankerci.run(
            "pod", "repo", "push", "tanker", "Tanker/Tanker.podspec",
            "--skip-tests",
            "--verbose",
            "--allow-warnings",
            cwd=self.src_path,
        )
        # fmt: on

    def publish(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            self.dest_path = Path(tmpdir)
            self.copy_top_files()
            self.copy_static_libs()
            self.copy_sources()
            self.copy_headers()
            self.copy_test_sources()
            archive = self.generate_archive()
            self.upload_archive(archive)
        self.build_pod()
        self.publish_pod()


def build_and_test(
    *, tanker_source: TankerSource, only_macos_archs: bool = False, debug: bool = False
) -> None:
    tankerci.conan.update_config()
    src_path = Path.getcwd()

    if only_macos_archs:
        archs = ["x86_64", "x86"]
    else:
        archs = ARCHS

    if tanker_source == TankerSource.LOCAL:
        tankerci.conan.export(
            src_path=Path.getcwd().parent / "sdk-native",
            ref_or_channel=LOCAL_TANKER,
        )
    elif tanker_source == TankerSource.UPSTREAM:
        for arch in archs:
            profile = f"ios-{arch}-release"
            package_folder = Path.getcwd() / "package" / profile

            tankerci.conan.export_pkg(
                Path.getcwd() / "package" / "conanfile.py",
                profile=profile,
                force=True,
                package_folder=package_folder,
            )
    elif tanker_source == TankerSource.SAME_AS_BRANCH:
        workspace = tankerci.git.prepare_sources(repos=["sdk-native", "sdk-ios"])
        src_path = workspace / "sdk-ios"
        tankerci.conan.export(
            src_path=workspace / "sdk-native",
            ref_or_channel=LOCAL_TANKER,
        )

    builder = Builder(src_path=src_path, debug=debug, archs=archs)
    builder.handle_sdk_deps(tanker_source=tanker_source)
    builder.generate_podspec()
    builder.handle_ios_deps()
    builder.build_and_test_pod()


def deploy(*, git_tag: str) -> None:
    version = tankerci.version_from_git_tag(git_tag)
    tankerci.bump_files(version)
    build_and_test(
        tanker_source=TankerSource.DEPLOYED, debug=False, only_macos_archs=False
    )
    src_path = Path.getcwd()
    pod_publisher = PodPublisher(src_path=src_path)
    pod_publisher.publish()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--isolate-conan-user-home",
        action="store_true",
        dest="home_isolation",
        default=False,
    )

    subparsers = parser.add_subparsers(title="subcommands", dest="command")

    reset_branch_parser = subparsers.add_parser("reset-branch")
    reset_branch_parser.add_argument("branch")

    download_artifacts_parser = subparsers.add_parser("download-artifacts")
    download_artifacts_parser.add_argument("--project-id", required=True)
    download_artifacts_parser.add_argument("--pipeline-id", required=True)
    download_artifacts_parser.add_argument("--job-name", required=True)

    check_parser = subparsers.add_parser("build-and-test")
    check_parser.add_argument("--debug", action="store_true", default=False)
    check_parser.add_argument(
        "--use-tanker", type=TankerSource, default=TankerSource.LOCAL
    )
    check_parser.add_argument(
        "--only-macos-archs",
        action="store_true",
        dest="only_macos_archs",
        default=False,
        help="skip ios architectures - useful if you only want to run the tests or use `pod check`.",  # noqa: E501
    )

    deploy_parser = subparsers.add_parser("deploy")
    deploy_parser.add_argument("--git-tag", required=True)
    subparsers.add_parser("mirror")

    args = parser.parse_args()
    if args.home_isolation:
        tankerci.conan.set_home_isolation()

    if args.command == "build-and-test":
        build_and_test(
            tanker_source=args.use_tanker,
            debug=args.debug,
            only_macos_archs=args.only_macos_archs,
        )
    elif args.command == "deploy":
        git_tag = args.git_tag
        deploy(git_tag=git_tag)
    elif args.command == "reset-branch":
        ref = tankerci.git.find_ref(
            Path.getcwd(), [f"origin/{args.branch}", "origin/master"]
        )
        tankerci.git.reset(Path.getcwd(), ref)
    elif args.command == "download-artifacts":
        tankerci.gitlab.download_artifacts(
            project_id=args.project_id,
            pipeline_id=args.pipeline_id,
            job_name=args.job_name,
        )
    elif args.command == "mirror":
        tankerci.git.mirror(github_url="git@github.com:TankerHQ/sdk-ios")
    else:
        parser.print_help()
        sys.exit()


if __name__ == "__main__":
    main()
