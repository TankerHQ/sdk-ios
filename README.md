[cocoapods-badge]: https://img.shields.io/static/v1.svg?label=Cocoapods&message=compatible&color=brightgreen
[last-commit-badge]: https://img.shields.io/github/last-commit/TankerHQ/sdk-ios.svg?label=Last%20commit&logo=github
[license-badge]: https://img.shields.io/badge/License-Apache%202.0-blue.svg
[license-link]: https://opensource.org/licenses/Apache-2.0
[platform-badge]: https://img.shields.io/static/v1.svg?label=Platform&message=ios&color=lightgrey

<img src="https://tanker.io/images/github-logo.png" alt="Tanker logo" width="180" />

[![License][license-badge]][license-link]
![Cocoapods][cocoapods-badge]
![Platform][platform-badge]
![Last Commit][last-commit-badge]

# Encryption SDK for iOS

[Overview](#overview) · [Getting started](#getting-started) · [Documentation](#documentation) · [Release notes](#release-notes) · [Contributing](#contributing) · [License](#license)

## Overview

Tanker is an open-source client SDK that can be embedded in any application.

It leverages powerful **client-side encryption** of any type of data, textual or binary, but without performance loss and assuring a **seamless end-user experience**. No cryptographic skills are required.

## Getting started

The Tanker iOS SDK is distributed on CocoaPods.

You just need to add the following lines to your `Podfile`:

```ruby
source 'https://github.com/CocoaPods/Specs.git'
source 'https://github.com/TankerHQ/PodSpecs.git'

target 'YourApp' do
  use_frameworks!
  pod 'Tanker', '~> X.Y.Z'
end
```

Tanker also provides open-source **[Android](https://github.com/TankerHQ/sdk-android)** and **[JavaScript](https://github.com/TankerHQ/sdk-js)** SDKs.

## Documentation

For more details and code examples, please refer to:

* [SDK implementation guide](https://tanker.io/docs/latest/guide/getting-started/?language=ios)
* [API reference](https://tanker.io/docs/latest/api/tanker/?language=ios)
* [Product overview](https://tanker.io/product)

Or fiddle with the [quickstart examples](https://github.com/TankerHQ/quickstart-examples) to see the Tanker SDKs integrated in a collection of demo apps.

## Release notes

Detailed changes for each release are documented in the [release notes](https://github.com/TankerHQ/sdk-ios/releases).

## Contributing

We welcome feedback. Feel free to open any issue on the Github bug tracker.

We are actively working to allow external developers to build and test this sdk from source.

## License

The Tanker iOS SDK is licensed under the [Apache License, version 2.0](http://www.apache.org/licenses/LICENSE-2.0).
