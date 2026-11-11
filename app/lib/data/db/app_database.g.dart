// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $InsightsTable extends Insights
    with TableInfo<$InsightsTable, InsightRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $InsightsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<InsightType, String> type =
      GeneratedColumn<String>(
        'type',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<InsightType>($InsightsTable.$convertertype);
  @override
  late final GeneratedColumnWithTypeConverter<PetType, String> petType =
      GeneratedColumn<String>(
        'pet_type',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<PetType>($InsightsTable.$converterpetType);
  static const VerificationMeta _breedMeta = const VerificationMeta('breed');
  @override
  late final GeneratedColumn<String> breed = GeneratedColumn<String>(
    'breed',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<Map<String, Object?>, String>
  payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  ).withConverter<Map<String, Object?>>($InsightsTable.$converterpayload);
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    type,
    petType,
    breed,
    payload,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'insights';
  @override
  VerificationContext validateIntegrity(
    Insertable<InsightRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('breed')) {
      context.handle(
        _breedMeta,
        breed.isAcceptableOrUnknown(data['breed']!, _breedMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  InsightRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return InsightRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      type: $InsightsTable.$convertertype.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}type'],
        )!,
      ),
      petType: $InsightsTable.$converterpetType.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}pet_type'],
        )!,
      ),
      breed: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}breed'],
      ),
      payload: $InsightsTable.$converterpayload.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}payload'],
        )!,
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $InsightsTable createAlias(String alias) {
    return $InsightsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<InsightType, String, String> $convertertype =
      const EnumNameConverter<InsightType>(InsightType.values);
  static JsonTypeConverter2<PetType, String, String> $converterpetType =
      const EnumNameConverter<PetType>(PetType.values);
  static TypeConverter<Map<String, Object?>, String> $converterpayload =
      const JsonMapConverter();
}

class InsightRow extends DataClass implements Insertable<InsightRow> {
  /// UUID v4; for `clip` rows it is the clipId, which makes replays idempotent.
  final String id;
  final InsightType type;
  final PetType petType;
  final String? breed;
  final Map<String, Object?> payload;
  final DateTime createdAt;
  const InsightRow({
    required this.id,
    required this.type,
    required this.petType,
    this.breed,
    required this.payload,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    {
      map['type'] = Variable<String>($InsightsTable.$convertertype.toSql(type));
    }
    {
      map['pet_type'] = Variable<String>(
        $InsightsTable.$converterpetType.toSql(petType),
      );
    }
    if (!nullToAbsent || breed != null) {
      map['breed'] = Variable<String>(breed);
    }
    {
      map['payload'] = Variable<String>(
        $InsightsTable.$converterpayload.toSql(payload),
      );
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  InsightsCompanion toCompanion(bool nullToAbsent) {
    return InsightsCompanion(
      id: Value(id),
      type: Value(type),
      petType: Value(petType),
      breed: breed == null && nullToAbsent
          ? const Value.absent()
          : Value(breed),
      payload: Value(payload),
      createdAt: Value(createdAt),
    );
  }

  factory InsightRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return InsightRow(
      id: serializer.fromJson<String>(json['id']),
      type: $InsightsTable.$convertertype.fromJson(
        serializer.fromJson<String>(json['type']),
      ),
      petType: $InsightsTable.$converterpetType.fromJson(
        serializer.fromJson<String>(json['petType']),
      ),
      breed: serializer.fromJson<String?>(json['breed']),
      payload: serializer.fromJson<Map<String, Object?>>(json['payload']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'type': serializer.toJson<String>(
        $InsightsTable.$convertertype.toJson(type),
      ),
      'petType': serializer.toJson<String>(
        $InsightsTable.$converterpetType.toJson(petType),
      ),
      'breed': serializer.toJson<String?>(breed),
      'payload': serializer.toJson<Map<String, Object?>>(payload),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  InsightRow copyWith({
    String? id,
    InsightType? type,
    PetType? petType,
    Value<String?> breed = const Value.absent(),
    Map<String, Object?>? payload,
    DateTime? createdAt,
  }) => InsightRow(
    id: id ?? this.id,
    type: type ?? this.type,
    petType: petType ?? this.petType,
    breed: breed.present ? breed.value : this.breed,
    payload: payload ?? this.payload,
    createdAt: createdAt ?? this.createdAt,
  );
  InsightRow copyWithCompanion(InsightsCompanion data) {
    return InsightRow(
      id: data.id.present ? data.id.value : this.id,
      type: data.type.present ? data.type.value : this.type,
      petType: data.petType.present ? data.petType.value : this.petType,
      breed: data.breed.present ? data.breed.value : this.breed,
      payload: data.payload.present ? data.payload.value : this.payload,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('InsightRow(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('petType: $petType, ')
          ..write('breed: $breed, ')
          ..write('payload: $payload, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, type, petType, breed, payload, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is InsightRow &&
          other.id == this.id &&
          other.type == this.type &&
          other.petType == this.petType &&
          other.breed == this.breed &&
          other.payload == this.payload &&
          other.createdAt == this.createdAt);
}

class InsightsCompanion extends UpdateCompanion<InsightRow> {
  final Value<String> id;
  final Value<InsightType> type;
  final Value<PetType> petType;
  final Value<String?> breed;
  final Value<Map<String, Object?>> payload;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const InsightsCompanion({
    this.id = const Value.absent(),
    this.type = const Value.absent(),
    this.petType = const Value.absent(),
    this.breed = const Value.absent(),
    this.payload = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  InsightsCompanion.insert({
    required String id,
    required InsightType type,
    required PetType petType,
    this.breed = const Value.absent(),
    required Map<String, Object?> payload,
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       type = Value(type),
       petType = Value(petType),
       payload = Value(payload),
       createdAt = Value(createdAt);
  static Insertable<InsightRow> custom({
    Expression<String>? id,
    Expression<String>? type,
    Expression<String>? petType,
    Expression<String>? breed,
    Expression<String>? payload,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (type != null) 'type': type,
      if (petType != null) 'pet_type': petType,
      if (breed != null) 'breed': breed,
      if (payload != null) 'payload': payload,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  InsightsCompanion copyWith({
    Value<String>? id,
    Value<InsightType>? type,
    Value<PetType>? petType,
    Value<String?>? breed,
    Value<Map<String, Object?>>? payload,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return InsightsCompanion(
      id: id ?? this.id,
      type: type ?? this.type,
      petType: petType ?? this.petType,
      breed: breed ?? this.breed,
      payload: payload ?? this.payload,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(
        $InsightsTable.$convertertype.toSql(type.value),
      );
    }
    if (petType.present) {
      map['pet_type'] = Variable<String>(
        $InsightsTable.$converterpetType.toSql(petType.value),
      );
    }
    if (breed.present) {
      map['breed'] = Variable<String>(breed.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(
        $InsightsTable.$converterpayload.toSql(payload.value),
      );
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('InsightsCompanion(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('petType: $petType, ')
          ..write('breed: $breed, ')
          ..write('payload: $payload, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ClipsTable extends Clips with TableInfo<$ClipsTable, ClipRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ClipsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<ClipStatus, String> status =
      GeneratedColumn<String>(
        'status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<ClipStatus>($ClipsTable.$converterstatus);
  @override
  late final GeneratedColumnWithTypeConverter<List<String>, String> framePaths =
      GeneratedColumn<String>(
        'frame_paths',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<List<String>>($ClipsTable.$converterframePaths);
  static const VerificationMeta _jobIdMeta = const VerificationMeta('jobId');
  @override
  late final GeneratedColumn<String> jobId = GeneratedColumn<String>(
    'job_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _errorMeta = const VerificationMeta('error');
  @override
  late final GeneratedColumn<String> error = GeneratedColumn<String>(
    'error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<PetType, String> petType =
      GeneratedColumn<String>(
        'pet_type',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<PetType>($ClipsTable.$converterpetType);
  static const VerificationMeta _breedHintMeta = const VerificationMeta(
    'breedHint',
  );
  @override
  late final GeneratedColumn<String> breedHint = GeneratedColumn<String>(
    'breed_hint',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    status,
    framePaths,
    jobId,
    error,
    createdAt,
    petType,
    breedHint,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'clips';
  @override
  VerificationContext validateIntegrity(
    Insertable<ClipRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('job_id')) {
      context.handle(
        _jobIdMeta,
        jobId.isAcceptableOrUnknown(data['job_id']!, _jobIdMeta),
      );
    }
    if (data.containsKey('error')) {
      context.handle(
        _errorMeta,
        error.isAcceptableOrUnknown(data['error']!, _errorMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('breed_hint')) {
      context.handle(
        _breedHintMeta,
        breedHint.isAcceptableOrUnknown(data['breed_hint']!, _breedHintMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ClipRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ClipRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      status: $ClipsTable.$converterstatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}status'],
        )!,
      ),
      framePaths: $ClipsTable.$converterframePaths.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}frame_paths'],
        )!,
      ),
      jobId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}job_id'],
      ),
      error: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      petType: $ClipsTable.$converterpetType.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}pet_type'],
        )!,
      ),
      breedHint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}breed_hint'],
      ),
    );
  }

  @override
  $ClipsTable createAlias(String alias) {
    return $ClipsTable(attachedDatabase, alias);
  }

  static TypeConverter<ClipStatus, String> $converterstatus =
      const ClipStatusConverter();
  static TypeConverter<List<String>, String> $converterframePaths =
      const StringListConverter();
  static JsonTypeConverter2<PetType, String, String> $converterpetType =
      const EnumNameConverter<PetType>(PetType.values);
}

class ClipRow extends DataClass implements Insertable<ClipRow> {
  final String id;

  /// Stored as [ClipStatus.wireName] (`pending_upload`, ...).
  final ClipStatus status;
  final List<String> framePaths;
  final String? jobId;
  final String? error;
  final DateTime createdAt;
  final PetType petType;
  final String? breedHint;
  const ClipRow({
    required this.id,
    required this.status,
    required this.framePaths,
    this.jobId,
    this.error,
    required this.createdAt,
    required this.petType,
    this.breedHint,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    {
      map['status'] = Variable<String>(
        $ClipsTable.$converterstatus.toSql(status),
      );
    }
    {
      map['frame_paths'] = Variable<String>(
        $ClipsTable.$converterframePaths.toSql(framePaths),
      );
    }
    if (!nullToAbsent || jobId != null) {
      map['job_id'] = Variable<String>(jobId);
    }
    if (!nullToAbsent || error != null) {
      map['error'] = Variable<String>(error);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    {
      map['pet_type'] = Variable<String>(
        $ClipsTable.$converterpetType.toSql(petType),
      );
    }
    if (!nullToAbsent || breedHint != null) {
      map['breed_hint'] = Variable<String>(breedHint);
    }
    return map;
  }

  ClipsCompanion toCompanion(bool nullToAbsent) {
    return ClipsCompanion(
      id: Value(id),
      status: Value(status),
      framePaths: Value(framePaths),
      jobId: jobId == null && nullToAbsent
          ? const Value.absent()
          : Value(jobId),
      error: error == null && nullToAbsent
          ? const Value.absent()
          : Value(error),
      createdAt: Value(createdAt),
      petType: Value(petType),
      breedHint: breedHint == null && nullToAbsent
          ? const Value.absent()
          : Value(breedHint),
    );
  }

  factory ClipRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ClipRow(
      id: serializer.fromJson<String>(json['id']),
      status: serializer.fromJson<ClipStatus>(json['status']),
      framePaths: serializer.fromJson<List<String>>(json['framePaths']),
      jobId: serializer.fromJson<String?>(json['jobId']),
      error: serializer.fromJson<String?>(json['error']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      petType: $ClipsTable.$converterpetType.fromJson(
        serializer.fromJson<String>(json['petType']),
      ),
      breedHint: serializer.fromJson<String?>(json['breedHint']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'status': serializer.toJson<ClipStatus>(status),
      'framePaths': serializer.toJson<List<String>>(framePaths),
      'jobId': serializer.toJson<String?>(jobId),
      'error': serializer.toJson<String?>(error),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'petType': serializer.toJson<String>(
        $ClipsTable.$converterpetType.toJson(petType),
      ),
      'breedHint': serializer.toJson<String?>(breedHint),
    };
  }

  ClipRow copyWith({
    String? id,
    ClipStatus? status,
    List<String>? framePaths,
    Value<String?> jobId = const Value.absent(),
    Value<String?> error = const Value.absent(),
    DateTime? createdAt,
    PetType? petType,
    Value<String?> breedHint = const Value.absent(),
  }) => ClipRow(
    id: id ?? this.id,
    status: status ?? this.status,
    framePaths: framePaths ?? this.framePaths,
    jobId: jobId.present ? jobId.value : this.jobId,
    error: error.present ? error.value : this.error,
    createdAt: createdAt ?? this.createdAt,
    petType: petType ?? this.petType,
    breedHint: breedHint.present ? breedHint.value : this.breedHint,
  );
  ClipRow copyWithCompanion(ClipsCompanion data) {
    return ClipRow(
      id: data.id.present ? data.id.value : this.id,
      status: data.status.present ? data.status.value : this.status,
      framePaths: data.framePaths.present
          ? data.framePaths.value
          : this.framePaths,
      jobId: data.jobId.present ? data.jobId.value : this.jobId,
      error: data.error.present ? data.error.value : this.error,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      petType: data.petType.present ? data.petType.value : this.petType,
      breedHint: data.breedHint.present ? data.breedHint.value : this.breedHint,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ClipRow(')
          ..write('id: $id, ')
          ..write('status: $status, ')
          ..write('framePaths: $framePaths, ')
          ..write('jobId: $jobId, ')
          ..write('error: $error, ')
          ..write('createdAt: $createdAt, ')
          ..write('petType: $petType, ')
          ..write('breedHint: $breedHint')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    status,
    framePaths,
    jobId,
    error,
    createdAt,
    petType,
    breedHint,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ClipRow &&
          other.id == this.id &&
          other.status == this.status &&
          other.framePaths == this.framePaths &&
          other.jobId == this.jobId &&
          other.error == this.error &&
          other.createdAt == this.createdAt &&
          other.petType == this.petType &&
          other.breedHint == this.breedHint);
}

class ClipsCompanion extends UpdateCompanion<ClipRow> {
  final Value<String> id;
  final Value<ClipStatus> status;
  final Value<List<String>> framePaths;
  final Value<String?> jobId;
  final Value<String?> error;
  final Value<DateTime> createdAt;
  final Value<PetType> petType;
  final Value<String?> breedHint;
  final Value<int> rowid;
  const ClipsCompanion({
    this.id = const Value.absent(),
    this.status = const Value.absent(),
    this.framePaths = const Value.absent(),
    this.jobId = const Value.absent(),
    this.error = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.petType = const Value.absent(),
    this.breedHint = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ClipsCompanion.insert({
    required String id,
    required ClipStatus status,
    required List<String> framePaths,
    this.jobId = const Value.absent(),
    this.error = const Value.absent(),
    required DateTime createdAt,
    required PetType petType,
    this.breedHint = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       status = Value(status),
       framePaths = Value(framePaths),
       createdAt = Value(createdAt),
       petType = Value(petType);
  static Insertable<ClipRow> custom({
    Expression<String>? id,
    Expression<String>? status,
    Expression<String>? framePaths,
    Expression<String>? jobId,
    Expression<String>? error,
    Expression<DateTime>? createdAt,
    Expression<String>? petType,
    Expression<String>? breedHint,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (status != null) 'status': status,
      if (framePaths != null) 'frame_paths': framePaths,
      if (jobId != null) 'job_id': jobId,
      if (error != null) 'error': error,
      if (createdAt != null) 'created_at': createdAt,
      if (petType != null) 'pet_type': petType,
      if (breedHint != null) 'breed_hint': breedHint,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ClipsCompanion copyWith({
    Value<String>? id,
    Value<ClipStatus>? status,
    Value<List<String>>? framePaths,
    Value<String?>? jobId,
    Value<String?>? error,
    Value<DateTime>? createdAt,
    Value<PetType>? petType,
    Value<String?>? breedHint,
    Value<int>? rowid,
  }) {
    return ClipsCompanion(
      id: id ?? this.id,
      status: status ?? this.status,
      framePaths: framePaths ?? this.framePaths,
      jobId: jobId ?? this.jobId,
      error: error ?? this.error,
      createdAt: createdAt ?? this.createdAt,
      petType: petType ?? this.petType,
      breedHint: breedHint ?? this.breedHint,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(
        $ClipsTable.$converterstatus.toSql(status.value),
      );
    }
    if (framePaths.present) {
      map['frame_paths'] = Variable<String>(
        $ClipsTable.$converterframePaths.toSql(framePaths.value),
      );
    }
    if (jobId.present) {
      map['job_id'] = Variable<String>(jobId.value);
    }
    if (error.present) {
      map['error'] = Variable<String>(error.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (petType.present) {
      map['pet_type'] = Variable<String>(
        $ClipsTable.$converterpetType.toSql(petType.value),
      );
    }
    if (breedHint.present) {
      map['breed_hint'] = Variable<String>(breedHint.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ClipsCompanion(')
          ..write('id: $id, ')
          ..write('status: $status, ')
          ..write('framePaths: $framePaths, ')
          ..write('jobId: $jobId, ')
          ..write('error: $error, ')
          ..write('createdAt: $createdAt, ')
          ..write('petType: $petType, ')
          ..write('breedHint: $breedHint, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PendingUploadsTable extends PendingUploads
    with TableInfo<$PendingUploadsTable, PendingUploadRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PendingUploadsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _clipIdMeta = const VerificationMeta('clipId');
  @override
  late final GeneratedColumn<String> clipId = GeneratedColumn<String>(
    'clip_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _attemptsMeta = const VerificationMeta(
    'attempts',
  );
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
    'attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _nextAttemptAtMeta = const VerificationMeta(
    'nextAttemptAt',
  );
  @override
  late final GeneratedColumn<DateTime> nextAttemptAt =
      GeneratedColumn<DateTime>(
        'next_attempt_at',
        aliasedName,
        false,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: true,
      );
  @override
  List<GeneratedColumn> get $columns => [clipId, attempts, nextAttemptAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pending_uploads';
  @override
  VerificationContext validateIntegrity(
    Insertable<PendingUploadRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('clip_id')) {
      context.handle(
        _clipIdMeta,
        clipId.isAcceptableOrUnknown(data['clip_id']!, _clipIdMeta),
      );
    } else if (isInserting) {
      context.missing(_clipIdMeta);
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    if (data.containsKey('next_attempt_at')) {
      context.handle(
        _nextAttemptAtMeta,
        nextAttemptAt.isAcceptableOrUnknown(
          data['next_attempt_at']!,
          _nextAttemptAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_nextAttemptAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {clipId};
  @override
  PendingUploadRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PendingUploadRow(
      clipId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}clip_id'],
      )!,
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
      nextAttemptAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}next_attempt_at'],
      )!,
    );
  }

  @override
  $PendingUploadsTable createAlias(String alias) {
    return $PendingUploadsTable(attachedDatabase, alias);
  }
}

class PendingUploadRow extends DataClass
    implements Insertable<PendingUploadRow> {
  final String clipId;
  final int attempts;
  final DateTime nextAttemptAt;
  const PendingUploadRow({
    required this.clipId,
    required this.attempts,
    required this.nextAttemptAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['clip_id'] = Variable<String>(clipId);
    map['attempts'] = Variable<int>(attempts);
    map['next_attempt_at'] = Variable<DateTime>(nextAttemptAt);
    return map;
  }

  PendingUploadsCompanion toCompanion(bool nullToAbsent) {
    return PendingUploadsCompanion(
      clipId: Value(clipId),
      attempts: Value(attempts),
      nextAttemptAt: Value(nextAttemptAt),
    );
  }

  factory PendingUploadRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PendingUploadRow(
      clipId: serializer.fromJson<String>(json['clipId']),
      attempts: serializer.fromJson<int>(json['attempts']),
      nextAttemptAt: serializer.fromJson<DateTime>(json['nextAttemptAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'clipId': serializer.toJson<String>(clipId),
      'attempts': serializer.toJson<int>(attempts),
      'nextAttemptAt': serializer.toJson<DateTime>(nextAttemptAt),
    };
  }

  PendingUploadRow copyWith({
    String? clipId,
    int? attempts,
    DateTime? nextAttemptAt,
  }) => PendingUploadRow(
    clipId: clipId ?? this.clipId,
    attempts: attempts ?? this.attempts,
    nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
  );
  PendingUploadRow copyWithCompanion(PendingUploadsCompanion data) {
    return PendingUploadRow(
      clipId: data.clipId.present ? data.clipId.value : this.clipId,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      nextAttemptAt: data.nextAttemptAt.present
          ? data.nextAttemptAt.value
          : this.nextAttemptAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PendingUploadRow(')
          ..write('clipId: $clipId, ')
          ..write('attempts: $attempts, ')
          ..write('nextAttemptAt: $nextAttemptAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(clipId, attempts, nextAttemptAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PendingUploadRow &&
          other.clipId == this.clipId &&
          other.attempts == this.attempts &&
          other.nextAttemptAt == this.nextAttemptAt);
}

class PendingUploadsCompanion extends UpdateCompanion<PendingUploadRow> {
  final Value<String> clipId;
  final Value<int> attempts;
  final Value<DateTime> nextAttemptAt;
  final Value<int> rowid;
  const PendingUploadsCompanion({
    this.clipId = const Value.absent(),
    this.attempts = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PendingUploadsCompanion.insert({
    required String clipId,
    this.attempts = const Value.absent(),
    required DateTime nextAttemptAt,
    this.rowid = const Value.absent(),
  }) : clipId = Value(clipId),
       nextAttemptAt = Value(nextAttemptAt);
  static Insertable<PendingUploadRow> custom({
    Expression<String>? clipId,
    Expression<int>? attempts,
    Expression<DateTime>? nextAttemptAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (clipId != null) 'clip_id': clipId,
      if (attempts != null) 'attempts': attempts,
      if (nextAttemptAt != null) 'next_attempt_at': nextAttemptAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PendingUploadsCompanion copyWith({
    Value<String>? clipId,
    Value<int>? attempts,
    Value<DateTime>? nextAttemptAt,
    Value<int>? rowid,
  }) {
    return PendingUploadsCompanion(
      clipId: clipId ?? this.clipId,
      attempts: attempts ?? this.attempts,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (clipId.present) {
      map['clip_id'] = Variable<String>(clipId.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (nextAttemptAt.present) {
      map['next_attempt_at'] = Variable<DateTime>(nextAttemptAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PendingUploadsCompanion(')
          ..write('clipId: $clipId, ')
          ..write('attempts: $attempts, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $InsightsTable insights = $InsightsTable(this);
  late final $ClipsTable clips = $ClipsTable(this);
  late final $PendingUploadsTable pendingUploads = $PendingUploadsTable(this);
  late final InsightsDao insightsDao = InsightsDao(this as AppDatabase);
  late final ClipsDao clipsDao = ClipsDao(this as AppDatabase);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    insights,
    clips,
    pendingUploads,
  ];
}

typedef $$InsightsTableCreateCompanionBuilder = InsightsCompanion Function({
  required String id,
  required InsightType type,
  required PetType petType,
  Value<String?> breed,
  required Map<String, Object?> payload,
  required DateTime createdAt,
  Value<int> rowid,
});
typedef $$InsightsTableUpdateCompanionBuilder = InsightsCompanion Function({
  Value<String> id,
  Value<InsightType> type,
  Value<PetType> petType,
  Value<String?> breed,
  Value<Map<String, Object?>> payload,
  Value<DateTime> createdAt,
  Value<int> rowid,
});

class $$InsightsTableFilterComposer
    extends Composer<_$AppDatabase, $InsightsTable> {
  $$InsightsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<InsightType, InsightType, String> get type =>
      $composableBuilder(
        column: $table.type,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<PetType, PetType, String> get petType =>
      $composableBuilder(
        column: $table.petType,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get breed => $composableBuilder(
    column: $table.breed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<
    Map<String, Object?>,
    Map<String, Object>,
    String
  >
  get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$InsightsTableOrderingComposer
    extends Composer<_$AppDatabase, $InsightsTable> {
  $$InsightsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get petType => $composableBuilder(
    column: $table.petType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get breed => $composableBuilder(
    column: $table.breed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$InsightsTableAnnotationComposer
    extends Composer<_$AppDatabase, $InsightsTable> {
  $$InsightsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumnWithTypeConverter<InsightType, String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumnWithTypeConverter<PetType, String> get petType =>
      $composableBuilder(column: $table.petType, builder: (column) => column);

  GeneratedColumn<String> get breed =>
      $composableBuilder(column: $table.breed, builder: (column) => column);

  GeneratedColumnWithTypeConverter<Map<String, Object?>, String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$InsightsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $InsightsTable,
          InsightRow,
          $$InsightsTableFilterComposer,
          $$InsightsTableOrderingComposer,
          $$InsightsTableAnnotationComposer,
          $$InsightsTableCreateCompanionBuilder,
          $$InsightsTableUpdateCompanionBuilder,
          (
            InsightRow,
            BaseReferences<_$AppDatabase, $InsightsTable, InsightRow>,
          ),
          InsightRow,
          PrefetchHooks Function()
        > {
  $$InsightsTableTableManager(_$AppDatabase db, $InsightsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$InsightsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$InsightsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$InsightsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<InsightType> type = const Value.absent(),
                Value<PetType> petType = const Value.absent(),
                Value<String?> breed = const Value.absent(),
                Value<Map<String, Object?>> payload = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => InsightsCompanion(
                id: id,
                type: type,
                petType: petType,
                breed: breed,
                payload: payload,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required InsightType type,
                required PetType petType,
                Value<String?> breed = const Value.absent(),
                required Map<String, Object?> payload,
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => InsightsCompanion.insert(
                id: id,
                type: type,
                petType: petType,
                breed: breed,
                payload: payload,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$InsightsTable, InsightRow>(table),
                  BaseReferences<_$AppDatabase, $InsightsTable, InsightRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$InsightsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $InsightsTable,
      InsightRow,
      $$InsightsTableFilterComposer,
      $$InsightsTableOrderingComposer,
      $$InsightsTableAnnotationComposer,
      $$InsightsTableCreateCompanionBuilder,
      $$InsightsTableUpdateCompanionBuilder,
      (InsightRow, BaseReferences<_$AppDatabase, $InsightsTable, InsightRow>),
      InsightRow,
      PrefetchHooks Function()
    >;
typedef $$ClipsTableCreateCompanionBuilder = ClipsCompanion Function({
  required String id,
  required ClipStatus status,
  required List<String> framePaths,
  Value<String?> jobId,
  Value<String?> error,
  required DateTime createdAt,
  required PetType petType,
  Value<String?> breedHint,
  Value<int> rowid,
});
typedef $$ClipsTableUpdateCompanionBuilder = ClipsCompanion Function({
  Value<String> id,
  Value<ClipStatus> status,
  Value<List<String>> framePaths,
  Value<String?> jobId,
  Value<String?> error,
  Value<DateTime> createdAt,
  Value<PetType> petType,
  Value<String?> breedHint,
  Value<int> rowid,
});

class $$ClipsTableFilterComposer extends Composer<_$AppDatabase, $ClipsTable> {
  $$ClipsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<ClipStatus, ClipStatus, String> get status =>
      $composableBuilder(
        column: $table.status,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<List<String>, List<String>, String>
  get framePaths => $composableBuilder(
    column: $table.framePaths,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get jobId => $composableBuilder(
    column: $table.jobId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get error => $composableBuilder(
    column: $table.error,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<PetType, PetType, String> get petType =>
      $composableBuilder(
        column: $table.petType,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get breedHint => $composableBuilder(
    column: $table.breedHint,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ClipsTableOrderingComposer
    extends Composer<_$AppDatabase, $ClipsTable> {
  $$ClipsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get framePaths => $composableBuilder(
    column: $table.framePaths,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get jobId => $composableBuilder(
    column: $table.jobId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get error => $composableBuilder(
    column: $table.error,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get petType => $composableBuilder(
    column: $table.petType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get breedHint => $composableBuilder(
    column: $table.breedHint,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ClipsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ClipsTable> {
  $$ClipsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumnWithTypeConverter<ClipStatus, String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumnWithTypeConverter<List<String>, String> get framePaths =>
      $composableBuilder(
        column: $table.framePaths,
        builder: (column) => column,
      );

  GeneratedColumn<String> get jobId =>
      $composableBuilder(column: $table.jobId, builder: (column) => column);

  GeneratedColumn<String> get error =>
      $composableBuilder(column: $table.error, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumnWithTypeConverter<PetType, String> get petType =>
      $composableBuilder(column: $table.petType, builder: (column) => column);

  GeneratedColumn<String> get breedHint =>
      $composableBuilder(column: $table.breedHint, builder: (column) => column);
}

class $$ClipsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ClipsTable,
          ClipRow,
          $$ClipsTableFilterComposer,
          $$ClipsTableOrderingComposer,
          $$ClipsTableAnnotationComposer,
          $$ClipsTableCreateCompanionBuilder,
          $$ClipsTableUpdateCompanionBuilder,
          (ClipRow, BaseReferences<_$AppDatabase, $ClipsTable, ClipRow>),
          ClipRow,
          PrefetchHooks Function()
        > {
  $$ClipsTableTableManager(_$AppDatabase db, $ClipsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ClipsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ClipsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ClipsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<ClipStatus> status = const Value.absent(),
                Value<List<String>> framePaths = const Value.absent(),
                Value<String?> jobId = const Value.absent(),
                Value<String?> error = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<PetType> petType = const Value.absent(),
                Value<String?> breedHint = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ClipsCompanion(
                id: id,
                status: status,
                framePaths: framePaths,
                jobId: jobId,
                error: error,
                createdAt: createdAt,
                petType: petType,
                breedHint: breedHint,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required ClipStatus status,
                required List<String> framePaths,
                Value<String?> jobId = const Value.absent(),
                Value<String?> error = const Value.absent(),
                required DateTime createdAt,
                required PetType petType,
                Value<String?> breedHint = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ClipsCompanion.insert(
                id: id,
                status: status,
                framePaths: framePaths,
                jobId: jobId,
                error: error,
                createdAt: createdAt,
                petType: petType,
                breedHint: breedHint,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ClipsTable, ClipRow>(table),
                  BaseReferences<_$AppDatabase, $ClipsTable, ClipRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ClipsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ClipsTable,
      ClipRow,
      $$ClipsTableFilterComposer,
      $$ClipsTableOrderingComposer,
      $$ClipsTableAnnotationComposer,
      $$ClipsTableCreateCompanionBuilder,
      $$ClipsTableUpdateCompanionBuilder,
      (ClipRow, BaseReferences<_$AppDatabase, $ClipsTable, ClipRow>),
      ClipRow,
      PrefetchHooks Function()
    >;
typedef $$PendingUploadsTableCreateCompanionBuilder =
    PendingUploadsCompanion Function({
      required String clipId,
      Value<int> attempts,
      required DateTime nextAttemptAt,
      Value<int> rowid,
    });
typedef $$PendingUploadsTableUpdateCompanionBuilder =
    PendingUploadsCompanion Function({
      Value<String> clipId,
      Value<int> attempts,
      Value<DateTime> nextAttemptAt,
      Value<int> rowid,
    });

class $$PendingUploadsTableFilterComposer
    extends Composer<_$AppDatabase, $PendingUploadsTable> {
  $$PendingUploadsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get clipId => $composableBuilder(
    column: $table.clipId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PendingUploadsTableOrderingComposer
    extends Composer<_$AppDatabase, $PendingUploadsTable> {
  $$PendingUploadsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get clipId => $composableBuilder(
    column: $table.clipId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PendingUploadsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PendingUploadsTable> {
  $$PendingUploadsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get clipId =>
      $composableBuilder(column: $table.clipId, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => column,
  );
}

class $$PendingUploadsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PendingUploadsTable,
          PendingUploadRow,
          $$PendingUploadsTableFilterComposer,
          $$PendingUploadsTableOrderingComposer,
          $$PendingUploadsTableAnnotationComposer,
          $$PendingUploadsTableCreateCompanionBuilder,
          $$PendingUploadsTableUpdateCompanionBuilder,
          (
            PendingUploadRow,
            BaseReferences<
              _$AppDatabase,
              $PendingUploadsTable,
              PendingUploadRow
            >,
          ),
          PendingUploadRow,
          PrefetchHooks Function()
        > {
  $$PendingUploadsTableTableManager(
    _$AppDatabase db,
    $PendingUploadsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PendingUploadsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PendingUploadsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PendingUploadsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> clipId = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<DateTime> nextAttemptAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PendingUploadsCompanion(
                clipId: clipId,
                attempts: attempts,
                nextAttemptAt: nextAttemptAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String clipId,
                Value<int> attempts = const Value.absent(),
                required DateTime nextAttemptAt,
                Value<int> rowid = const Value.absent(),
              }) => PendingUploadsCompanion.insert(
                clipId: clipId,
                attempts: attempts,
                nextAttemptAt: nextAttemptAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PendingUploadsTable, PendingUploadRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $PendingUploadsTable,
                    PendingUploadRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PendingUploadsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PendingUploadsTable,
      PendingUploadRow,
      $$PendingUploadsTableFilterComposer,
      $$PendingUploadsTableOrderingComposer,
      $$PendingUploadsTableAnnotationComposer,
      $$PendingUploadsTableCreateCompanionBuilder,
      $$PendingUploadsTableUpdateCompanionBuilder,
      (
        PendingUploadRow,
        BaseReferences<_$AppDatabase, $PendingUploadsTable, PendingUploadRow>,
      ),
      PendingUploadRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$InsightsTableTableManager get insights =>
      $$InsightsTableTableManager(_db, _db.insights);
  $$ClipsTableTableManager get clips =>
      $$ClipsTableTableManager(_db, _db.clips);
  $$PendingUploadsTableTableManager get pendingUploads =>
      $$PendingUploadsTableTableManager(_db, _db.pendingUploads);
}
