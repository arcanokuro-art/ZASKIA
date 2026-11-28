import 'package:flutter/material.dart';
import '../settings/app_settings.dart';
import '../workspace/projects_screen.dart';
import 'onboarding_screen.dart';

class StartScreen extends StatelessWidget {
  const StartScreen({super.key});
  @override Widget build(BuildContext context)=>AnimatedBuilder(animation:AppSettings.instance,builder:(context,_)=>
    AppSettings.instance.get<bool>('onboardingComplete')?const ProjectsScreen():
      OnboardingScreen(onFinished:()=>AppSettings.instance.set('onboardingComplete',true)));
}
