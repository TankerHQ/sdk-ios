from typing import Dict, List, Optional

import argparse
import os
from pathlib import Path
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
from tankerci.build_info import DepsConfig
import cli_ui as ui

PROFILES = [
    "ios-armv7-release",
    "ios-armv7s-release",
    "ios-armv8-release",
    "ios-x86-release",
    "ios-x86_64-release",
]


def _copy_folder_content(src_path: Path, dest_path: Path) -> None:
    ui.info_1("Moving content of", src_path, "to", dest_path)
    src_dirs = [p for p in src_path.iterdir() if p.is_dir()]
    for src_dir in src_dirs:
        dest_dir = dest_path / src_dir.name
        if dest_dir.exists():
            shutil.rmtree(dest_dir)
        ui.info_2(src_dir, "->", dest_dir)
        shutil.copytree(src_dir, dest_dir)
    src_files = [p for p in src_path.iterdir() if p.is_file()]
    for src_file in src_files:
        dest_file = dest_path / src_file.name
        if dest_file.exists():
            dest_file.unlink()
        ui.info_2(src_file, "->", dest_file)
        shutil.copy2(src_file, dest_file)


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
        contents = in_path.read_text()
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
            for lib in DepsConfig(self.get_build_path(profile)).all_lib_paths():
                all_libs.setdefault(lib.name, []).append(lib)
        return all_libs

    def generate_fat_libraries(self) -> None:
        ui.info_1("Generating fat libraries")
        if self.libraries_path.exists():
            shutil.rmtree(self.libraries_path)
        self.libraries_path.mkdir(parents=True, exist_ok=True)

        for lib_name, libs in self.get_all_dependency_libs().items():
            output = self.libraries_path / lib_name
            lib_strings: List[str] = [str(x) for x in libs]
            tankerci.run(
                "lipo",
                "-create",
                "-output",
                str(output),
                *lib_strings,
                cwd=self.conan_path,
            )

    def copy_headers(self) -> None:
        first_profile = list(self.profiles)[0]
        # we assume that all profiles have the same includes
        deps_info = DepsConfig(self.get_build_path(first_profile))
        for include_dir in deps_info["tanker"].include_dirs:
            include_path = Path(include_dir)

            _copy_folder_content(include_path, self.headers_path)

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
            str(self.pod_path / "Tanker.podspec"),
        )


class PodPublisher:
    def __init__(self, *, src_path: Path) -> None:
        self.src_path = src_path
        self.dest_path = self.src_path / "artifacts"
        if self.dest_path.exists():
            shutil.rmtree(self.dest_path)

    def copy_static_libs(self) -> None:
        ui.info_1("Copying static libs")
        libraries_path = self.src_path / "Tanker/Libraries"
        dest_path = self.dest_path / "Libraries"
        ui.info_2(libraries_path, "->", dest_path)
        shutil.copytree(libraries_path, dest_path)

    def copy_sources(self) -> None:
        ui.info_1("Copying sources")
        sources_path = self.src_path / "Tanker/Sources"

        ui.info_2(sources_path, "->", self.dest_path)
        shutil.copytree(sources_path, self.dest_path / "Sources")

        export_list_src = self.src_path / "Tanker/export_symbols.list"
        export_list_dest = self.dest_path / "export_symbols.list"

        ui.info_2(export_list_src, "->", export_list_dest)
        shutil.copy(export_list_src, export_list_dest)

    def copy_top_files(self) -> None:
        ui.info_1("Copying top files")
        for name in ("Tanker/LICENSE", "Tanker/Tanker.podspec"):
            src = self.src_path / name
            ui.info_2(src, "->", self.dest_path)
            shutil.copy(src, self.dest_path)

    def copy_headers(self) -> None:
        ui.info_1("Copying headers")
        headers_path = self.src_path / "Tanker" / "Headers"
        dest_path = self.dest_path / "Headers"
        ui.info_2(headers_path, "->", dest_path)
        shutil.copytree(headers_path, dest_path)

    def copy_test_sources(self) -> None:
        # trick cocoapods copy the Dummy.m to avoid error during validation
        ui.info_1("Copying dummy test file")
        dummy_test_path = self.src_path / "Tanker/Tests/Dummy.m"
        dest_path = self.dest_path / "Tests"
        dest_path.mkdir(parents=True, exist_ok=True)
        ui.info_2(dummy_test_path, "->", dest_path)
        shutil.copy(dummy_test_path, dest_path)

    def get_version_from_spec(self) -> str:
        contents = (self.src_path / "Tanker/Tanker.podspec").read_text()
        for line in contents.splitlines():
            match = re.match(r"^\s+s\.version\s+=\s+'(.*?)'", line)
            if match:
                return match.groups()[0]
        sys.exit("Could not find version from Tanker.podspec")

    def generate_archive(self) -> Path:
        version = self.get_version_from_spec()
        ui.info_1("Generating archive, version:", version)
        archive_name = "tanker-ios-sdk-%s.tar.gz" % version
        with tankerci.working_directory(self.dest_path):
            tankerci.run("tar cfvz %s *" % archive_name, shell=True)
            shutil.copy(archive_name, self.src_path)
            res = self.src_path / archive_name
        ui.info_2("Generated", res)
        return res

    def upload_archive(self, archive_path: Path) -> None:
        tankerci.gcp.GcpProject("tanker-prod").auth()
        tankerci.run("gsutil", "cp", str(archive_path), "gs://cocoapods.tanker.io/ios/")

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

    def write_artifacts(self) -> None:
        self.dest_path = Path.cwd() / "pod"
        shutil.rmtree(self.dest_path, ignore_errors=True)
        self.dest_path.mkdir(parents=True)

        self.copy_top_files()
        self.copy_static_libs()
        self.copy_sources()
        self.copy_headers()
        self.copy_test_sources()

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
    tanker_source: TankerSource, update: bool, tanker_ref: Optional[str]
) -> Builder:
    artifact_path = Path.cwd() / "package"
    tanker_deployed_ref = tanker_ref

    if tanker_source == TankerSource.UPSTREAM:
        profiles = [d.name for d in artifact_path.iterdir() if d.is_dir()]
    else:
        profiles = PROFILES
    if tanker_source == TankerSource.DEPLOYED and not tanker_deployed_ref:
        tanker_deployed_ref = "tanker/latest-stable@"
    tankerci.conan.install_tanker_source(
        tanker_source,
        output_path=Path("Tanker/conan"),
        profiles=profiles,
        update=update,
        tanker_deployed_ref=tanker_deployed_ref,
    )
    builder = Builder(src_path=Path.cwd(), profiles=profiles)
    builder.handle_sdk_deps(tanker_source=tanker_source)
    builder.generate_podspec()
    builder.handle_ios_deps()
    return builder


def build_and_test(
    *, tanker_source: TankerSource, tanker_ref: Optional[str] = None
) -> None:
    builder = prepare(tanker_source, False, tanker_ref)
    builder.build_and_test_pod()


def deploy(*, version: str, tanker_ref: str) -> None:
    tankerci.bump_files(version)
    build_and_test(tanker_source=TankerSource.DEPLOYED, tanker_ref=tanker_ref)
    src_path = Path.cwd()
    pod_publisher = PodPublisher(src_path=src_path)
    pod_publisher.publish()


def main() -> None:
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

    build_and_test_parser = subparsers.add_parser("build-and-test")
    build_and_test_parser.add_argument(
        "--use-tanker",
        type=tankerci.conan.TankerSource,
        default=tankerci.conan.TankerSource.EDITABLE,
        dest="tanker_source",
    )
    build_and_test_parser.add_argument("--tanker-ref")

    prepare_parser = subparsers.add_parser("prepare")
    prepare_parser.add_argument(
        "--use-tanker",
        type=tankerci.conan.TankerSource,
        default=tankerci.conan.TankerSource.EDITABLE,
        dest="tanker_source",
    )
    prepare_parser.add_argument("--tanker-ref")
    prepare_parser.add_argument(
        "--update",
        action="store_true",
        default=False,
        dest="update",
    )

    deploy_parser = subparsers.add_parser("deploy")
    deploy_parser.add_argument("--version", required=True)
    deploy_parser.add_argument("--tanker-ref", required=True)
    subparsers.add_parser("mirror")

    args = parser.parse_args()
    command = args.command

    if args.home_isolation:
        tankerci.conan.set_home_isolation()
        tankerci.conan.update_config()
        if command in ("build-and-test", "deploy"):
            # Because of GitLab issue https://gitlab.com/gitlab-org/gitlab/-/issues/254323
            # the downstream deploy jobs will be triggered even if upstream has failed
            # By removing the cache we ensure that we do not use a
            # previously built (and potentially broken) release candidate to deploy a binding
            tankerci.conan.run("remove", "tanker/*", "--force")

    if command == "build-and-test":
        build_and_test(
            tanker_source=args.tanker_source,
            tanker_ref=args.tanker_ref,
        )
        pod_publisher = PodPublisher(src_path=Path.cwd())
        pod_publisher.write_artifacts()
    elif command == "prepare":
        prepare(args.tanker_source, args.update, args.tanker_ref)
    elif command == "deploy":
        deploy(version=args.version, tanker_ref=args.tanker_ref)
    elif command == "mirror":
        tankerci.git.mirror(github_url="git@github.com:TankerHQ/sdk-ios")
    elif command == "reset-branch":
        fallback = os.environ["CI_COMMIT_REF_NAME"]
        ref = tankerci.git.find_ref(
            Path.cwd(), [f"origin/{args.branch}", f"origin/{fallback}"]
        )
        tankerci.git.reset(Path.cwd(), ref)
    elif command == "download-artifacts":
        tankerci.gitlab.download_artifacts(
            project_id=args.project_id,
            pipeline_id=args.pipeline_id,
            job_name=args.job_name,
        )
    else:
        parser.print_help()
        sys.exit()


if __name__ == "__main__":
    main()
