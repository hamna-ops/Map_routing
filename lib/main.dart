import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'booking_content_detail.dart';
import 'utils/app_constants.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(AppConstants.designWidth, AppConstants.designHeight),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        return MaterialApp(
          title: 'Map Routing App',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(AppConstants.primaryColorValue),
            ),
            useMaterial3: true,
          ),
          home: const HomeScreen(),
        );
      },
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Sample booking data - In production, this should come from a state management solution
    final sampleBooking = {
      'startLocation': '12 Ashford Road, Brighton, UK',
      'endLocation': '47 High Street, Hove, UK',
      'startTime': '16:00 PM',
      'endTime': '16:24 PM',
      'distance': '4Km',
      'duration': '24mints',
      'remainingDistance': '2Km Left',
      'remainingTime': '12 mints',
      'providerName': 'John Michael',
      'providerTitle': 'Carpenter',
      'rating': '4.9',
      'price': '\$25/hr',
    };
    return BookingContentDetail(booking: sampleBooking);
  }
}
