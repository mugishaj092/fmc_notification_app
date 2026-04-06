import 'package:flutter_test/flutter_test.dart';

import 'package:fcm_notification_app/main.dart';

void main() {
  test('NotificationItem stores notification data', () {
    final now = DateTime.now();
    final item = NotificationItem(
      title: 'Welcome',
      body: 'Push notification received',
      source: 'Foreground',
      time: now,
    );

    expect(item.title, 'Welcome');
    expect(item.body, 'Push notification received');
    expect(item.source, 'Foreground');
    expect(item.time, now);
  });
}
