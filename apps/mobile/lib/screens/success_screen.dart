import 'package:flutter/material.dart';

/// Reusable full-screen success page shown after a completed money flow
/// (transfer, request, merchant payment). Pushed with `pushReplacement`
/// (after popping back to the first route) so Back returns to home.
class SuccessScreen extends StatelessWidget {
  const SuccessScreen({
    super.key,
    required this.title,
    required this.amountText,
    this.subtitleLines = const [],
    this.primaryButtonLabel = 'Done',
    required this.onPrimary,
  });

  final String title;
  final String amountText;
  final List<String> subtitleLines;
  final String primaryButtonLabel;
  final VoidCallback onPrimary;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 112,
                height: 112,
                decoration: const BoxDecoration(
                  color: Color(0xFFE5F6EC),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: SizedBox(
                    width: 72,
                    height: 72,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Color(0xFF1B7F4B),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child:
                            Icon(Icons.check, color: Colors.white, size: 44),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1F2937),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                amountText,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF111827),
                ),
              ),
              if (subtitleLines.isNotEmpty) ...[
                const SizedBox(height: 16),
                ...subtitleLines.map(
                  (line) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      line,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ),
                ),
              ],
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onPrimary,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0F4C81),
                    minimumSize: const Size.fromHeight(52),
                  ),
                  child: Text(primaryButtonLabel),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
