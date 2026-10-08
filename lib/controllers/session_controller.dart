// lib/controllers/session_controller.dart
//
// PulseGuard — Local Mock Authentication and User Session Controller.
//
// DESIGN & ARCHITECTURE NOTE:
//   PulseGuard is an offline-first, private biometric wellness application.
//   Authentication is a LOCAL MOCK: one primary account per device, stored in
//   SQLite with a salted SHA-256 hash. No external cloud authentication or
//   network connectivity is used.
//
// Manages:
//   * User sign-in, sign-up with OTP simulation, and password reset
//   * Profile attributes (name, age, gender, avatar picture)
//   * Health questionnaire metadata persistence

import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../models/user_profile.dart';
import '../services/database_service.dart';

class SessionController extends ChangeNotifier {
  SessionController({DatabaseService? database})
      : _database = database ?? DatabaseService.instance;

  final DatabaseService _database;

  UserProfile? _profile;
  bool _isLoading = false;
  String? _errorMessage;

  UserProfile? get profile => _profile;
  bool get isAuthenticated => _profile != null;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String? get avatarPath => _profile?.avatarPath;

  /// Loads the active local user profile from SQLite.
  Future<void> loadSession() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final p = await _database.fetchCurrentProfile();
      _profile = p;
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Hashes a password with a unique salt using SHA-256.
  static String hashPassword(String password, String salt) {
    final bytes = utf8.encode('$salt:$password:$salt');
    return sha256.convert(bytes).toString();
  }

  /// Generates a cryptographically randomized 16-character salt.
  static String generateSalt() {
    final rand = Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    return base64Url.encode(bytes);
  }

  /// Generates a random 6-digit simulation OTP for on-screen display.
  static String generateSimulatedOtp() {
    final rand = Random();
    final code = rand.nextInt(900000) + 100000;
    return code.toString();
  }

  /// Attempts to authenticate the user locally with email and password.
  Future<bool> signIn(String email, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final normalizedEmail = email.trim().toLowerCase();
      var user = await _database.fetchUserProfileByEmail(normalizedEmail);

      // If no match by email, check if only one default profile exists
      user ??= await _database.fetchCurrentProfile();

      if (user == null) {
        _errorMessage = 'No user profile found on this device.';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      // Verify salted hash if credentials exist
      if (user.passwordHash != null && user.salt != null) {
        final computed = hashPassword(password, user.salt!);
        if (computed != user.passwordHash) {
          _errorMessage = 'Incorrect password.';
          _isLoading = false;
          notifyListeners();
          return false;
        }
      }

      _profile = user;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Sign in failed: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Registers a new local account with salted hash and sets it active.
  Future<UserProfile> registerAccount({
    required String name,
    required String email,
    required String password,
  }) async {
    final salt = generateSalt();
    final hash = hashPassword(password, salt);

    final newProfile = UserProfile(
      name: name.trim(),
      email: email.trim().toLowerCase(),
      age: 25,
      gender: 'Male',
      passwordHash: hash,
      salt: salt,
      createdAt: DateTime.now().toUtc().toIso8601String(),
    );

    final id = await _database.insertUserProfile(newProfile);
    _profile = newProfile.copyWith(id: id);
    notifyListeners();
    return _profile!;
  }

  /// Resets password for the local profile.
  Future<bool> resetPassword({
    required String email,
    required String newPassword,
  }) async {
    try {
      final normalizedEmail = email.trim().toLowerCase();
      var user = await _database.fetchUserProfileByEmail(normalizedEmail);
      user ??= await _database.fetchCurrentProfile();

      if (user == null) {
        _errorMessage = 'Account not found.';
        notifyListeners();
        return false;
      }

      final salt = generateSalt();
      final hash = hashPassword(newPassword, salt);
      final updated = user.copyWith(passwordHash: hash, salt: salt);
      await _database.updateUserProfile(updated);

      if (_profile?.id == updated.id) {
        _profile = updated;
      }
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Saves complete onboarding health questionnaire metadata into SQLite.
  Future<void> saveQuestionnaireData({
    required String sex,
    required DateTime dob,
    required int age,
    required String height,
    required String weight,
    required List<String> cardiacDevices,
    required List<String> cardiacEvents,
    required List<String> arrhythmia,
    required List<String> conditions,
    required List<String> medications,
    required String nicotine,
  }) async {
    final healthMap = {
      'sex': sex,
      'dob': dob.toIso8601String(),
      'age': age,
      'height': height,
      'weight': weight,
      'cardiac_devices': cardiacDevices,
      'cardiac_events': cardiacEvents,
      'arrhythmia': arrhythmia,
      'conditions': conditions,
      'medications': medications,
      'nicotine': nicotine,
    };

    final current = _profile ??
        UserProfile(
          name: 'User',
          age: age,
          gender: sex.toLowerCase(),
          createdAt: DateTime.now().toUtc().toIso8601String(),
        );

    final updated = current.copyWith(
      age: age,
      gender: sex.toLowerCase(),
      healthJson: jsonEncode(healthMap),
    );

    if (updated.id != null) {
      await _database.updateUserProfile(updated);
      _profile = updated;
    } else {
      final id = await _database.insertUserProfile(updated);
      _profile = updated.copyWith(id: id);
    }
    notifyListeners();
  }

  /// Updates profile avatar image file path.
  Future<void> updateAvatar(String path) async {
    if (_profile == null) return;
    final updated = _profile!.copyWith(avatarPath: path);
    await _database.updateUserProfile(updated);
    _profile = updated;
    notifyListeners();
  }

  /// Updates basic profile info (name, age, gender).
  Future<void> updateProfile({
    String? name,
    int? age,
    String? gender,
  }) async {
    if (_profile == null) return;
    final updated = _profile!.copyWith(
      name: name,
      age: age,
      gender: gender,
    );
    await _database.updateUserProfile(updated);
    _profile = updated;
    notifyListeners();
  }

  /// Signs out of the local session.
  void signOut() {
    _profile = null;
    notifyListeners();
  }
}
