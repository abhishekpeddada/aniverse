import 'package:flutter/material.dart';

class SourceBadge extends StatelessWidget {
  final String source; // 'allanime' or 'raiden'
  
  const SourceBadge({
    super.key,
    required this.source,
  });

  @override
  Widget build(BuildContext context) {
    final isRaiden = source == 'raiden';
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isRaiden ? Colors.purple.withOpacity(0.8) : Colors.blue.withOpacity(0.8),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        isRaiden ? 'RAIDEN' : 'ALLANIME',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 8,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
