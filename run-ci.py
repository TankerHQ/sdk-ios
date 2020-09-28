from typing import Dict, List, Optional

import re
import shutil
import sys
import tempfile

import tankerci
import tankerci.conan
from tankerci.conan import TankerSource
import tankerci.context
import tankerci.cpp
import tankerci.gcp
import tankerci.git
import tankerci.gitlab
import cli_ui as ui
from path import Path

PROFILES = [
    "ios-armv7-release",
    "ios-armv7s-release",
    "ios-armv8-release",
    "ios-x86-release",
    "ios-x86_64-release",
]


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
    def __init__(self, *, src_path: Path, profiles: List[str]):
        self.src_path = src_path
        self.pod_path = self.src_path / "Tanker"
        self.conan_path = self.pod_path / "conan"
        self.libraries_path = self.pod_path / "Libraries"
        self.headers_path = self.pod_path / "Headers"
        self.example_path = self.pod_path / "Example"
        self.profiles = profiles

    def generate_podspec(self) -> None:
        static_libs = self.get_static_libs()
        in_path = self.src_path / "Tanker/Tanker.in.podspec"
        contents = in_path.text()
        link_flags = [
            f"-l{x.name[3:-2]}" for x in static_libs
        ]  # strip 'lib' prefix and '.a' suffix
        contents = contents.replace("@static_libs_link_flags@", " ".join(link_flags))
        out_path = self.pod_path / "Tanker.podspec"
        out_path.write_text(contents)
        ui.info_2("Generated", out_path)

    def get_static_libs(self) -> List[Path]:
        libs_path = self.libraries_path
        return libs_path.glob("*.a")  # type: ignore

    def get_build_path(self, profile: str) -> Path:
        return self.conan_path / profile

    def get_all_dependency_libs(self) -> Dict[str, List[Path]]:
        all_libs: Dict[str, List[Path]] = dict()
        for profile in self.profiles:
            deps = tankerci.conan.get_dependencies_libs(
                self.get_build_path(profile) / "conanbuildinfo.json"
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
                "lipo", "-create", "-output", output, *libs, cwd=self.conan_path
            )

    def copy_headers(self) -> None:
        first_profile = list(self.profiles)[0]
        # we assume that all profiles have the same includes
        conan_info = self.get_build_path(first_profile) / "conanbuildinfo.json"
        include_paths = tankerci.conan.get_dependencies_include_paths(conan_info)
        for src_include_path in include_paths["tanker"]:
            _copy_folder_content(src_include_path, self.headers_path)

    def handle_sdk_deps(self, *, tanker_source: TankerSource) -> None:
        ui.info_1("copying sdk-native for profiles: ", self.profiles)
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


def prepare(
    tanker_source: TankerSource, update: bool, tanker_deployed_ref: Optional[str]
) -> Builder:
    artifact_path = Path.getcwd() / "package"
    if tanker_source == TankerSource.UPSTREAM:
        profiles = [d.basename() for d in artifact_path.dirs()]
    else:
        profiles = PROFILES
    tankerci.conan.install_tanker_source(
        tanker_source,
        output_path=Path("Tanker/conan"),
        profiles=profiles,
        update=update,
        tanker_deployed_ref=tanker_deployed_ref,
    )
    builder = Builder(src_path=Path.getcwd(), profiles=profiles)
    builder.handle_sdk_deps(tanker_source=tanker_source)
    builder.generate_podspec()
    builder.handle_ios_deps()
    return builder


def build_and_test(
    *, tanker_source: TankerSource, tanker_deployed_ref: Optional[str] = None
) -> None:
    tankerci.conan.update_config()
    builder = prepare(tanker_source, False, tanker_deployed_ref)
    builder.build_and_test_pod()


def deploy(*, version: str) -> None:
    tankerci.bump_files(version)
    build_and_test(tanker_source=TankerSource.DEPLOYED,)
    src_path = Path.getcwd()
    pod_publisher = PodPublisher(src_path=src_path)
    pod_publisher.publish()


def main() -> None:
    parser = tankerci.cpp.init_parser()

    args = parser.parse_args()
    if args.home_isolation:
        tankerci.conan.set_home_isolation()

    if args.command == "build-and-test":
        build_and_test(
            tanker_source=args.tanker_source,
            tanker_deployed_ref=args.tanker_deployed_ref,
        )
    elif args.command == "prepare":
        prepare(args.tanker_source, args.update, args.tanker_deployed_ref)
    elif args.command == "deploy":
        deploy(version=args.version)
    elif args.command == "mirror":
        tankerci.git.mirror(github_url="git@github.com:TankerHQ/sdk-ios")
    else:
        tankerci.cpp.handle_common_subcommands(parser, args)


if __name__ == "__main__":
    main()
