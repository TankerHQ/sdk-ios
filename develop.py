import argparse
import sys

from path import Path

import ci
import ci.cpp
import ci.ios
import ui


def main() -> None:
    parser = argparse.ArgumentParser()

    subparsers = parser.add_subparsers(title="subcommands", dest="command")

    update_conan_config_parser = subparsers.add_parser("update-conan-config")

    deps_cpp = subparsers.add_parser("deps-cpp")
    deps_cpp.add_argument("--release", action="store_true")
    deps_cpp.add_argument("--stable-native", action="store_true")
    deps_cpp.add_argument("--all-archs", action="store_true")

    subparsers.add_parser("generate-test-config")

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        sys.exit(1)

    if args.command == "update-conan-config":
        ci.cpp.update_conan_config("darwin")
        return

    if args.command == "generate-test-config":
        src_path = Path(__file__).abspath().parent
        ci.ios.generate_test_config(src_path, config_name="dev")
        return

    debug = not args.release
    all_archs = args.all_archs
    if all_archs:
        archs = ci.ios.ARCHS
    else:
        archs = ['x86_64']
    native_from_sources = not args.stable_native

    ui.info_1(
        "Installing C++ deps",
    )
    ui.info_2(
        " Settings:\n",
        "   debug: ", debug, "\n",
        "   native_from_sources: ", native_from_sources, "\n"
        "   archs: ", archs, "\n",
        sep="", end=""
    )
    deps_handler = ci.ios.DepsHandler(
        debug=debug,
        archs=archs,
        native_from_sources=native_from_sources
    )

    deps_handler.handle_cpp_deps()



if __name__ == "__main__":
    main()
