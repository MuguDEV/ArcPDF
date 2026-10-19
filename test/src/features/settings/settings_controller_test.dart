import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:hive/hive.dart';
import 'package:arcpdf/src/features/settings/settings_controller.dart';

class MockBox extends Mock implements Box {}

void main() {
  group('SettingsController', () {
    late MockBox mockBox;

    setUp(() {
      mockBox = MockBox();
      when(() => mockBox.get('themeMode',
          defaultValue: any(named: 'defaultValue'))).thenReturn(0);
      when(() => mockBox.get('grid', defaultValue: any(named: 'defaultValue')))
          .thenReturn(false);
      when(() => mockBox.get('useBlurEffect',
          defaultValue: any(named: 'defaultValue'))).thenReturn(true);
      when(() => mockBox.get('useLiquidGlass',
          defaultValue: any(named: 'defaultValue'))).thenReturn(false);
      when(() => mockBox.get('anim', defaultValue: any(named: 'defaultValue')))
          .thenReturn(1.0);
      when(() => mockBox.get('animSpeed',
          defaultValue: any(named: 'defaultValue'))).thenReturn(1.0);
      when(() =>
              mockBox.get('thumbQ', defaultValue: any(named: 'defaultValue')))
          .thenReturn(0.8);
      when(() => mockBox.get('fontFamily',
          defaultValue: any(named: 'defaultValue'))).thenReturn(1);
      when(() => mockBox.get('useHaptics',
          defaultValue: any(named: 'defaultValue'))).thenReturn(true);
      when(() => mockBox.get('keepScreenAwake',
          defaultValue: any(named: 'defaultValue'))).thenReturn(false);
      when(() => mockBox.get('compressionThreads',
          defaultValue: any(named: 'defaultValue'))).thenReturn(2);
    });

    test('initial state reads from box', () {
      final controller = SettingsController(mockBox);

      expect(controller.state.themeMode, ThemeMode.system);
      expect(controller.state.useBlurEffect, true);
      expect(controller.state.useLiquidGlass, false);
      expect(controller.state.animationIntensity, 1.0);
      expect(controller.state.animationSpeed, 1.0);
      expect(controller.state.thumbnailQuality, 0.8);
      expect(controller.state.fontFamily, AppFontFamily.inter);
    });

    test('invalid stored values fall back without crashing startup', () {
      when(() => mockBox.get('themeMode',
          defaultValue: any(named: 'defaultValue'))).thenReturn(999);
      when(() => mockBox.get('fontFamily',
          defaultValue: any(named: 'defaultValue'))).thenReturn(-1);
      when(() => mockBox.get('anim', defaultValue: any(named: 'defaultValue')))
          .thenReturn(double.nan);
      when(() => mockBox.get('animSpeed',
          defaultValue: any(named: 'defaultValue'))).thenReturn('fast');
      when(() =>
              mockBox.get('thumbQ', defaultValue: any(named: 'defaultValue')))
          .thenReturn(double.infinity);
      when(() => mockBox.get('compressionThreads',
          defaultValue: any(named: 'defaultValue'))).thenReturn(double.nan);
      when(() => mockBox.get('useBlurEffect',
          defaultValue: any(named: 'defaultValue'))).thenReturn('yes');
      when(() => mockBox.get('skippedUpdateVersion')).thenReturn(123);
      final controller = SettingsController(mockBox);
      addTearDown(controller.dispose);
      expect(controller.state.themeMode, ThemeMode.system);
      expect(controller.state.fontFamily, AppFontFamily.inter);
      expect(controller.state.animationIntensity, 1);
      expect(controller.state.animationSpeed, 1);
      expect(controller.state.thumbnailQuality, 0.8);
      expect(controller.state.compressionThreads, 2);
      expect(controller.state.useBlurEffect, isTrue);
      expect(controller.state.skippedUpdateVersion, isNull);
    });

    test('numeric setters clamp ranges and reject non-finite values', () async {
      when(() => mockBox.put(any(), any())).thenAnswer((_) async {});
      final controller = SettingsController(mockBox);
      addTearDown(controller.dispose);
      await controller.setAnimationIntensity(-10);
      await controller.setAnimationSpeed(99);
      await controller.setThumbnailQuality(double.nan);
      expect(controller.state.animationIntensity, 0.01);
      expect(controller.state.animationSpeed, 2);
      expect(controller.state.thumbnailQuality, 0.8);
      verify(() => mockBox.put('thumbQ', 0.8)).called(1);
    });

    test('setThemeMode updates state and box', () async {
      when(() => mockBox.put('themeMode', any())).thenAnswer((_) async {});

      final controller = SettingsController(mockBox);
      await controller.setThemeMode(ThemeMode.dark);

      expect(controller.state.themeMode, ThemeMode.dark);
      verify(() => mockBox.put('themeMode', ThemeMode.dark.index)).called(1);
    });
  });
}
