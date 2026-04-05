import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
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
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
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
    return MaterialApp(
      title: 'FCM Notification App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F0F1A),
        colorScheme: ColorScheme.dark(
          primary: const Color(0xFF7C4DFF),
          secondary: const Color(0xFF03DAC6),
          surface: const Color(0xFF1A1A2E),
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF1A1A2E),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF2A2A3E), width: 1),
          ),
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
  String _deviceToken = 'Fetching token...';
  bool _tokenLoaded = false;
  bool _tokenVisible = false;
  String _status = 'Waiting for notification...';
  Color _statusColor = Colors.grey;
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
        _statusColor = Colors.red;
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
        _statusColor = const Color(0xFF00E676);
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
          _statusColor = const Color(0xFF448AFF);
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
        _statusColor = const Color(0xFFFFD740);
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
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
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
                    color: const Color(0xFF7C4DFF).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.notifications_active,
                      color: Color(0xFF7C4DFF), size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(body,
                style: const TextStyle(fontSize: 15, color: Colors.white70)),
            const SizedBox(height: 16),
            Row(
              children: [
                _sourceChip(source),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Dismiss',
                      style: TextStyle(color: Color(0xFF7C4DFF))),
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
      SnackBar(
        content: const Text('Token copied to clipboard!'),
        backgroundColor: const Color(0xFF7C4DFF),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _sourceChip(String source) {
    final colors = {
      'Foreground': const Color(0xFF00E676),
      'Background': const Color(0xFFFFD740),
      'Terminated': const Color(0xFF448AFF),
    };
    final color = colors[source] ?? Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(source,
          style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F1A),
        elevation: 0,
        title: const Text('FCM Notifications',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        centerTitle: true,
        actions: [
          AnimatedBuilder(
            animation: _bellAnimation,
            builder: (_, child) => Transform.rotate(
              angle: _bellAnimation.value,
              child: child,
            ),
            child: Stack(
              children: [
                IconButton(
                  icon: const Icon(Icons.notifications_outlined),
                  onPressed: null,
                ),
                if (_history.isNotEmpty)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: const BoxDecoration(
                        color: Color(0xFF7C4DFF),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '${_history.length > 9 ? '9+' : _history.length}',
                          style: const TextStyle(
                              fontSize: 9, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Hero Header ──────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF7C4DFF), Color(0xFF3D1A8E)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF7C4DFF).withOpacity(0.4),
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
                    child: const Icon(Icons.notifications_active,
                        color: Colors.white, size: 52),
                  ),
                  const SizedBox(height: 10),
                  const Text('Firebase Cloud Messaging',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
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
                        Text(_status,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.vpn_key,
                            color: Color(0xFF7C4DFF), size: 18),
                        const SizedBox(width: 8),
                        const Text('Device Token',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14)),
                        const Spacer(),
                        if (_tokenLoaded)
                          GestureDetector(
                            onTap: () =>
                                setState(() => _tokenVisible = !_tokenVisible),
                            child: Text(
                              _tokenVisible ? 'Hide' : 'Reveal',
                              style: const TextStyle(
                                  color: Color(0xFF7C4DFF), fontSize: 12),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F0F1A),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF2A2A3E)),
                      ),
                      child: Text(
                        _tokenLoaded && !_tokenVisible
                            ? '${_deviceToken.substring(0, 12)}••••••••••••••••••••••••••••••••'
                            : _deviceToken,
                        style: const TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: Color(0xFF03DAC6),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _tokenLoaded ? _copyToken : null,
                        icon: const Icon(Icons.copy, size: 16),
                        label: const Text('Copy Token'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF7C4DFF),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.history,
                            color: Color(0xFF7C4DFF), size: 18),
                        const SizedBox(width: 8),
                        const Text('Notification History',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14)),
                        const Spacer(),
                        if (_history.isNotEmpty)
                          GestureDetector(
                            onTap: () => setState(() => _history.clear()),
                            child: const Text('Clear',
                                style: TextStyle(
                                    color: Colors.redAccent, fontSize: 12)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_history.isEmpty)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Column(
                            children: [
                              Icon(Icons.notifications_none,
                                  color: Colors.white24, size: 40),
                              SizedBox(height: 8),
                              Text('No notifications yet',
                                  style: TextStyle(
                                      color: Colors.white38, fontSize: 13)),
                            ],
                          ),
                        ),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _history.length,
                        separatorBuilder: (_, __) => const Divider(
                            height: 1, color: Color(0xFF2A2A3E)),
                        itemBuilder: (_, i) {
                          final item = _history[i];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF7C4DFF)
                                        .withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(
                                      Icons.notifications_active,
                                      color: Color(0xFF7C4DFF),
                                      size: 18),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(item.title,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 13)),
                                      const SizedBox(height: 2),
                                      Text(item.body,
                                          style: const TextStyle(
                                              color: Colors.white54,
                                              fontSize: 12)),
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          _sourceChip(item.source),
                                          const SizedBox(width: 8),
                                          Text(
                                            '${item.time.hour.toString().padLeft(2, '0')}:${item.time.minute.toString().padLeft(2, '0')}',
                                            style: const TextStyle(
                                                color: Colors.white38,
                                                fontSize: 11),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            Card(
              child: ExpansionTile(
                leading: const Icon(Icons.science_outlined,
                    color: Color(0xFF7C4DFF)),
                title: const Text('How to Send a Test',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                iconColor: const Color(0xFF7C4DFF),
                collapsedIconColor: Colors.white38,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      children: [
                        _buildStep('1', 'Copy your device token above'),
                        _buildStep('2', 'Go to Firebase Console → Messaging'),
                        _buildStep('3', 'Click "Send your first message"'),
                        _buildStep('4', 'Enter a title and body'),
                        _buildStep('5', 'Click "Send test message"'),
                        _buildStep('6', 'Paste your token → Add → Test'),
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
              color: Color(0xFF7C4DFF),
              shape: BoxShape.circle,
            ),
            child: Text(number,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 10),
          Expanded(
              child: Text(text,
                  style:
                      const TextStyle(fontSize: 13, color: Colors.white70))),
        ],
      ),
    );
  }
}
