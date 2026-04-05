import 'package:firebase_auth/firebase_auth.dart';

/// Converts technical error messages to user-friendly messages
class ErrorUtils {
  /// Convert any error to a human-friendly message
  static String getFriendlyMessage(dynamic error) {
    if (error == null) return 'Something went wrong. Please try again.';
    
    final errorStr = error.toString().toLowerCase();
    
    // Firebase Auth errors
    if (error is FirebaseAuthException) {
      return _getAuthErrorMessage(error.code);
    }
    
    // Check for common error patterns
    if (errorStr.contains('network') || 
        errorStr.contains('connection') ||
        errorStr.contains('socket') ||
        errorStr.contains('unreachable')) {
      return 'No internet connection. Please check your network and try again.';
    }
    
    if (errorStr.contains('permission') || errorStr.contains('denied')) {
      return 'You don\'t have permission to perform this action.';
    }
    
    if (errorStr.contains('not found') || errorStr.contains('does not exist')) {
      return 'The requested data could not be found.';
    }
    
    if (errorStr.contains('timeout') || errorStr.contains('timed out')) {
      return 'The request took too long. Please try again.';
    }
    
    if (errorStr.contains('already exists') || errorStr.contains('duplicate')) {
      return 'This item already exists.';
    }
    
    if (errorStr.contains('invalid') || errorStr.contains('malformed')) {
      return 'Invalid data. Please check your input and try again.';
    }
    
    if (errorStr.contains('quota') || errorStr.contains('limit')) {
      return 'Service limit reached. Please try again later.';
    }
    
    if (errorStr.contains('unavailable') || errorStr.contains('server')) {
      return 'Service temporarily unavailable. Please try again later.';
    }
    
    if (errorStr.contains('cancelled') || errorStr.contains('aborted')) {
      return 'Operation was cancelled.';
    }
    
    if (errorStr.contains('only patients')) {
      return 'This app is for patients only. Please use the doctor app.';
    }
    
    if (errorStr.contains('only doctors') || errorStr.contains('doctors only')) {
      return 'This app is for doctors only. Please use the patient app.';
    }
    
    if (errorStr.contains('not signed in') || errorStr.contains('not logged in')) {
      return 'Please sign in to continue.';
    }
    
    // Default friendly message
    return 'Something went wrong. Please try again.';
  }
  
  /// Get user-friendly message for Firebase Auth error codes
  static String _getAuthErrorMessage(String code) {
    switch (code) {
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'user-disabled':
        return 'This account has been disabled. Please contact support.';
      case 'user-not-found':
        return 'No account found with this email. Please sign up first.';
      case 'wrong-password':
        return 'Incorrect password. Please try again.';
      case 'invalid-credential':
        return 'Invalid email or password. Please try again.';
      case 'email-already-in-use':
        return 'An account already exists with this email. Please sign in instead.';
      case 'operation-not-allowed':
        return 'This sign-in method is not enabled. Please contact support.';
      case 'weak-password':
        return 'Password is too weak. Please use at least 6 characters.';
      case 'too-many-requests':
        return 'Too many failed attempts. Please try again later.';
      case 'network-request-failed':
        return 'No internet connection. Please check your network.';
      case 'requires-recent-login':
        return 'Please sign out and sign in again to continue.';
      case 'account-exists-with-different-credential':
        return 'An account already exists with the same email but different sign-in method.';
      case 'credential-already-in-use':
        return 'This credential is already linked to another account.';
      case 'expired-action-code':
        return 'This link has expired. Please request a new one.';
      case 'invalid-action-code':
        return 'This link is invalid or has already been used.';
      default:
        return 'Authentication failed. Please try again.';
    }
  }
  
  /// Get a short title for error display
  static String getErrorTitle(dynamic error) {
    final errorStr = error.toString().toLowerCase();
    
    if (errorStr.contains('network') || errorStr.contains('connection')) {
      return 'Connection Error';
    }
    if (errorStr.contains('permission')) {
      return 'Access Denied';
    }
    if (errorStr.contains('not found')) {
      return 'Not Found';
    }
    if (errorStr.contains('timeout')) {
      return 'Timeout';
    }
    if (error is FirebaseAuthException) {
      return 'Sign In Error';
    }
    
    return 'Error';
  }
}
