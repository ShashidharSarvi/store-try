import 'package:supabase_flutter/supabase_flutter.dart';

class UserService {
  final SupabaseClient supabase = Supabase.instance.client;

  /// Get the current user's role
  Future<String?> getUserRole() async {
    final user = supabase.auth.currentUser;
    if (user == null) return null;

    final response = await supabase
        .from('profiles')
        .select('role') // <-- make sure your `profiles` table has a `role` column
        .eq('id', user.id)
        .maybeSingle();

    return response?['role']; // returns "user" or "developer"
  }
}
