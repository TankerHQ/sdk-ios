import argparse
import sys


import ci
import ci.cpp
import ci.ios


def main():
    parser = argparse.ArgumentParser()

    subparsers = parser.add_subparsers(title="subcommands", dest="command")

    update_conan_config_parser = subparsers.add_parser("update-conan-config")
    update_conan_config_parser.add_argument("--platform", required=True)

    check_parser = subparsers.add_parser("check")
    check_parser.add_argument(
        "--native-from-sources", action="store_true", dest="native_from_sources"
    )

    subparsers.add_parser("deploy")

    args = parser.parse_args()

    if args.command == "update-conan-config":
        ci.cpp.update_conan_config(args.platform)
    elif args.command == "check":
        ci.ios.check(native_from_sources=args.native_from_sources)
    elif args.command == "deploy":
        ci.ios.deploy()
    else:
        parser.print_help()
        sys.exit()


if __name__ == "__main__":
    main()
