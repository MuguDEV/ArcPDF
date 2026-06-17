import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../shared/widgets/arc_bouncy_card.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('About & Licenses', style: TextStyle(fontWeight: FontWeight.w700)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          children: [
            // App Logo / Identity
            Center(
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: theme.colorScheme.primary.withValues(alpha: 0.15),
                      blurRadius: 32,
                      offset: const Offset(0, 16),
                    )
                  ],
                ),
                child: Icon(
                  HugeIcons.strokeRoundedPdf02,
                  size: 56,
                  color: theme.colorScheme.primary,
                ),
              ).animate().scale(delay: 100.ms, duration: 500.ms, curve: Curves.elasticOut),
            ),
            const SizedBox(height: 24),

            Text(
              'ArcPDF',
              style: theme.textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
            ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.2),

            const SizedBox(height: 8),
            Text(
              'A Beautiful, Private PDF Reader',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.2),

            const SizedBox(height: 48),

            // Copyright Section
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(HugeIcons.strokeRoundedCopyright, size: 20, color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Text(
                        '2026 Mugunthan S',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'This program is free software: you can redistribute it and/or modify it under the terms of the GNU Affero General Public License (AGPL-3.0) as published by the Free Software Foundation.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.1),

            const SizedBox(height: 24),

            // Licenses Action
            ArcBouncyCard(
              onTap: () {
                showLicensePage(
                  context: context,
                  applicationName: 'ArcPDF',
                  applicationLegalese: 'Copyright (C) 2026 Mugunthan S\nLicensed under GNU AGPL-3.0',
                );
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      theme.colorScheme.primaryContainer,
                      theme.colorScheme.primary.withValues(alpha: 0.2),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(HugeIcons.strokeRoundedBookOpen01, color: theme.colorScheme.onPrimary, size: 24),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Open Source Licenses',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'View third-party software details',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(HugeIcons.strokeRoundedArrowRight01, color: theme.colorScheme.onPrimaryContainer),
                  ],
                ),
              ),
            ).animate().fadeIn(delay: 500.ms).slideY(begin: 0.1),
          ],
        ),
      ),
    );
  }
}
