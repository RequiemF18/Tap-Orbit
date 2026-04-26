import 'package:flutter/material.dart';

import 'game_screen.dart';

class GameOverScreen extends StatelessWidget {
  const GameOverScreen({
    super.key,
    required this.finalScore,
    required this.bestCombo,
    required this.personalBest,
  });

  final int finalScore;
  final int bestCombo;
  final int personalBest;

  @override
  Widget build(BuildContext context) {
    const cyan = Color(0xFF00E5FF);
    const magenta = Color(0xFFFF2BD6);
    const lime = Color(0xFFB6FF00);
    const amber = Color(0xFFFFB300);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'GAME OVER',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 44,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 3,
                    shadows: [
                      Shadow(
                        color: Colors.white54,
                        blurRadius: 22,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 42),
                _StatLine(label: 'FINAL SCORE', value: '$finalScore', color: cyan),
                const SizedBox(height: 18),
                _StatLine(label: 'BEST COMBO', value: '$bestCombo', color: magenta),
                const SizedBox(height: 18),
                _StatLine(label: 'PERSONAL BEST', value: '$personalBest', color: lime),
                const SizedBox(height: 54),
                _NeonButton(
                  color: amber,
                  text: 'Play Again',
                  onPressed: () {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => const GameScreen()),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatLine extends StatelessWidget {
  const _StatLine({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            color: color.withOpacity(0.78),
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: 2.4,
            shadows: [Shadow(color: color, blurRadius: 16)],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 36,
            fontWeight: FontWeight.w900,
            shadows: [Shadow(color: color, blurRadius: 22)],
          ),
        ),
      ],
    );
  }
}

class _NeonButton extends StatelessWidget {
  const _NeonButton({required this.text, required this.color, required this.onPressed});

  final String text;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(color: color.withOpacity(0.35), blurRadius: 24, spreadRadius: 1),
        ],
        borderRadius: BorderRadius.circular(999),
      ),
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.black,
          side: BorderSide(color: color, width: 2),
          foregroundColor: color,
          padding: const EdgeInsets.symmetric(horizontal: 42, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: color,
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
            shadows: [Shadow(color: color, blurRadius: 14)],
          ),
        ),
      ),
    );
  }
}
