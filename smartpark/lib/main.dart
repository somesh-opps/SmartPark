import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const SmartParkApp());
}

class SmartParkApp extends StatelessWidget {
  const SmartParkApp({super.key, this.repository});

  final SensorRepository? repository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SmartPark',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFFF2F7F3),
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF117A56)),
        useMaterial3: true,
      ),
      home: DashboardScreen(repository: repository),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, this.repository});

  final SensorRepository? repository;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const Duration _autoRefreshInterval = Duration(seconds: 4);

  late SensorRepository _repository;
  late DashboardSnapshot _snapshot;
  Timer? _autoRefreshTimer;
  bool _isLive = false;
  bool _isRefreshing = false;
  String? _errorMessage;
  String _activeBaseUrl = '';

  @override
  void initState() {
    super.initState();
    // Initialize with API server (which fetches from Firebase)
    _repository = widget.repository ?? ApiSensorRepository();
    if (_repository is ApiSensorRepository) {
      _activeBaseUrl = (_repository as ApiSensorRepository).baseUrl;
    }
    _snapshot = DashboardSnapshot(slots: const <SlotItem>[], lastUpdated: DateTime.now());
    
    // Start with API server
    _initializeRepository();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(_autoRefreshInterval, (_) {
      if (!mounted) {
        return;
      }
      _refreshFromApi(forceRefresh: false);
    });
  }

  Future<void> _initializeRepository() async {
    final String? savedBaseUrl = await ApiEndpointStore.readBaseUrl();
    if (savedBaseUrl != null && savedBaseUrl.trim().isNotEmpty) {
      _repository = ApiSensorRepository(baseUrl: savedBaseUrl);
      _activeBaseUrl = (_repository as ApiSensorRepository).baseUrl;
    } else {
      // Use the default URL based on platform
      _repository = ApiSensorRepository(baseUrl: ApiSensorRepository._defaultBaseUrl());
      _activeBaseUrl = (_repository as ApiSensorRepository).baseUrl;
    }
    if (mounted) {
      setState(() {});
    }
    await _refreshFromApi(forceRefresh: true);
  }



  Future<void> _showServerConfigDialog() async {
    if (widget.repository != null) {
      return;
    }

    final TextEditingController controller = TextEditingController(text: _activeBaseUrl);
    final String? enteredUrl = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Server URL'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              hintText: 'http://10.145.88.180:8000',
              helperText: 'Use your computer LAN IP for real phone.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text.trim()),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (enteredUrl == null) {
      return;
    }

    final String? normalizedUrl = _normalizeServerUrl(enteredUrl);
    if (normalizedUrl == null) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid URL like http://10.145.88.180:8000')),
      );
      return;
    }

    await ApiEndpointStore.writeBaseUrl(normalizedUrl);
    _repository = ApiSensorRepository(baseUrl: normalizedUrl);
    if (!mounted) {
      return;
    }
    setState(() {
      _activeBaseUrl = (_repository as ApiSensorRepository).baseUrl;
      _errorMessage = null;
    });
    await _refreshFromApi(forceRefresh: true);
  }

  String? _normalizeServerUrl(String input) {
    final String trimmed = input.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    final String withScheme =
        trimmed.startsWith('http://') || trimmed.startsWith('https://') ? trimmed : 'http://$trimmed';
    final Uri? uri = Uri.tryParse(withScheme);
    if (uri == null || !uri.hasScheme || uri.host.trim().isEmpty) {
      return null;
    }

    if (uri.port == 0) {
      final int defaultPort = uri.scheme == 'https' ? 443 : 8000;
      return '${uri.scheme}://${uri.host}:$defaultPort';
    }
    return '${uri.scheme}://${uri.host}:${uri.port}';
  }

  Future<void> _refreshFromApi({required bool forceRefresh}) async {
    if (_isRefreshing) {
      return;
    }

    if (mounted) {
      setState(() {
        _isRefreshing = true;
      });
    }

    try {
      final DashboardSnapshot latest = await _repository.fetchSnapshot(forceRefresh: forceRefresh);
      if (!mounted) {
        return;
      }
      setState(() {
        _snapshot = latest;
        _isLive = true;
        _errorMessage = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _snapshot = DashboardSnapshot(slots: const <SlotItem>[], lastUpdated: DateTime.now());
        _isLive = false;
        _errorMessage = error is ServerConnectionException
            ? error.message
            : 'Unable to refresh parking data right now. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  int get _freeCount => _snapshot.slots.where((slot) => slot.isFree).length;

  int get _occupiedCount => _snapshot.slots.length - _freeCount;

  double get _availabilityRate {
    if (_snapshot.slots.isEmpty) {
      return 0;
    }
    return _freeCount / _snapshot.slots.length;
  }

  @override
  Widget build(BuildContext context) {
    final DateTime now = DateTime.now();
    final Duration elapsed = now.difference(_snapshot.lastUpdated);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 14, 12, 24),
                children: [
                  _TopBar(
                    now: now,
                    onRefresh: _refreshFromApi,
                    isRefreshing: _isRefreshing,
                    onConfigureServer: _showServerConfigDialog,
                  ),
                  const SizedBox(height: 14),
                  if (_errorMessage != null) ...[
                    _ConnectionErrorCard(
                      message: _errorMessage!,
                      activeBaseUrl: _activeBaseUrl,
                      onConfigureServer: _showServerConfigDialog,
                    ),
                    const SizedBox(height: 12),
                  ],
                  _AvailabilityCard(
                    freeCount: _freeCount,
                    totalCount: _snapshot.slots.length,
                    occupiedCount: _occupiedCount,
                    availabilityRate: _availabilityRate,
                    isLive: _isLive,
                  ),
                  const SizedBox(height: 16),
                  if (_snapshot.slots.isEmpty)
                    const _NoDataCard()
                  else
                    ..._snapshot.slots.map((slot) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _SlotCard(slot: slot),
                        )),
                  const SizedBox(height: 10),
                  _FooterStatsCard(
                    freeCount: _freeCount,
                    occupiedCount: _occupiedCount,
                    age: elapsed,
                    hasData: _snapshot.slots.isNotEmpty,
                  ),
                  const SizedBox(height: 18),
                  Center(
                    child: Text(
                      'FIREBASE VIA API SERVER',
                      style: const TextStyle(
                        fontSize: 12,
                        letterSpacing: 3,
                        color: Color(0xFF5F7C72),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.now,
    required this.onRefresh,
    required this.isRefreshing,
    required this.onConfigureServer,
  });

  final DateTime now;
  final Future<void> Function({required bool forceRefresh}) onRefresh;
  final bool isRefreshing;
  final VoidCallback onConfigureServer;

  String _formatTime(DateTime dateTime) {
    final int hour12 = dateTime.hour == 0 ? 12 : (dateTime.hour > 12 ? dateTime.hour - 12 : dateTime.hour);
    final String minute = dateTime.minute.toString().padLeft(2, '0');
    final String period = dateTime.hour >= 12 ? 'PM' : 'AM';
    return '$hour12:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool compact = constraints.maxWidth < 370;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'SmartPark',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF0F5C42),
                      fontSize: compact ? 30 : 34,
                      height: 1,
                    ),
                  ),
                ),
              ),
              if (!compact) ...[
                Text(
                  _formatTime(now),
                  style: const TextStyle(
                    color: Color(0xFF0F5C42),
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(width: 2),
              ],
              IconButton(
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                padding: EdgeInsets.zero,
                onPressed: onConfigureServer,
                tooltip: 'Server URL',
                icon: const Icon(Icons.settings_ethernet_rounded, color: Color(0xFF0F5C42)),
              ),
              IconButton(
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                padding: EdgeInsets.zero,
                onPressed: isRefreshing ? null : () => onRefresh(forceRefresh: true),
                tooltip: 'Refresh',
                icon: isRefreshing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      )
                    : const Icon(Icons.refresh_rounded, color: Color(0xFF0F5C42)),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AvailabilityCard extends StatelessWidget {
  const _AvailabilityCard({
    required this.freeCount,
    required this.totalCount,
    required this.occupiedCount,
    required this.availabilityRate,
    required this.isLive,
  });

  final int freeCount;
  final int totalCount;
  final int occupiedCount;
  final double availabilityRate;
  final bool isLive;

  @override
  Widget build(BuildContext context) {
    final int percent = (availabilityRate * 100).round();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F22223A),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          const Text(
            'CURRENT AVAILABILITY',
            style: TextStyle(
              fontSize: 14,
              letterSpacing: 3,
              color: Color(0xFF1D4638),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(
              text: '$freeCount',
              style: const TextStyle(
                fontSize: 74,
                fontWeight: FontWeight.w700,
                color: Color(0xFF198A62),
                height: 1,
              ),
              children: [
                TextSpan(
                  text: ' of $totalCount',
                  style: const TextStyle(
                    fontSize: 74,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF198A62),
                  ),
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          const Text(
            'slots available',
            style: TextStyle(
              fontSize: 56,
              color: Color(0xFF198A62),
              fontWeight: FontWeight.w500,
              height: 1,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          _LivePulseBadge(isLive: isLive),
          const SizedBox(height: 14),
          Text(
            'Occupied: $occupiedCount  •  Availability: $percent%',
            style: const TextStyle(
              fontSize: 12,
              letterSpacing: 0.6,
              color: Color(0xFF4D6F63),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _LivePulseBadge extends StatelessWidget {
  const _LivePulseBadge({required this.isLive});

  final bool isLive;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFE4F4EC),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 10, color: Color(0xFF0E6B4C)),
          const SizedBox(width: 8),
          Text(
            isLive ? 'LIVE SYSTEM PULSE' : 'NO DATA AVAILABLE',
            style: const TextStyle(
              color: Color(0xFF0E6B4C),
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _NoDataCard extends StatelessWidget {
  const _NoDataCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Column(
        children: [
          Icon(Icons.sensors_off_rounded, size: 28, color: Color(0xFF6E8C82)),
          SizedBox(height: 10),
          Text(
            'NO DATA AVAILABLE',
            style: TextStyle(
              fontSize: 14,
              letterSpacing: 1.8,
              color: Color(0xFF3E5D53),
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Waiting for backend slot updates from /sensors',
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF6E8C82),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionErrorCard extends StatelessWidget {
  const _ConnectionErrorCard({
    required this.message,
    required this.activeBaseUrl,
    required this.onConfigureServer,
  });

  final String message;
  final String activeBaseUrl;
  final VoidCallback onConfigureServer;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF6EF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFB7DBCA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(Icons.wifi_off_rounded, size: 18, color: Color(0xFF2C7258)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF2C5E4C),
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Current server: $activeBaseUrl',
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF2C5E4C),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onConfigureServer,
            icon: const Icon(Icons.edit_rounded, size: 16),
            label: const Text('Change Server URL'),
          ),
        ],
      ),
    );
  }
}

class _SlotCard extends StatelessWidget {
  const _SlotCard({required this.slot});

  final SlotItem slot;

  String _formatTime(DateTime timestamp) {
    final int hour12 = timestamp.hour == 0 ? 12 : (timestamp.hour > 12 ? timestamp.hour - 12 : timestamp.hour);
    final String minute = timestamp.minute.toString().padLeft(2, '0');
    final String period = timestamp.hour >= 12 ? 'PM' : 'AM';
    return '$hour12:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    final bool disabled = !slot.isFree;
    final Color borderColor = disabled ? const Color(0xFFC5DED2) : const Color(0xFFBDE2D4);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor, width: 1.2),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                height: 40,
                width: 40,
                decoration: BoxDecoration(
                  color: disabled ? const Color(0xFFE5EFEA) : const Color(0xFFE4F5ED),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: disabled
                      ? const Icon(Icons.directions_car_filled, color: Color(0xFF2E6E5A), size: 20)
                      : const Icon(Icons.local_parking_rounded, color: Color(0xFF117A56), size: 22),
                ),
              ),
              const Spacer(),
              _StatusPill(isFree: slot.isFree),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Slot ${slot.number}',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: disabled ? const Color(0xFF355D4E) : const Color(0xFF0B4633),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${slot.area} · Updated ${_formatTime(slot.lastSeen)}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: disabled ? const Color(0xFF5D7D72) : const Color(0xFF3D5C53),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.isFree});

  final bool isFree;

  @override
  Widget build(BuildContext context) {
    final Color textColor = isFree ? const Color(0xFF0E6B4C) : const Color(0xFF2E6E5A);
    final Color bgColor = isFree ? const Color(0xFFDDF4EA) : const Color(0xFFE2EEE8);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 6, color: textColor),
          const SizedBox(width: 5),
          Text(
            isFree ? 'FREE' : 'OCCUPIED',
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _FooterStatsCard extends StatelessWidget {
  const _FooterStatsCard({
    required this.freeCount,
    required this.occupiedCount,
    required this.age,
    required this.hasData,
  });

  final int freeCount;
  final int occupiedCount;
  final Duration age;
  final bool hasData;

  String get _ageLabel {
    if (!hasData) {
      return '--';
    }
    final int seconds = age.inSeconds;
    if (seconds < 60) {
      return '${seconds}s';
    }
    final int minutes = age.inMinutes;
    return '${minutes}m';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF3EE),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _CountColumn(label: 'FREE', value: '$freeCount', valueColor: const Color(0xFF198A62)),
              const SizedBox(width: 30),
              const SizedBox(height: 42, child: VerticalDivider(color: Color(0xFFC3D7CE), width: 1)),
              const SizedBox(width: 30),
              _CountColumn(label: 'OCCUPIED', value: '$occupiedCount', valueColor: const Color(0xFF2E6E5A)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.refresh, size: 13, color: Color(0xFF2A5445)),
              const SizedBox(width: 8),
              Text(
                'LAST UPDATED: ${_ageLabel.toUpperCase()} AGO',
                style: const TextStyle(
                  fontSize: 11,
                  letterSpacing: 2,
                  color: Color(0xFF2A5445),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          )
        ],
      ),
    );
  }
}

class _CountColumn extends StatelessWidget {
  const _CountColumn({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            letterSpacing: 1.5,
            fontWeight: FontWeight.w700,
            color: Color(0xFF294E41),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 34,
            height: 1,
            fontWeight: FontWeight.w700,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

class SlotItem {
  const SlotItem({
    required this.id,
    required this.number,
    required this.area,
    required this.isFree,
    required this.lastSeen,
  });

  final String id;
  final int number;
  final String area;
  final bool isFree;
  final DateTime lastSeen;
}

class DashboardSnapshot {
  const DashboardSnapshot({required this.slots, required this.lastUpdated});

  final List<SlotItem> slots;
  final DateTime lastUpdated;
}

abstract class SensorRepository {
  Future<DashboardSnapshot> fetchSnapshot({required bool forceRefresh});
}

class ApiSensorRepository implements SensorRepository {
  ApiSensorRepository({String? baseUrl})
    : _baseUri = Uri.parse(
        baseUrl ??
            (() {
              const String envBase = String.fromEnvironment('API_BASE_URL', defaultValue: '');
              return envBase.trim().isNotEmpty ? envBase.trim() : _defaultBaseUrl();
            })(),
      );

  final Uri _baseUri;

  String get baseUrl => '${_baseUri.scheme}://${_baseUri.host}:${_baseUri.port}';

  @override
  Future<DashboardSnapshot> fetchSnapshot({required bool forceRefresh}) async {
    final Map<String, String> queryParameters = <String, String>{'limit': '200'};
    if (forceRefresh) {
      queryParameters['_t'] = DateTime.now().millisecondsSinceEpoch.toString();
    }

    final Uri uri = _baseUri.replace(path: '/sensors', queryParameters: queryParameters);
    late final http.Response response;
    try {
      response = await http
          .get(
            uri,
            headers: forceRefresh ? const <String, String>{'Cache-Control': 'no-cache'} : null,
          )
          .timeout(const Duration(seconds: 8));
    } on TimeoutException {
      throw ServerConnectionException(_connectionHelpMessage(uri));
    } on http.ClientException {
      throw ServerConnectionException(_connectionHelpMessage(uri));
    }

    if (response.statusCode != 200) {
      throw Exception('Backend error (${response.statusCode}): ${response.body}');
    }

    final dynamic decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Unexpected response format');
    }

    final dynamic items = decoded['items'];
    if (items is! List) {
      throw Exception('Missing items list in response');
    }

    final Map<int, SlotItem> bySlot = <int, SlotItem>{};
    for (final dynamic raw in items) {
      if (raw is! Map<String, dynamic>) {
        continue;
      }
      final int? slotNumber = _extractSlotNumber(raw);
      if (slotNumber == null || bySlot.containsKey(slotNumber)) {
        continue;
      }
      bySlot[slotNumber] = SlotItem(
        id: raw['_id']?.toString() ?? raw['id']?.toString() ?? 'unknown_$slotNumber',
        number: slotNumber,
        area: _extractArea(raw),
        isFree: _extractIsFree(raw),
        lastSeen: _extractTimestamp(raw),
      );
    }

    if (bySlot.isEmpty) {
      return DashboardSnapshot(slots: const <SlotItem>[], lastUpdated: DateTime.now());
    }

    final List<SlotItem> slots = bySlot.values.toList()..sort((a, b) => a.number.compareTo(b.number));
    return DashboardSnapshot(slots: slots, lastUpdated: DateTime.now());
  }

  static String _defaultBaseUrl() {
    if (kIsWeb) {
      return 'http://localhost:8000';
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.145.88.180:8000';  // Computer LAN IP
    }
    return 'http://localhost:8000';
  }

  static String _connectionHelpMessage(Uri uri) {
    final StringBuffer buffer = StringBuffer(
      'Cannot connect to server at ${uri.scheme}://${uri.host}:${uri.port}.',
    );

    if (defaultTargetPlatform == TargetPlatform.android && uri.host == '10.0.2.2') {
      buffer.write(' If you are using a real Android phone, use your computer LAN IP with '
          '--dart-define=API_BASE_URL=http://<your-ip>:8000.');
    }

    return buffer.toString();
  }

  static int? _extractSlotNumber(Map<String, dynamic> doc) {
    final List<String> keys = <String>['number', 'slot_number', 'slot', 'slotId', 'slot_id'];
    for (final String key in keys) {
      final int? parsed = _toInt(doc[key]);
      if (parsed != null) {
        return parsed;
      }
    }

    final dynamic idValue = doc['id'];
    if (idValue != null) {
      final RegExpMatch? idMatch = RegExp(r'(\d+)').firstMatch(idValue.toString());
      if (idMatch != null) {
        return int.tryParse(idMatch.group(1)!);
      }
    }

    final String? device = doc['device_id']?.toString();
    if (device == null) {
      return null;
    }
    final RegExpMatch? match = RegExp(r'(\d+)').firstMatch(device);
    if (match == null) {
      return null;
    }
    return int.tryParse(match.group(1)!);
  }

  static String _extractArea(Map<String, dynamic> doc) {
    final List<String> keys = <String>['area', 'location', 'zone', 'name'];
    for (final String key in keys) {
      final dynamic value = doc[key];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString();
      }
    }
    return 'Unknown Area';
  }

  static bool _extractIsFree(Map<String, dynamic> doc) {
    final dynamic freeValue = doc['isFree'] ?? doc['is_free'] ?? doc['free'] ?? doc['available'];
    final bool? explicitFree = _toBool(freeValue);
    if (explicitFree != null) {
      return explicitFree;
    }

    final bool? occupied = _toBool(doc['occupied']);
    if (occupied != null) {
      return !occupied;
    }

    final String? status = doc['status']?.toString().toLowerCase();
    if (status == 'free' || status == 'available') {
      return true;
    }
    if (status == 'occupied' || status == 'busy') {
      return false;
    }

    return false;
  }

  static DateTime _extractTimestamp(Map<String, dynamic> doc) {
    final dynamic value = doc['timestamp'] ?? doc['last_seen'] ?? doc['updated_at'];
    if (value == null) {
      return DateTime.now();
    }
    if (value is String) {
      final DateTime? parsed = DateTime.tryParse(value);
      if (parsed != null) {
        return parsed;
      }
      return DateTime.now();
    }
    if (value is int) {
      if (value > 9999999999) {
        return DateTime.fromMillisecondsSinceEpoch(value);
      }
      return DateTime.fromMillisecondsSinceEpoch(value * 1000);
    }
    return DateTime.now();
  }

  static int? _toInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is double) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  static bool? _toBool(dynamic value) {
    if (value is bool) {
      return value;
    }
    if (value is int) {
      return value != 0;
    }
    if (value is String) {
      final String normalized = value.toLowerCase().trim();
      if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
        return true;
      }
      if (normalized == 'false' || normalized == '0' || normalized == 'no') {
        return false;
      }
    }
    return null;
  }
}

class ServerConnectionException implements Exception {
  ServerConnectionException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ApiEndpointStore {
  static const String _keyApiBaseUrl = 'api_base_url';

  static Future<String?> readBaseUrl() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? value = prefs.getString(_keyApiBaseUrl);
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    return value;
  }

  static Future<void> writeBaseUrl(String value) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyApiBaseUrl, value);
  }
}
