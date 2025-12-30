import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

/// TFLite-based text embedding service for semantic similarity
class TFLiteEmbeddingService {
  Interpreter? _interpreter;
  bool _isInitialized = false;
  bool _modelAvailable = false;
  
  // Embedding cache: text hash -> embedding vector
  final Map<int, List<double>> _embeddingCache = {};
  
  static const String _modelPath = 'assets/models/use_lite.tflite';
  static const int _embeddingDim = 512;
  
  /// Initialize the TFLite interpreter
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      _interpreter = await Interpreter.fromAsset(_modelPath);
      _modelAvailable = true;
      _isInitialized = true;
      debugPrint('🤖 TFLite model loaded successfully');
    } catch (e) {
      _modelAvailable = false;
      _isInitialized = true;
      debugPrint('⚠️ TFLite model not available, using fallback: $e');
    }
  }
  
  /// Check if AI embeddings are available
  bool get isAIAvailable => _modelAvailable && _interpreter != null;
  
  /// Generate embedding for text
  Future<List<double>?> embed(String text) async {
    if (!_isInitialized) await initialize();
    if (!_modelAvailable || _interpreter == null) return null;
    
    final hash = text.hashCode;
    if (_embeddingCache.containsKey(hash)) {
      return _embeddingCache[hash];
    }
    
    try {
      final input = _prepareInput(text);
      final output = List.filled(_embeddingDim, 0.0).reshape([1, _embeddingDim]);
      
      _interpreter!.run(input, output);
      
      final embedding = (output[0] as List).cast<double>().toList();
      final normalized = _normalize(embedding);
      
      _embeddingCache[hash] = normalized;
      return normalized;
    } catch (e) {
      debugPrint('Embedding error: $e');
      return null;
    }
  }
  
  /// Compute cosine similarity between two embeddings
  double cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) return 0.0;
    
    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;
    
    for (int i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    
    if (normA == 0 || normB == 0) return 0.0;
    return dotProduct / (sqrt(normA) * sqrt(normB));
  }
  
  /// Compute similarity between two texts
  Future<double?> textSimilarity(String text1, String text2) async {
    if (!isAIAvailable) return null;
    
    final emb1 = await embed(text1);
    final emb2 = await embed(text2);
    
    if (emb1 == null || emb2 == null) return null;
    
    return cosineSimilarity(emb1, emb2);
  }
  
  List<List<int>> _prepareInput(String text) {
    final tokens = text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .split(' ')
        .take(128)
        .map((w) => w.hashCode % 30000)
        .toList();
    
    while (tokens.length < 128) {
      tokens.add(0);
    }
    
    return [tokens];
  }
  
  List<double> _normalize(List<double> vec) {
    double norm = 0.0;
    for (var v in vec) {
      norm += v * v;
    }
    norm = sqrt(norm);
    if (norm == 0) return vec;
    return vec.map((v) => v / norm).toList();
  }
  
  void clearCache() {
    _embeddingCache.clear();
  }
  
  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isInitialized = false;
    _embeddingCache.clear();
  }
}
