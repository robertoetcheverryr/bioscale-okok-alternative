// TEMPORARY: BLE debug screen. Remove before opening the PR.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../services/ble_constants.dart';

class BleDebugScreen extends StatefulWidget {
  const BleDebugScreen({super.key});

  @override
  State<BleDebugScreen> createState() => _BleDebugScreenState();
}

class _BleDebugScreenState extends State<BleDebugScreen> {
  final Map<String, ScanResult> _results = {};
  StreamSubscription<List<ScanResult>>? _sub;
  StreamSubscription<bool>? _scanningSub;
  bool _scanning = false;
  bool _fineLocation = true;
  String _status = 'idle';

  @override
  void dispose() {
    _sub?.cancel();
    _scanningSub?.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  Future<void> _start() async {
    _results.clear();
    setState(() => _status = 'starting');
    try {
      final adapter = await FlutterBluePlus.adapterState.first;
      _status = 'adapter=$adapter';
      _sub?.cancel();
      _sub = FlutterBluePlus.onScanResults.listen((list) {
        for (final r in list) {
          _results[r.device.remoteId.str] = r;
        }
        if (mounted) setState(() {});
      }, onError: (e) => setState(() => _status = 'scan error: $e'));
      _scanningSub?.cancel();
      _scanningSub = FlutterBluePlus.isScanning.listen((s) {
        if (mounted) setState(() => _scanning = s);
      });
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 30),
        androidUsesFineLocation: _fineLocation,
        continuousUpdates: true,
      );
    } catch (e) {
      setState(() => _status = 'startScan threw: $e');
    }
  }

  String _hex(List<int> b) =>
      b.map((x) => x.toRadixString(16).padLeft(2, '0')).join(' ');

  String _name(ScanResult r) => r.advertisementData.advName.isNotEmpty
      ? r.advertisementData.advName
      : r.device.platformName;

  bool _wouldMatch(ScanResult r) {
    final n = _name(r).toLowerCase();
    final byName = n.isNotEmpty &&
        BleConstants.chipseaDeviceNamePrefixes
            .any((p) => n.contains(p.toLowerCase()));
    final byUuid = r.advertisementData.serviceUuids.any((u) =>
        u == BleConstants.chipseaServiceUuid ||
        u == BleConstants.chipseaV2ServiceUuid);
    return byName || byUuid;
  }

  String _describe(ScanResult r) {
    final a = r.advertisementData;
    final b = StringBuffer()
      ..writeln('id=${r.device.remoteId.str} rssi=${r.rssi} '
          'connectable=${a.connectable} match=${_wouldMatch(r)}')
      ..writeln('advName="${a.advName}" platformName="${r.device.platformName}"')
      ..writeln('uuids=${a.serviceUuids.map((u) => u.str).join(",")}');
    a.manufacturerData.forEach((k, v) => b.writeln(
        'mfr 0x${k.toRadixString(16).padLeft(4, '0')} (${v.length}B): ${_hex(v)}'));
    a.serviceData.forEach((k, v) => b.writeln('svc ${k.str}: ${_hex(v)}'));
    return b.toString();
  }

  List<ScanResult> get _sorted => _results.values.toList()
    ..sort((x, y) {
      final m = (_wouldMatch(y) ? 1 : 0) - (_wouldMatch(x) ? 1 : 0);
      return m != 0 ? m : y.rssi.compareTo(x.rssi);
    });

  @override
  Widget build(BuildContext context) {
    final items = _sorted;
    return Scaffold(
      appBar: AppBar(
        title: Text('BLE debug (${items.length})'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copy all',
            onPressed: () {
              final text = 'status=$_status scanning=$_scanning '
                      'fineLocation=$_fineLocation\n\n' +
                  items.map(_describe).join('\n');
              Clipboard.setData(ClipboardData(text: text));
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Copied')));
            },
          ),
        ],
      ),
      body: Column(
        children: [
          SwitchListTile(
            title: const Text('androidUsesFineLocation'),
            value: _fineLocation,
            onChanged: _scanning
                ? null
                : (v) => setState(() => _fineLocation = v),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                ElevatedButton(
                  onPressed: _scanning ? FlutterBluePlus.stopScan : _start,
                  child: Text(_scanning ? 'Stop' : 'Scan 30 s'),
                ),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(_status,
                        style: const TextStyle(fontSize: 12))),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              itemCount: items.length,
              itemBuilder: (_, i) {
                final r = items[i];
                return Container(
                  color: _wouldMatch(r) ? Colors.green.withValues(alpha: 0.15) : null,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: SelectableText(
                    '${_name(r).isEmpty ? "(no name)" : _name(r)}\n${_describe(r)}',
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
