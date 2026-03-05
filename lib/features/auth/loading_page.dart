import 'dart:async';
import 'package:flutter/material.dart';
import 'package:phamory/core/theme.dart';
import 'package:phamory/features/pages/home_page.dart';


class LoadingPage extends StatefulWidget {
  const LoadingPage({super.key});


  @override
  State<LoadingPage> createState() => _LoadingPageState();
}


class _LoadingPageState extends State<LoadingPage>
    with TickerProviderStateMixin {


  late AnimationController _controller;
  late Timer _dotTimer;


  int dotCount = 1;
  String loadingText = "กำลังโหลด.";


  @override
  void initState() {
    super.initState();


    // animation controller
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);


    // จุดวิ่ง
    _dotTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      setState(() {
        dotCount = (dotCount % 3) + 1;
        loadingText = "กำลังโหลด${"." * dotCount}";
      });
    });


    // หน่วง 3 วิ แล้วไป Home
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomePage()),
        );
      }
    });
  }


  @override
  void dispose() {
    _controller.dispose();
    _dotTimer.cancel();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    final floatAnimation =
        Tween(begin: 0.0, end: -20.0).animate(_controller);


    final scaleAnimation =
        Tween(begin: 1.0, end: 1.08).animate(_controller);


    final rotateAnimation =
        Tween(begin: 0.0, end: 0.3).animate(_controller);


    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [PharmaColors.lightBlue, PharmaColors.primary],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [


                  Transform.translate(
                    offset: Offset(0, floatAnimation.value),
                    child: Transform.rotate(
                      angle: rotateAnimation.value,
                      child: Transform.scale(
                        scale: scaleAnimation.value,
                        child: Image.asset(
                          'assets/pill.png', // ใส่รูป pill ของคุณ
                          width: 120,
                        ),
                      ),
                    ),
                  ),


                  const SizedBox(height: 40),


                  Text(
                    loadingText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

