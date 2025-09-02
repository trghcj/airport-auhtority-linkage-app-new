import 'package:cloud_firestore/cloud_firestore.dart';

class Flight {
  final String registrationNumber;
  final String aircraftType;
  final String airportCode;
  final String destinationLocation;
  final String departureLocation;
  final DateTime? departureTime;
  final DateTime? arrivalTime;
  final double? parking;
  final double? udfc;
  final double? rnfc;
  final double? tnlc;
  final double? landing;
  final double? openParking;
  final double? oldInPax;
  final double? oldUsPax;
  final double? newInPax;
  final double? newUsPax;
  final double? oldInRate;
  final double? oldUsRate;
  final double? newInRate;
  final double? newUsRate;

  Flight({
    required this.registrationNumber,
    required this.aircraftType,
    required this.airportCode,
    required this.destinationLocation,
    required this.departureLocation,
    this.departureTime,
    this.arrivalTime,
    this.parking,
    this.udfc,
    this.rnfc,
    this.tnlc,
    this.landing,
    this.openParking,
    this.oldInPax,
    this.oldUsPax,
    this.newInPax,
    this.newUsPax,
    this.oldInRate,
    this.oldUsRate,
    this.newInRate,
    this.newUsRate,
  });

  factory Flight.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    return Flight(
      registrationNumber: data['registrationNumber'] ?? '',
      aircraftType: data['aircraftType'] ?? '',
      airportCode: data['airportcode'] ?? '',
      destinationLocation: data['destinationLocation'] ?? '',
      departureLocation: data['departureLocation'] ?? '',
      departureTime: (data['departureTime'] as Timestamp?)?.toDate(),
      arrivalTime: (data['arrivalTime'] as Timestamp?)?.toDate(),
      parking: (data['Parking'] ?? 0).toDouble(),
      udfc: (data['UDFC'] ?? 0).toDouble(),
      rnfc: (data['RNFC'] ?? 0).toDouble(),
      tnlc: (data['TNLC'] ?? 0).toDouble(),
      landing: (data['Landing'] ?? 0).toDouble(),
      openParking: (data['Open Parking'] ?? 0).toDouble(),
      oldInPax: (data['OLD IN PAX'] ?? 0).toDouble(),
      oldUsPax: (data['OLD US PAX'] ?? 0).toDouble(),
      newInPax: (data['NEW IN PAX'] ?? 0).toDouble(),
      newUsPax: (data['NEW US PAX'] ?? 0).toDouble(),
      oldInRate: (data['OLD IN RATE'] ?? 0).toDouble(),
      oldUsRate: (data['OLD US RATE'] ?? 0).toDouble(),
      newInRate: (data['NEW IN RATE'] ?? 0).toDouble(),
      newUsRate: (data['NEW US RATE'] ?? 0).toDouble(),
    );
  }

  double get airtimeHours {
    if (departureTime != null && arrivalTime != null) {
      return arrivalTime!.difference(departureTime!).inMinutes / 60.0;
    }
    return 0.0;
  }

  String get billingStatus {
    final total = (parking ?? 0) + (udfc ?? 0) + (rnfc ?? 0) +
        (tnlc ?? 0) + (landing ?? 0) + (openParking ?? 0) +
        (oldInPax ?? 0) + (oldUsPax ?? 0) +
        (newInPax ?? 0) + (newUsPax ?? 0) +
        (oldInRate ?? 0) + (oldUsRate ?? 0) +
        (newInRate ?? 0) + (newUsRate ?? 0);
    return total > 0 ? "Billed" : "Unbilled";
  }

  String get linkageStatus {
    if (destinationLocation.isEmpty || departureLocation.isEmpty) {
      return "Unlinked";
    }
    return "Linked";
  }
}

class FlightService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<List<Flight>> getAllFlights() async {
    final snapshot = await _firestore.collection('flights').get();
    return snapshot.docs.map((doc) => Flight.fromFirestore(doc)).toList();
  }

  Future<List<Flight>> searchFlights(String query) async {
    final lowerQuery = query.toLowerCase();
    final snapshot = await _firestore.collection('flights').get();

    return snapshot.docs.map((doc) => Flight.fromFirestore(doc)).where((flight) {
      return flight.registrationNumber.toLowerCase().contains(lowerQuery) ||
          flight.aircraftType.toLowerCase().contains(lowerQuery) ||
          flight.airportCode.toLowerCase().contains(lowerQuery);
    }).toList();
  }

  Future<List<Flight>> getFlightsByFilter(String filterBy) async {
    final flights = await getAllFlights();

    if (filterBy == 'airtime') {
      return flights.where((f) => f.airtimeHours > 0).toList();
    } else if (filterBy == 'billing') {
      return flights.where((f) => f.billingStatus == "Billed").toList();
    } else if (filterBy == 'linkage') {
      return flights.where((f) => f.linkageStatus == "Unlinked").toList();
    } else {
      return flights;
    }
  }
}

