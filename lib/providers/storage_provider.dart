import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/storage_service.dart';

// Make storage service available as a provider
final storageServiceProvider = Provider((ref) => StorageService());
