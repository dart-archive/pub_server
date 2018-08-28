## 0.1.5

* Differentiate between client- and server-side upload issues.

## 0.1.4+2

* Drop support for Dart 1.x.

## 0.1.4+1

* Support Dart 2 stable releases.

* Support latest release of `package:pub_semver`.

## 0.1.4

* Dart 2 support with `dart2_constant`.

## 0.1.3

* `PackageRepository.download` now has more specific return type:
  `Future<Stream<List<int>>>`.

* Fix incorrect boundary parsing during upload.

* Update minimum Dart SDK to `1.23.0`.

## 0.1.2

* Add support for generic exceptions raised e.g. due to `pubspec.yaml`
  validation failure.

## 0.1.1+4

* Support the latest version of `pkg/shelf`.

## 0.1.1+3

* Support the latest release of `pub_semver`.

## 0.1.1+2

* Fixed null comparision.

## 0.1.1+1

* Updated dependencies.

## 0.1.1

* Return "400 Bad Request" in case the version number encoded in the URL is not
  a valid semantic version

## 0.1.0

Initial release.
