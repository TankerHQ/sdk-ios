import argparse
import sys


import ci
import ci.cpp
import ci.ios
import ci.git


def main():
    parser = argparse.ArgumentParser()

    subparsers = parser.add_subparsers(title="subcommands", dest="command")

    update_conan_config_parser = subparsers.add_parser("update-conan-config")
    update_conan_config_parser.add_argument("--platform", required=True)

    check_parser = subparsers.add_parser("check")
    check_parser.add_argument(
        "--native-from-sources", action="store_true", dest="native_from_sources"
    )

    deploy_parser = subparsers.add_parser("deploy")
    deploy_parser.add_argument("--git-tag", required=True)
    subparsers.add_parser("mirror")

    args = parser.parse_args()

    if args.command == "update-conan-config":
        ci.cpp.update_conan_config(args.platform)
    elif args.command == "check":
        ci.ios.check(native_from_sources=args.native_from_sources)
    elif args.command == "deploy":
        git_tag = args.git_tag
        ci.ios.deploy(git_tag=git_tag)
    elif args.command == "mirror":
        ci.git.mirror(github_url="git@github.com:TankerHQ/sdk-ios")
    else:
        parser.print_help()
        sys.exit()


if __name__ == "__main__":
    main()
