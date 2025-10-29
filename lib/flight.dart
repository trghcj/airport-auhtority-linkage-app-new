// lib/flight.dart

class Flight {
  final String registrationNumber;
  final String aircraftType;
  final String airportcode;
  final String destinationloactio;
  final String departureloaction;
  final DateTime departureTime;
  final DateTime arrivalTime;
  final double airtimeHours;
  final String linkageStatus;
  final String billingStatus;

  Flight({
    required this.registrationNumber,
    required this.aircraftType,
    required this.airportcode,
    required this.destinationloactio,
    required this.departureloaction,
    required this.departureTime,
    required this.arrivalTime,
    required this.airtimeHours,
    required this.linkageStatus,
    required this.billingStatus,
  });

  factory Flight.fromFirestore(Map<String, dynamic> data) {
    return Flight(
      registrationNumber: data['Reg No.'] ?? '',
      aircraftType: data['aircraftType'] ?? '',
      airportcode: data['airportcode'] ?? '',
      destinationloactio: data['Dest Location'] ?? '',
      departureloaction: data['Dep Location'] ?? '',
      departureTime: DateTime.tryParse(data['departureTime'] ?? '') ?? DateTime.now(),
      arrivalTime: DateTime.tryParse(data['arrivalTime'] ?? '') ?? DateTime.now(),
      airtimeHours: (data['airtimeHours'] ?? 0).toDouble(),
      linkageStatus: data['linkageStatus'] ?? 'Unlinked',
      billingStatus: data['billingStatus'] ?? 'Unbilled',
    );
  }
}
