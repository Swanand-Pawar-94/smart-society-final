import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:smart_society_app/main.dart';
import 'package:smart_society_app/models/session.dart';
import 'package:smart_society_app/services/api_service.dart';
import 'package:smart_society_app/state/auth_controller.dart';

void main() {
  for (final role in ['RESIDENT', 'SECURITY', 'ADMIN']) {
    testWidgets('$role can open penalty management from its live More menu',
        (tester) async {
      final requestedPaths = <String>[];
      final api = ApiService(
        client: MockClient((request) async {
          requestedPaths.add(request.url.path);
          if (request.url.path.endsWith('/admin/penalty-dashboard')) {
            return _json({
              'data': {'total_reports': 0, 'by_status': {}}
            });
          }
          if (request.url.path.endsWith('/penalty-reports')) {
            return _json({
              'data': {'current_page': 1, 'data': []}
            });
          }
          return _json({'data': []});
        }),
      );
      final auth = AuthController(api)
        ..loading = false
        ..session = Session(
          token: 'test-token',
          user: AppUser(
            id: 1,
            name: 'Test User',
            email: 'test@example.test',
            role: role,
          ),
        );
      final home = switch (role) {
        'RESIDENT' => const ResidentMoreScreen(),
        'SECURITY' => const SecurityMoreScreen(),
        _ => const AdminMoreScreen(),
      };
      final menuLabel = switch (role) {
        'RESIDENT' => 'Penalties',
        'SECURITY' => 'Penalty reports',
        _ => 'Penalty management',
      };

      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: auth,
        child: MaterialApp(home: home),
      ));
      await tester.ensureVisible(find.text(menuLabel));
      await tester.tap(find.text(menuLabel));
      await tester.pumpAndSettle();

      expect(find.text('Penalty management'), findsOneWidget);
      expect(find.text('No violation reports yet.'), findsOneWidget);
      expect(requestedPaths, contains('/api/penalty-reports'));
      if (role == 'ADMIN') {
        expect(requestedPaths, contains('/api/admin/penalty-dashboard'));
      } else {
        expect(requestedPaths, isNot(contains('/api/admin/penalty-dashboard')));
      }
    });
  }
}

http.Response _json(Object data, {int statusCode = 200}) => http.Response(
      jsonEncode(data),
      statusCode,
      headers: {'content-type': 'application/json'},
    );
