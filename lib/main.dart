import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

const AndroidNotificationChannel channel = AndroidNotificationChannel(
  'high_importance_channel',
  'High Importance Notifications',
  description: 'This channel is used for important notifications.',
  importance: Importance.high,
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);
  await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
    alert: true,
    badge: true,
    sound: true,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF0A7AFF);
    const accent = Color(0xFF00A389);
    const surfaceTint = Color(0xFFF3F8FF);

    return MaterialApp(
      title: 'FCM Notification App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF4F7FC),
        colorScheme: const ColorScheme.light(
          primary: primary,
          secondary: accent,
          surface: Colors.white,
          surfaceContainerHighest: surfaceTint,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          foregroundColor: Color(0xFF0E1A2B),
          elevation: 0,
          centerTitle: true,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFFE6EEF9)),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: primary,
          contentTextStyle: const TextStyle(color: Colors.white),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      home: const NotificationHomePage(),
    );
  }
}

class NotificationItem {
  final String title;
  final String body;
  final String source;
  final DateTime time;

  NotificationItem({
    required this.title,
    required this.body,
    required this.source,
    required this.time,
  });
}

class NotificationHomePage extends StatefulWidget {
  const NotificationHomePage({super.key});

  @override
  State<NotificationHomePage> createState() => _NotificationHomePageState();
}

class _NotificationHomePageState extends State<NotificationHomePage>
    with SingleTickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  String _deviceToken = 'Fetching token...';
  bool _tokenLoaded = false;
  bool _tokenVisible = false;
  String _status = 'Waiting for notification...';
  Color _statusColor = const Color(0xFF95A0B3);
  final List<NotificationItem> _history = [];

  late AnimationController _bellController;
  late Animation<double> _bellAnimation;

  @override
  void initState() {
    super.initState();
    _bellController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _bellAnimation = Tween<double>(begin: -0.1, end: 0.1).animate(
      CurvedAnimation(parent: _bellController, curve: Curves.elasticIn),
    );
    _initializeLocalNotifications();
    _requestPermissionAndGetToken();
    _setupForegroundNotificationHandler();
    _setupNotificationOpenedHandler();
  }

  @override
  void dispose() {
    _bellController.dispose();
    super.dispose();
  }

  void _ringBell() {
    _bellController.forward().then((_) => _bellController.reverse());
  }

  void _openNotificationDrawer() {
    _scaffoldKey.currentState?.openEndDrawer();
  }

  void _initializeLocalNotifications() {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    flutterLocalNotificationsPlugin.initialize(
      const InitializationSettings(android: androidSettings),
    );
  }

  Future<void> _requestPermissionAndGetToken() async {
    final messaging = FirebaseMessaging.instance;
    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      setState(() {
        _deviceToken = 'Permission denied. Enable notifications in settings.';
        _statusColor = const Color(0xFFE95454);
      });
      return;
    }

    try {
      final token = await messaging.getToken();
      if (token != null) {
        setState(() {
          _deviceToken = token;
          _tokenLoaded = true;
        });
      }
    } catch (e) {
      setState(() => _deviceToken = 'Error getting token: $e');
    }

    messaging.onTokenRefresh.listen((t) => setState(() => _deviceToken = t));
  }

  void _setupForegroundNotificationHandler() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final notification = message.notification;
      final android = message.notification?.android;

      _ringBell();

      setState(() {
        _status = 'Received in Foreground';
        _statusColor = const Color(0xFF0FA968);
        _history.insert(
          0,
          NotificationItem(
            title: notification?.title ?? 'No title',
            body: notification?.body ?? 'No body',
            source: 'Foreground',
            time: DateTime.now(),
          ),
        );
      });

      if (notification != null && android != null) {
        flutterLocalNotificationsPlugin.show(
          notification.hashCode,
          notification.title,
          notification.body,
          NotificationDetails(
            android: AndroidNotificationDetails(
              channel.id,
              channel.name,
              channelDescription: channel.description,
              importance: Importance.high,
              priority: Priority.high,
              icon: '@mipmap/ic_launcher',
            ),
          ),
        );
      }

      _showNotificationSheet(
        title: notification?.title ?? 'Notification',
        body: notification?.body ?? '',
        source: 'Foreground',
      );
    });
  }

  void _setupNotificationOpenedHandler() {
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) {
        setState(() {
          _status = 'App opened from terminated state';
          _statusColor = const Color(0xFF2E7DFF);
          _history.insert(
            0,
            NotificationItem(
              title: message.notification?.title ?? 'No title',
              body: message.notification?.body ?? 'No body',
              source: 'Terminated',
              time: DateTime.now(),
            ),
          );
        });
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _ringBell();
      setState(() {
        _status = 'Opened from Background';
        _statusColor = const Color(0xFFE39A1A);
        _history.insert(
          0,
          NotificationItem(
            title: message.notification?.title ?? 'No title',
            body: message.notification?.body ?? 'No body',
            source: 'Background',
            time: DateTime.now(),
          ),
        );
      });
    });
  }

  void _showNotificationSheet({
    required String title,
    required String body,
    required String source,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD3DEEE),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEDF4FF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.notifications_active,
                      color: Color(0xFF0A7AFF), size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: Color(0xFF122239),
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              body,
              style: const TextStyle(
                color: Color(0xFF52657E),
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _sourceChip(source),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Dismiss'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _copyToken() {
    Clipboard.setData(ClipboardData(text: _deviceToken));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Token copied to clipboard!')),
    );
  }

  String _formatTime(DateTime time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _maskedToken() {
    if (!_tokenLoaded) {
      return _deviceToken;
    }
    if (_tokenVisible || _deviceToken.length <= 20) {
      return _deviceToken;
    }
    return '${_deviceToken.substring(0, 16)}••••••••••••••••••••';
  }

  Widget _sourceChip(String source) {
    final colors = {
      'Foreground': const Color(0xFF0FA968),
      'Background': const Color(0xFFE39A1A),
      'Terminated': const Color(0xFF2E7DFF),
    };
    final color = colors[source] ?? const Color(0xFF95A0B3);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        source,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildNotificationTile(NotificationItem item, {bool compact = false}) {
    return Container(
      margin: EdgeInsets.only(bottom: compact ? 10 : 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE6EEF9)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: const Color(0xFFEDF4FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              compact ? Icons.mark_email_unread_outlined : Icons.campaign_outlined,
              color: const Color(0xFF0A7AFF),
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: const TextStyle(
                    color: Color(0xFF10243D),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.body,
                  style: const TextStyle(
                    color: Color(0xFF5A6E87),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _sourceChip(item.source),
                    const SizedBox(width: 8),
                    Text(
                      _formatTime(item.time),
                      style: const TextStyle(
                        color: Color(0xFF8A9AB1),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationDrawer() {
    return Drawer(
      width: MediaQuery.of(context).size.width * 0.88,
      backgroundColor: Colors.white,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEDF4FF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.notifications_active,
                        color: Color(0xFF0A7AFF)),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Notification Drawer',
                      style: TextStyle(
                        color: Color(0xFF0F2239),
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFF0F8FF), Color(0xFFF6FFF7)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _history.isEmpty
                      ? 'No alerts yet. New notifications will appear here.'
                      : '${_history.length} notification${_history.length == 1 ? '' : 's'} received',
                  style: const TextStyle(
                    color: Color(0xFF4D607B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (_history.isNotEmpty)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => setState(_history.clear),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Clear all'),
                  ),
                ),
              const SizedBox(height: 4),
              Expanded(
                child: _history.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.notifications_none,
                                color: Color(0xFF9CADC4), size: 44),
                            SizedBox(height: 10),
                            Text(
                              'Your drawer is clean',
                              style: TextStyle(
                                color: Color(0xFF71839B),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _history.length,
                        itemBuilder: (_, i) => _buildNotificationTile(
                          _history[i],
                          compact: true,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      endDrawer: _buildNotificationDrawer(),
      appBar: AppBar(
        title: const Text(
          'Notification Center',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: AnimatedBuilder(
              animation: _bellAnimation,
              builder: (_, child) => Transform.rotate(
                angle: _bellAnimation.value,
                child: child,
              ),
              child: Stack(
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications_rounded),
                    onPressed: _openNotificationDrawer,
                    tooltip: 'Open notifications',
                  ),
                  if (_history.isNotEmpty)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        constraints:
                            const BoxConstraints(minWidth: 16, minHeight: 16),
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: const BoxDecoration(
                          color: Color(0xFFE95454),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          _history.length > 9 ? '9+' : '${_history.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF7FAFF), Color(0xFFEFF5FF)],
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF0A7AFF), Color(0xFF00A389)],
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0A7AFF).withOpacity(0.28),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    AnimatedBuilder(
                      animation: _bellAnimation,
                      builder: (_, child) => Transform.rotate(
                        angle: _bellAnimation.value,
                        child: child,
                      ),
                      child: const Icon(Icons.notifications_active_rounded,
                          color: Colors.white, size: 52),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'FCM Push Dashboard',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: _statusColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _status,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.vpn_key_rounded,
                              color: Color(0xFF0A7AFF), size: 18),
                          const SizedBox(width: 8),
                          const Text(
                            'Device Token',
                            style: TextStyle(
                              color: Color(0xFF11243C),
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                          const Spacer(),
                          if (_tokenLoaded)
                            TextButton(
                              onPressed: () =>
                                  setState(() => _tokenVisible = !_tokenVisible),
                              child: Text(_tokenVisible ? 'Hide' : 'Reveal'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FBFF),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE6EEF9)),
                        ),
                        child: Text(
                          _maskedToken(),
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            color: Color(0xFF2E4D73),
                            fontSize: 11,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _tokenLoaded ? _copyToken : null,
                          icon: const Icon(Icons.copy_rounded, size: 18),
                          label: const Text('Copy Token'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.history_rounded,
                              color: Color(0xFF0A7AFF), size: 18),
                          const SizedBox(width: 8),
                          const Text(
                            'Recent Notifications',
                            style: TextStyle(
                              color: Color(0xFF11243C),
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: _openNotificationDrawer,
                            child: const Text('Open drawer'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (_history.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 26),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FBFF),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Column(
                            children: [
                              Icon(Icons.notifications_none_rounded,
                                  color: Color(0xFFA1B0C5), size: 38),
                              SizedBox(height: 8),
                              Text(
                                'No notifications yet',
                                style: TextStyle(
                                  color: Color(0xFF7E8EA5),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        Column(
                          children: _history
                              .take(3)
                              .map((item) => _buildNotificationTile(item))
                              .toList(),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Card(
                child: ExpansionTile(
                  leading: const Icon(Icons.science_outlined,
                      color: Color(0xFF0A7AFF)),
                  title: const Text(
                    'How to Send a Test',
                    style: TextStyle(
                      color: Color(0xFF11243C),
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                  iconColor: const Color(0xFF0A7AFF),
                  collapsedIconColor: const Color(0xFF7E8EA5),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                      child: Column(
                        children: [
                          _buildStep('1', 'Copy your device token above'),
                          _buildStep('2', 'Go to Firebase Console -> Messaging'),
                          _buildStep('3', 'Click "Send your first message"'),
                          _buildStep('4', 'Enter a title and body'),
                          _buildStep('5', 'Click "Send test message"'),
                          _buildStep('6', 'Paste token -> Add -> Test'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep(String number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Color(0xFF0A7AFF),
              shape: BoxShape.circle,
            ),
            child: Text(
              number,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFF536985),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}