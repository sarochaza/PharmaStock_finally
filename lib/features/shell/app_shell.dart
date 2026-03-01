import 'package:flutter/material.dart';

import '../../data/auth/auth_repository.dart';
import '../pages/home_page.dart';
import '../pages/drugs_page.dart';
import '../drugs/add_drug_page.dart';
import '../pages/stock_page.dart';
import '../pages/logs_page.dart';

class AppShell extends StatefulWidget {
  final AuthRepository auth;
  const AppShell({super.key, required this.auth});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  // ✅ ใส่ SizedBox.shrink() ไว้ตำแหน่ง index 2 ให้ตรงกับปุ่ม Add
  late final List<Widget> _pages = const [
    HomePage(),            // 0
    DrugsPage(),           // 1
    SizedBox.shrink(),     // 2 (Add = push page)
    StockPage(),           // 3
    LogsPage(),            // 4
  ];

  Future<void> _openAddDrug() async {
    final ok = await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AddDrugPage()),
    );

    if (ok == true && mounted) {
      setState(() => _index = 1); // ไปหน้า Drugs
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('บันทึกยาเรียบร้อย')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: cs.primary,
        foregroundColor: Colors.white,
        title: const Text('PharmaStock'),
        actions: [
          IconButton(
            tooltip: 'ออกจากระบบ',
            onPressed: () async {
              try {
                await widget.auth.signOut();
              } catch (_) {}
            },
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: SafeArea(child: _pages[_index]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) {
          if (i == 2) {
            _openAddDrug();
            return;
          }
          setState(() => _index = i);
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_rounded), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.medication_rounded), label: 'Drugs'),
          NavigationDestination(icon: Icon(Icons.add_box_rounded), label: 'Add'),
          NavigationDestination(icon: Icon(Icons.inventory_2_rounded), label: 'Stock'),
          NavigationDestination(icon: Icon(Icons.receipt_long_rounded), label: 'Logs'),
        ],
      ),
    );
  }
}