import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final authStateProvider = StreamProvider<AuthState>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return _authStateStream(client);
});

final currentUserProvider = Provider<User?>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(supabaseClientProvider).auth.currentUser;
});

Future<AuthState> _refreshExpiredSession(
  SupabaseClient client,
  AuthState state,
) async {
  final session = state.session ?? client.auth.currentSession;
  if (session == null || !session.isExpired) {
    return state;
  }

  final response = await client.auth.refreshSession();
  final refreshedSession = response.session ?? client.auth.currentSession;
  await client.realtime.setAuth(refreshedSession?.accessToken);
  return AuthState(AuthChangeEvent.tokenRefreshed, refreshedSession);
}

Stream<AuthState> _authStateStream(SupabaseClient client) async* {
  yield await _refreshExpiredSession(
    client,
    AuthState(AuthChangeEvent.initialSession, client.auth.currentSession),
  );

  yield* client.auth.onAuthStateChange.asyncMap(
    (state) => _refreshExpiredSession(client, state),
  );
}
