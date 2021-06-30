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
        self.private_headers_path = self.pod_path / "PrivateHeaders"
        self.example_path = self.pod_path / "Example"
        self.profiles = profiles

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

    def merge_all_dependencies(self) -> None:
        if self.libraries_path.exists():
            shutil.rmtree(self.libraries_path)
        self.libraries_path.mkdir(parents=True, exist_ok=True)
        env = os.environ.copy()
        env["ARMERGE_LDFLAGS"] = "-bitcode_bundle"
        for profile in self.profiles:
            specific_arch_path = self.libraries_path / profile
            specific_arch_path.mkdir()
            lib_paths = DepsConfig(self.get_build_path(profile)).all_lib_paths()
            tankerci.run(
                "armerge",
                "--keep-symbols=^_?tanker_.*",
                f"--output={specific_arch_path / 'libtankerdeps.a'}",
                *lib_paths,
                env=env,
            )

    def generate_xcframework(self) -> None:
        ui.info_1("Generating xcframework")

        # We still have to use lipo to unify iphone libs and simulator libs
        # Otherwise, xcodebuild -create-xcframework will complain about "equivalent library definitions"
        all_libs = [str(self.libraries_path / p / "libtankerdeps.a") for p in self.profiles]
        simulator_libs = [str(self.libraries_path / p / "libtankerdeps.a") for p in self.profiles if p.find("x86") != -1]
        iphone_libs = list(set(simulator_libs) ^ set(all_libs))

        simulator_dir = self.libraries_path / "simulator"
        iphone_dir = self.libraries_path / "iphone"
        simulator_dir.mkdir(parents=True, exist_ok=True)
        iphone_dir.mkdir(parents=True, exist_ok=True)

        # xcodebuild is bad, -headers must be given a single path, we have to ship ctanker/ and ctanker.h ...
        # so create a ad-hoc folder for that
        with tempfile.TemporaryDirectory() as f:
            headers_temp_dir = Path(f)
            ctanker_path = self.private_headers_path / "ctanker"
            shutil.copytree(ctanker_path, headers_temp_dir / "ctanker")
            ctanker_h = self.private_headers_path / "ctanker.h"
            shutil.copy(ctanker_h, headers_temp_dir)

            fat_simulator_lib = str(simulator_dir / "libtankerdeps.a")
            fat_iphone_lib = str(iphone_dir/ "libtankerdeps.a")
            xcframework_dir = self.src_path / "Tanker" / "Frameworks" / "TankerDeps.xcframework"
            shutil.rmtree(xcframework_dir, ignore_errors=True)

            tankerci.run(
                "lipo",
                "-create",
                "-output",
                fat_simulator_lib,
                *simulator_libs,
                cwd=self.conan_path,
            )
            tankerci.run(
                "lipo",
                "-create",
                "-output",
                fat_iphone_lib,
                *iphone_libs,
                cwd=self.conan_path,
            )

            tankerci.run(
                "xcodebuild",
                "-create-xcframework",
                "-library", fat_simulator_lib,
                "-headers", headers_temp_dir,
                "-library", fat_iphone_lib,
                "-headers", headers_temp_dir,
                "-output",
                xcframework_dir,
                cwd=self.conan_path,
            )

    def copy_headers(self) -> None:
        first_profile = list(self.profiles)[0]
        # we assume that all profiles have the same includes
        deps_info = DepsConfig(self.get_build_path(first_profile))
        for include_dir in deps_info["tanker"].include_dirs:
            include_path = Path(include_dir)

            _copy_folder_content(include_path, self.private_headers_path)

    def handle_sdk_deps(self) -> None:
        ui.info_1("copying sdk-native for profiles: ", self.profiles)
        self.merge_all_dependencies()
        self.copy_headers()
        self.generate_xcframework()

    def handle_ios_deps(self) -> None:
        ui.info_2("Installing Tanker pod dependencies")
        tankerci.run("pod", "install", "--repo-update", "--clean-install", cwd=self.example_path)

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


def upload_archive(archive_path: Path) -> None:
    tankerci.gcp.GcpProject("tanker-prod").auth()
    tankerci.run("gsutil", "cp", str(archive_path), "gs://cocoapods.tanker.io/ios/")


class PodPublisher:
    def __init__(self, *, src_path: Path) -> None:
        self.src_path = src_path
        self.dest_path = self.src_path / "artifacts"
        if self.dest_path.exists():
            shutil.rmtree(self.dest_path)

    def copy_xcframework(self) -> None:
        ui.info_1("Copying xcframework")
        xcframework_path = self.src_path / "Tanker/Frameworks"
        dest_path = self.dest_path / "Frameworks"
        ui.info_2(xcframework_path, "->", dest_path)
        shutil.copytree(xcframework_path, dest_path)

    def copy_sources(self) -> None:
        ui.info_1("Copying sources")
        sources_path = self.src_path / "Tanker/Sources"

        ui.info_2(sources_path, "->", self.dest_path)
        shutil.copytree(sources_path, self.dest_path / "Sources")

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
        self.copy_headers()
        self.copy_xcframework()
        self.copy_sources()
        self.copy_test_sources()

    def publish(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            self.dest_path = Path(tmpdir)
            self.copy_top_files()
            self.copy_sources()
            self.copy_headers()
            self.copy_xcframework()
            self.copy_test_sources()
            archive = self.generate_archive()
            upload_archive(archive)
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
    builder.handle_sdk_deps()
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
        default=tankerci.conan.TankerSource.LOCAL,
        dest="tanker_source",
    )
    build_and_test_parser.add_argument("--tanker-ref")

    prepare_parser = subparsers.add_parser("prepare")
    prepare_parser.add_argument(
        "--use-tanker",
        type=tankerci.conan.TankerSource,
        default=tankerci.conan.TankerSource.LOCAL,
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
    elif command == "reset-branch":
        fallback = os.environ["CI_COMMIT_REF_NAME"]
        ref = tankerci.git.find_ref(
            Path.cwd(), [f"origin/{args.branch}", f"origin/{fallback}"]
        )
        tankerci.git.reset(Path.cwd(), ref, clean=False)
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
