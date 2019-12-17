// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library pub_server.copy_and_write_repository;

import 'dart:async';

import 'package:logging/logging.dart';
import 'package:pub_server/repository.dart';

final Logger _logger = Logger('pub_server.cow_repository');

/// A [CopyAndWriteRepository] writes to one repository and directs
/// read-misses to another repository.
///
/// Package versions not available from the read-write repository will be
/// fetched from a read-fallback repository and uploaded to the read-write
/// repository. This effectively caches all packages requested through this
/// [CopyAndWriteRepository].
///
/// New package versions which get uploaded will be stored only locally.
class CopyAndWriteRepository extends PackageRepository {
  final PackageRepository local;
  final PackageRepository remote;
  final _RemoteMetadataCache _localCache;
  final _RemoteMetadataCache _remoteCache;
  final bool standalone;

  /// Construct a new proxy with [local] as the local [PackageRepository] which
  /// is used for uploading new package versions to and [remote] as the
  /// read-only [PackageRepository] which is consulted on misses in [local].
  CopyAndWriteRepository(
      PackageRepository local, PackageRepository remote, bool standalone)
      : local = local,
        remote = remote,
        standalone = standalone,
        _localCache = _RemoteMetadataCache(local),
        _remoteCache = _RemoteMetadataCache(remote);

  @override
  Stream<PackageVersion> versions(String package) {
    StreamController<PackageVersion> controller;
    void onListen() {
      var waitList = [_localCache.fetchVersionlist(package)];
      if (standalone != true) {
        waitList.add(_remoteCache.fetchVersionlist(package));
      }
      Future.wait(waitList).then((tuple) {
        var versions = <PackageVersion>{}..addAll(tuple[0]);
        if (standalone != true) {
          versions.addAll(tuple[1]);
        }
        for (var version in versions) {
          controller.add(version);
        }
        controller.close();
      });
    }

    controller = StreamController(onListen: onListen);
    return controller.stream;
  }

  @override
  Future<PackageVersion> lookupVersion(String package, String version) {
    return versions(package)
        .where((pv) => pv.versionString == version)
        .toList()
        .then((List<PackageVersion> versions) {
      if (versions.isNotEmpty) return versions.first;
      return null;
    });
  }

  @override
  Future<Stream<List<int>>> download(String package, String version) async {
    var packageVersion = await local.lookupVersion(package, version);

    if (packageVersion != null) {
      _logger.info('Serving $package/$version from local repository.');
      return local.download(package, packageVersion.versionString);
    } else {
      // We first download the package from the remote repository and store
      // it locally. Then we read the local version and return it.

      _logger.info('Downloading $package/$version from remote repository.');
      var stream = await remote.download(package, version);

      _logger.info('Upload $package/$version to local repository.');
      await local.upload(stream);

      _logger.info('Serving $package/$version from local repository.');
      return local.download(package, version);
    }
  }

  @override
  bool get supportsUpload => true;

  @override
  Future<PackageVersion> upload(Stream<List<int>> data) async {
    _logger.info('Starting upload to local package repository.');
    final pkgVersion = await local.upload(data);
    // TODO: It's not really necessary to invalidate all.
    _logger.info(
        'Upload finished - ${pkgVersion.packageName}@${pkgVersion.version}. '
        'Invalidating in-memory cache.');
    _localCache.invalidateAll();
    return pkgVersion;
  }

  @override
  bool get supportsAsyncUpload => false;
}

/// A cache for [PackageVersion] objects for a given `package`.
///
/// The constructor takes a [PackageRepository] which will be used to populate
/// the cache.
class _RemoteMetadataCache {
  final PackageRepository remote;

  final Map<String, Set<PackageVersion>> _versions = {};
  final Map<String, Completer<Set<PackageVersion>>> _versionCompleters = {};

  _RemoteMetadataCache(this.remote);

  // TODO: After a cache expiration we should invalidate entries and re-fetch
  // them.
  Future<List<PackageVersion>> fetchVersionlist(String package) {
    return _versionCompleters
        .putIfAbsent(package, () {
          var c = Completer<Set<PackageVersion>>();

          _versions.putIfAbsent(package, () => <PackageVersion>{});
          remote.versions(package).toList().then((versions) {
            _versions[package].addAll(versions);
            c.complete(_versions[package]);
          });

          return c;
        })
        .future
        .then((set) => set.toList());
  }

  void addVersion(String package, PackageVersion version) {
    _versions
        .putIfAbsent(version.packageName, () => <PackageVersion>{})
        .add(version);
  }

  void invalidateAll() {
    _versionCompleters.clear();
    _versions.clear();
  }
}
