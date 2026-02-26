import 'package:uuid/uuid.dart';

const Uuid _uuid = Uuid();

String newId() => _uuid.v4();
