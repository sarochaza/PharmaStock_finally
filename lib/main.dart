import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // โหลด .env
  await dotenv.load(fileName: ".env");

  // เตรียม Supabase (ยังไม่ใช้ก็ได้ แต่ init ไว้รองรับอนาคต)
  final supabaseUrl = dotenv.maybeGet('SUPABASE_URL') ?? '';
  final supabaseAnonKey = dotenv.maybeGet('SUPABASE_ANON_KEY') ?? '';

  // ถ้ายังไม่ใส่ค่า จะไม่ init (เพื่อไม่ให้พังตอนรัน)
  if (supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty) {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
    );
  }

  runApp(const PhamoryApp());
}