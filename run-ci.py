import argparse
import sys
import contextlib

from path import Path

import ci
import ci.conan
import ci.cpp
import ci.ios
import ci.git
import ci.mail

DEPLOYED_TANKER = "tanker/2.0.0-alpha8@tanker/stable"
LOCAL_TANKER = "tanker/dev@tanker/dev"

def get_notifier(name: str):
    if name == 'mail':
        return ci.mail.notify_failure('sdk-ios')
    else:
        return contextlib.suppress()


def build_and_test(args):
    src_path = Path.getcwd()
    tanker_conan_ref = LOCAL_TANKER

    if args.use_tanker == "deployed":
        tanker_conan_ref = DEPLOYED_TANKER
    elif args.use_tanker == "local":
        ci.conan.export(src_path=Path.getcwd().parent / "sdk-native", ref_or_channel="tanker/dev")
    elif args.use_tanker == "same-as-branch":
        workspace = ci.git.prepare_sources(repos=["sdk-native", "sdk-ios"])
        src_path = workspace / "sdk-ios"
        ci.conan.export(src_path=workspace / "sdk-native", ref_or_channel="tanker/dev")
    else:
        parser.print_help()
        sys.exit()

    if args.only_arch:
        archs = ["x86_64", "x86"]
    else:
        archs = ci.ios.ARCHS

    ci.ios.build_and_test(src_path=src_path, archs=archs, debug=args.debug, tanker_conan_ref=tanker_conan_ref)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--isolate-conan-user-home", action="store_true", dest="home_isolation", default=False)

    subparsers = parser.add_subparsers(title="subcommands", dest="command")
    subparsers.add_parser("generate-test-config")

    subparsers.add_parser("update-conan-config")

    check_parser = subparsers.add_parser("build-and-test")
    check_parser.add_argument("--debug", action="store_true", default=False)
    check_parser.add_argument("--use-tanker", choices=['deployed', 'local', 'same-as-branch'], default='local')
    check_parser.add_argument("--only-arch", action="store_true", dest="only_arch", default=False)
    check_parser.add_argument("--notifier", choices=['mail', 'none'], default='none')

    deploy_parser = subparsers.add_parser("deploy")
    deploy_parser.add_argument("--git-tag", required=True)
    subparsers.add_parser("mirror")

    args = parser.parse_args()
    if args.home_isolation:
        ci.conan.set_home_isolation()

    if args.command == "update-conan-config":
        ci.cpp.update_conan_config()
    elif args.command == "build-and-test":
        with get_notifier(args.notifier):
            build_and_test(args)
    elif args.command == "generate-test-config":
        src_path = Path(__file__).abspath().parent
        ci.ios.generate_test_config(src_path / "Tanker" / "Tests", config_name="dev")
        return
    elif args.command == "deploy":
        git_tag = args.git_tag
        ci.ios.deploy(src_path=Path.getcwd(), git_tag=git_tag, tanker_conan_ref=DEPLOYED_TANKER)
    elif args.command == "mirror":
        ci.git.mirror(github_url="git@github.com:TankerHQ/sdk-ios")
    else:
        parser.print_help()
        sys.exit()


if __name__ == "__main__":
    main()
