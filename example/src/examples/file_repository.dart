// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert' as convert;
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:pub_server/repository.dart';
import 'package:yaml/yaml.dart';

final Logger _logger = Logger('pub_server.file_repository');

/// Implements the [PackageRepository] by storing pub packages on a file system.
class FileRepository extends PackageRepository {
  final String baseDir;

  FileRepository(this.baseDir);

  @override
  Stream<PackageVersion> versions(String package) {
    var directory = Directory(p.join(baseDir, package));
    if (directory.existsSync()) {
      return directory
          .list(recursive: false)
          .where((fse) => fse is Directory)
          .map((dir) {
        var version = p.basename(dir.path);
        var packageVersion = _getSpecificVersion(package, version);
        if (packageVersion != null) {
          return packageVersion;
        }
      });
    }

    return Stream.fromIterable([]);
  }

  @override
  Future<PackageVersion> lookupVersion(String package, String version) {
    return Future.value(_getSpecificVersion(package, version));
  }

  PackageVersion _getSpecificVersion(String package, String version) {
    var pubspecFile = File(pubspecFilePath(package, version));
    var tarballFile = File(packageTarballPath(package, version));
    if (pubspecFile.existsSync() && tarballFile.existsSync()) {
      var pubspec = pubspecFile.readAsStringSync();
      return PackageVersion(package, version, pubspec);
    } else {
      return null;
    }
  }

  @override
  bool get supportsUpload => true;

  @override
  Future<PackageVersion> upload(Stream<List<int>> data) async {
    _logger.info('Start uploading package.');
    var bb = await data.fold(
        BytesBuilder(), (BytesBuilder byteBuilder, d) => byteBuilder..add(d));
    var tarballBytes = bb.takeBytes();
    var tarBytes = GZipDecoder().decodeBytes(tarballBytes);
    var archive = TarDecoder().decodeBytes(tarBytes);
    ArchiveFile pubspecArchiveFile;
    for (var file in archive.files) {
      if (file.name == 'pubspec.yaml') {
        pubspecArchiveFile = file;
        break;
      }
    }

    if (pubspecArchiveFile == null) {
      throw 'Did not find any pubspec.yaml file in upload. Aborting.';
    }

    // TODO: Error handling.
    var pubspec = loadYaml(convert.utf8.decode(_getBytes(pubspecArchiveFile)));

    var package = pubspec['name'] as String;
    var version = pubspec['version'] as String;

    var packageVersionDir = Directory(p.join(baseDir, package, version));

    if (!packageVersionDir.existsSync()) {
      packageVersionDir.createSync(recursive: true);
    }

    var pubspecFile = File(pubspecFilePath(package, version));
    if (pubspecFile.existsSync()) {
      throw PackageAlreadyExistException(
          '`$package` already exists at version `$version`.');
    }

    var pubspecContent = convert.utf8.decode(_getBytes(pubspecArchiveFile));
    pubspecFile.writeAsStringSync(pubspecContent);
    File(packageTarballPath(package, version)).writeAsBytesSync(tarballBytes);

    _logger.info('Uploaded new $package/$version');

    return PackageVersion(package, version, pubspecContent);
  }

  @override
  bool get supportsDownloadUrl => false;

  @override
  Future<Stream<List<int>>> download(String package, String version) async {
    var pubspecFile = File(pubspecFilePath(package, version));
    var tarballFile = File(packageTarballPath(package, version));

    if (pubspecFile.existsSync() && tarballFile.existsSync()) {
      return tarballFile.openRead();
    } else {
      throw 'package cannot be downloaded, because it does not exist';
    }
  }

  String pubspecFilePath(String package, String version) =>
      p.join(baseDir, package, version, 'pubspec.yaml');

  String packageTarballPath(String package, String version) =>
      p.join(baseDir, package, version, 'package.tar.gz');
}

// Since pkg/archive v1.0.31, content is `dynamic` although in our use case
// it's always `List<int>`
List<int> _getBytes(ArchiveFile file) => file.content as List<int>;
