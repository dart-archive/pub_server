// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library appengine_pub.file_repository;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;
import 'package:pub_server/repository.dart';
import 'package:yaml/yaml.dart';

final Logger _logger = new Logger('pub_server.file_repository');

/// Implements the [PackageRepository] by storing pub packages on a file system.
class FileRepository extends PackageRepository {
  final String baseDir;

  FileRepository(this.baseDir);

  @override
  Stream<PackageVersion> versions(String package) {
    var directory = new Directory(path.join(baseDir, package));
    if (directory.existsSync()) {
      return directory
          .list(recursive: false)
          .where((fse) => fse is Directory)
          .map((dir) {
        var version = path.basename(dir.path);
        var pubspecFile = new File(pubspecFilePath(package, version));
        var tarballFile = new File(packageTarballPath(package, version));
        if (pubspecFile.existsSync() && tarballFile.existsSync()) {
          var pubspec = pubspecFile.readAsStringSync();
          return new PackageVersion(package, version, pubspec);
        }
      });
    }

    return new Stream.fromIterable([]);
  }

  // TODO: Could be optimized by searching for the exact package/version
  // combination instead of enumerating all.
  @override
  Future<PackageVersion> lookupVersion(String package, String version) {
    return versions(package)
        .where((pv) => pv.versionString == version)
        .toList()
        .then((List<PackageVersion> versions) {
      if (versions.length >= 1) return versions.first;
      return null;
    });
  }

  @override
  bool get supportsUpload => true;

  @override
  Future<PackageVersion> upload(Stream<List<int>> data) async {
    _logger.info('Start uploading package.');
    var bb = await data.fold(new BytesBuilder(),
        (BytesBuilder byteBuilder, d) => byteBuilder..add(d));
    var tarballBytes = bb.takeBytes();
    var tarBytes = new GZipDecoder().decodeBytes(tarballBytes);
    var archive = new TarDecoder().decodeBytes(tarBytes);
    ArchiveFile pubspecArchiveFile;
    for (var file in archive.files) {
      if (file.name == 'pubspec.yaml') {
        pubspecArchiveFile = file;
        break;
      }
    }
    if (pubspecArchiveFile != null) {
      // TODO: Error handling.
      var pubspec = loadYaml(UTF8.decode(_getBytes(pubspecArchiveFile)));

      var package = pubspec['name'] as String;
      var version = pubspec['version'] as String;

      var packageVersionDir =
          new Directory(path.join(baseDir, package, version));
      var pubspecFile = new File(pubspecFilePath(package, version));
      var tarballFile = new File(packageTarballPath(package, version));

      if (!packageVersionDir.existsSync()) {
        packageVersionDir.createSync(recursive: true);
      }
      pubspecFile.writeAsBytesSync(_getBytes(pubspecArchiveFile));
      tarballFile.writeAsBytesSync(tarballBytes);

      _logger.info('Uploaded new $package/$version');
    } else {
      _logger.warning('Did not find any pubspec.yaml file in upload. '
          'Aborting.');
      throw 'No pubspec file.';
    }
  }

  @override
  bool get supportsDownloadUrl => false;

  @override
  Future<Stream<List<int>>> download(String package, String version) async {
    var pubspecFile = new File(pubspecFilePath(package, version));
    var tarballFile = new File(packageTarballPath(package, version));

    if (pubspecFile.existsSync() && tarballFile.existsSync()) {
      return tarballFile.openRead();
    } else {
      throw 'package cannot be downloaded, because it does not exist';
    }
  }

  String pubspecFilePath(String package, String version) =>
      path.join(baseDir, package, version, 'pubspec.yaml');

  String packageTarballPath(String package, String version) =>
      path.join(baseDir, package, version, 'package.tar.gz');
}

// Since pkg/archive v1.0.31, content is `dynamic` although in our use case
// it's always `List<int>`
List<int> _getBytes(ArchiveFile file) => file.content as List<int>;
