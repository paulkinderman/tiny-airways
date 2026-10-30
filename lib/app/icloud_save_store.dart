import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../core/save/cloud_sync.dart';

/// The cloud copy of the save in iCloud's key-value store, through the
/// `tiny_airways/icloud` channel in `ios/Runner/AppDelegate.swift`.
///
/// The save is gzipped and base64-encoded: the key-value store holds up to
/// 1 MB, and a save compresses to a small fraction of that. Without an
/// iCloud account (or the iCloud entitlement) [isAvailable] is false and
/// the game just saves locally.
class ICloudSaveStore implements CloudSaveStore {
  const ICloudSaveStore();

  static const _channel = MethodChannel('tiny_airways/icloud');

  @override
  Future<bool> isAvailable() async {
    try {
      return await _channel.invokeMethod<bool>('isAvailable') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<String?> read() async {
    final packed = await _channel.invokeMethod<String>('read');
    if (packed == null || packed.isEmpty) return null;
    return utf8.decode(gzip.decode(base64.decode(packed)));
  }

  @override
  Future<void> write(String text) => _channel.invokeMethod<void>(
    'write',
    base64.encode(gzip.encode(utf8.encode(text))),
  );
}
