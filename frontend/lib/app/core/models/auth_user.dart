/// WHAT: Defines the authenticated user model shared across public and protected routes.
/// WHY: Route guards and dashboards need one canonical representation of the logged-in account.
/// HOW: Parse the backend user payload into a compact immutable Dart model.
library;

class AuthUser {
  const AuthUser({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.fullName,
    required this.email,
    required this.phone,
    required this.role,
    required this.status,
  });

  final String id;
  final String firstName;
  final String lastName;
  final String fullName;
  final String email;
  final String? phone;
  final String role;
  final String status;

  bool get isAdmin => role == 'admin';
  bool get isStaff => role == 'staff';
  bool get isCustomer => role == 'customer';

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'firstName': firstName,
      'lastName': lastName,
      'fullName': fullName,
      'email': email,
      'phone': phone,
      'role': role,
      'status': status,
    };
  }

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: json['id'] as String? ?? '',
      firstName: json['firstName'] as String? ?? '',
      lastName: json['lastName'] as String? ?? '',
      fullName: json['fullName'] as String? ?? '',
      email: json['email'] as String? ?? '',
      phone: json['phone'] as String?,
      role: json['role'] as String? ?? 'customer',
      status: json['status'] as String? ?? 'active',
    );
  }
}
