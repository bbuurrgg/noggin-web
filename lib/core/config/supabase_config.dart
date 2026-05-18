class SupabaseConfig {
  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://hirwocyixlhjlsrlygiz.supabase.co',
  );

  static const anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_5Q_LbvqQxmHELc8KlRm-xA_plM8HXrD',
  );
}
