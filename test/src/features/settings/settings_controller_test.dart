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
      when(() => mockBox.get('themeMode', defaultValue: any(named: 'defaultValue'))).thenReturn(0);
      when(() => mockBox.get('grid', defaultValue: any(named: 'defaultValue'))).thenReturn(false);
      when(() => mockBox.get('useBlurEffect', defaultValue: any(named: 'defaultValue'))).thenReturn(true);
      when(() => mockBox.get('useLiquidGlass', defaultValue: any(named: 'defaultValue'))).thenReturn(false);
      when(() => mockBox.get('anim', defaultValue: any(named: 'defaultValue'))).thenReturn(1.0);
      when(() => mockBox.get('animSpeed', defaultValue: any(named: 'defaultValue'))).thenReturn(1.0);
      when(() => mockBox.get('thumbQ', defaultValue: any(named: 'defaultValue'))).thenReturn(0.8);
      when(() => mockBox.get('fontFamily', defaultValue: any(named: 'defaultValue'))).thenReturn(1);
    });

    test('initial state reads from box', () {
      final controller = SettingsController(mockBox);

      expect(controller.state.themeMode, ThemeMode.system);
      expect(controller.state.useGrid, false);
      expect(controller.state.useBlurEffect, true);
      expect(controller.state.useLiquidGlass, false);
      expect(controller.state.animationIntensity, 1.0);
      expect(controller.state.animationSpeed, 1.0);
      expect(controller.state.thumbnailQuality, 0.8);
      expect(controller.state.fontFamily, AppFontFamily.inter);
    });

    test('setThemeMode updates state and box', () async {
      when(() => mockBox.put('themeMode', any())).thenAnswer((_) async {});

      final controller = SettingsController(mockBox);
      await controller.setThemeMode(ThemeMode.dark);

      expect(controller.state.themeMode, ThemeMode.dark);
      verify(() => mockBox.put('themeMode', ThemeMode.dark.index)).called(1);
    });

    test('setGrid updates state and box', () async {
      when(() => mockBox.put('grid', any())).thenAnswer((_) async {});

      final controller = SettingsController(mockBox);
      await controller.setGrid(true);

      expect(controller.state.useGrid, true);
      verify(() => mockBox.put('grid', true)).called(1);
    });
  });
}
