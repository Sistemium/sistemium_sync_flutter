import 'package:flutter/foundation.dart';
import 'package:sentry/sentry.dart';

/// Centralized logging system for Sistemium Sync Flutter library
/// 
/// Usage:
/// ```dart
/// SyncLogger.log('Sync started');
/// SyncLogger.log('Sync started', name: 'SYNC');
/// SyncLogger.log('Sync failed', error: e, stackTrace: st);
/// ```
class SyncLogger {
  /// Single logging method
  static void log(
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (kDebugMode) {
      // Debug mode: console logging
      final callerInfo = _getCallerInfo();

      final timestamp = DateTime.now();
      final timeStr = '${timestamp.hour.toString().padLeft(2, '0')}:'
                     '${timestamp.minute.toString().padLeft(2, '0')}:'
                     '${timestamp.second.toString().padLeft(2, '0')}.'
                     '${timestamp.millisecond.toString().padLeft(3, '0')}';

      final buffer = StringBuffer();
      buffer.write('[$timeStr] ');

      if (callerInfo != null) {
        buffer.write('[${callerInfo.file}:${callerInfo.line}] ');
      }

      buffer.write(message);

      print(buffer.toString());

      if (error != null) {
        print('Error: $error');
        if (stackTrace != null) {
          print('Stack trace:\n$stackTrace');
        }
      }
    } else if (Sentry.isEnabled) {
      // Release mode with Sentry: forward to Sentry
      if (error != null) {
        Sentry.logger.error(message);
      } else {
        Sentry.logger.info(message);
      }
    }
  }
  
  /// Extract caller information from stack trace
  static _CallerInfo? _getCallerInfo() {
    try {
      final trace = StackTrace.current.toString();
      final lines = trace.split('\n');
      
      // Skip the first few lines (this class's methods)
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i];
        
        // Skip lines from this logger class
        if (line.contains('sync_logger.dart')) continue;
        
        // Skip Flutter framework lines
        if (line.contains('package:flutter/')) continue;
        
        // Parse the line to extract file and line number
        // Format: #N      method (package:app/file.dart:line:column)
        final match = RegExp(r'\((.+?):(\d+):\d+\)').firstMatch(line);
        if (match != null) {
          String filePath = match.group(1)!;
          final lineNumber = match.group(2)!;
          
          // Extract just the filename from the path
          if (filePath.contains('/')) {
            filePath = filePath.split('/').last;
          }
          
          return _CallerInfo(filePath, lineNumber);
        }
      }
    } catch (e) {
      // Silently fail if we can't get caller info
    }
    return null;
  }
}

/// Helper class to store caller information
class _CallerInfo {
  final String file;
  final String line;
  
  _CallerInfo(this.file, this.line);
}