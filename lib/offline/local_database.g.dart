// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'local_database.dart';

// ignore_for_file: type=lint
class $CachedRecordsTable extends CachedRecords
    with TableInfo<$CachedRecordsTable, CachedRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _sourceTableMeta =
      const VerificationMeta('sourceTable');
  @override
  late final GeneratedColumn<String> sourceTable = GeneratedColumn<String>(
      'source_table', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _recordIdMeta =
      const VerificationMeta('recordId');
  @override
  late final GeneratedColumn<String> recordId = GeneratedColumn<String>(
      'record_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _dataJsonMeta =
      const VerificationMeta('dataJson');
  @override
  late final GeneratedColumn<String> dataJson = GeneratedColumn<String>(
      'data_json', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _cachedAtMeta =
      const VerificationMeta('cachedAt');
  @override
  late final GeneratedColumn<DateTime> cachedAt = GeneratedColumn<DateTime>(
      'cached_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns =>
      [id, sourceTable, recordId, dataJson, cachedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_records';
  @override
  VerificationContext validateIntegrity(Insertable<CachedRecord> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('source_table')) {
      context.handle(
          _sourceTableMeta,
          sourceTable.isAcceptableOrUnknown(
              data['source_table']!, _sourceTableMeta));
    } else if (isInserting) {
      context.missing(_sourceTableMeta);
    }
    if (data.containsKey('record_id')) {
      context.handle(_recordIdMeta,
          recordId.isAcceptableOrUnknown(data['record_id']!, _recordIdMeta));
    } else if (isInserting) {
      context.missing(_recordIdMeta);
    }
    if (data.containsKey('data_json')) {
      context.handle(_dataJsonMeta,
          dataJson.isAcceptableOrUnknown(data['data_json']!, _dataJsonMeta));
    } else if (isInserting) {
      context.missing(_dataJsonMeta);
    }
    if (data.containsKey('cached_at')) {
      context.handle(_cachedAtMeta,
          cachedAt.isAcceptableOrUnknown(data['cached_at']!, _cachedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
        {sourceTable, recordId},
      ];
  @override
  CachedRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedRecord(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      sourceTable: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}source_table'])!,
      recordId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}record_id'])!,
      dataJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}data_json'])!,
      cachedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}cached_at'])!,
    );
  }

  @override
  $CachedRecordsTable createAlias(String alias) {
    return $CachedRecordsTable(attachedDatabase, alias);
  }
}

class CachedRecord extends DataClass implements Insertable<CachedRecord> {
  final int id;
  final String sourceTable;
  final String recordId;
  final String dataJson;
  final DateTime cachedAt;
  const CachedRecord(
      {required this.id,
      required this.sourceTable,
      required this.recordId,
      required this.dataJson,
      required this.cachedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['source_table'] = Variable<String>(sourceTable);
    map['record_id'] = Variable<String>(recordId);
    map['data_json'] = Variable<String>(dataJson);
    map['cached_at'] = Variable<DateTime>(cachedAt);
    return map;
  }

  CachedRecordsCompanion toCompanion(bool nullToAbsent) {
    return CachedRecordsCompanion(
      id: Value(id),
      sourceTable: Value(sourceTable),
      recordId: Value(recordId),
      dataJson: Value(dataJson),
      cachedAt: Value(cachedAt),
    );
  }

  factory CachedRecord.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedRecord(
      id: serializer.fromJson<int>(json['id']),
      sourceTable: serializer.fromJson<String>(json['sourceTable']),
      recordId: serializer.fromJson<String>(json['recordId']),
      dataJson: serializer.fromJson<String>(json['dataJson']),
      cachedAt: serializer.fromJson<DateTime>(json['cachedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'sourceTable': serializer.toJson<String>(sourceTable),
      'recordId': serializer.toJson<String>(recordId),
      'dataJson': serializer.toJson<String>(dataJson),
      'cachedAt': serializer.toJson<DateTime>(cachedAt),
    };
  }

  CachedRecord copyWith(
          {int? id,
          String? sourceTable,
          String? recordId,
          String? dataJson,
          DateTime? cachedAt}) =>
      CachedRecord(
        id: id ?? this.id,
        sourceTable: sourceTable ?? this.sourceTable,
        recordId: recordId ?? this.recordId,
        dataJson: dataJson ?? this.dataJson,
        cachedAt: cachedAt ?? this.cachedAt,
      );
  CachedRecord copyWithCompanion(CachedRecordsCompanion data) {
    return CachedRecord(
      id: data.id.present ? data.id.value : this.id,
      sourceTable:
          data.sourceTable.present ? data.sourceTable.value : this.sourceTable,
      recordId: data.recordId.present ? data.recordId.value : this.recordId,
      dataJson: data.dataJson.present ? data.dataJson.value : this.dataJson,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedRecord(')
          ..write('id: $id, ')
          ..write('sourceTable: $sourceTable, ')
          ..write('recordId: $recordId, ')
          ..write('dataJson: $dataJson, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, sourceTable, recordId, dataJson, cachedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedRecord &&
          other.id == this.id &&
          other.sourceTable == this.sourceTable &&
          other.recordId == this.recordId &&
          other.dataJson == this.dataJson &&
          other.cachedAt == this.cachedAt);
}

class CachedRecordsCompanion extends UpdateCompanion<CachedRecord> {
  final Value<int> id;
  final Value<String> sourceTable;
  final Value<String> recordId;
  final Value<String> dataJson;
  final Value<DateTime> cachedAt;
  const CachedRecordsCompanion({
    this.id = const Value.absent(),
    this.sourceTable = const Value.absent(),
    this.recordId = const Value.absent(),
    this.dataJson = const Value.absent(),
    this.cachedAt = const Value.absent(),
  });
  CachedRecordsCompanion.insert({
    this.id = const Value.absent(),
    required String sourceTable,
    required String recordId,
    required String dataJson,
    this.cachedAt = const Value.absent(),
  })  : sourceTable = Value(sourceTable),
        recordId = Value(recordId),
        dataJson = Value(dataJson);
  static Insertable<CachedRecord> custom({
    Expression<int>? id,
    Expression<String>? sourceTable,
    Expression<String>? recordId,
    Expression<String>? dataJson,
    Expression<DateTime>? cachedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sourceTable != null) 'source_table': sourceTable,
      if (recordId != null) 'record_id': recordId,
      if (dataJson != null) 'data_json': dataJson,
      if (cachedAt != null) 'cached_at': cachedAt,
    });
  }

  CachedRecordsCompanion copyWith(
      {Value<int>? id,
      Value<String>? sourceTable,
      Value<String>? recordId,
      Value<String>? dataJson,
      Value<DateTime>? cachedAt}) {
    return CachedRecordsCompanion(
      id: id ?? this.id,
      sourceTable: sourceTable ?? this.sourceTable,
      recordId: recordId ?? this.recordId,
      dataJson: dataJson ?? this.dataJson,
      cachedAt: cachedAt ?? this.cachedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (sourceTable.present) {
      map['source_table'] = Variable<String>(sourceTable.value);
    }
    if (recordId.present) {
      map['record_id'] = Variable<String>(recordId.value);
    }
    if (dataJson.present) {
      map['data_json'] = Variable<String>(dataJson.value);
    }
    if (cachedAt.present) {
      map['cached_at'] = Variable<DateTime>(cachedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedRecordsCompanion(')
          ..write('id: $id, ')
          ..write('sourceTable: $sourceTable, ')
          ..write('recordId: $recordId, ')
          ..write('dataJson: $dataJson, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }
}

class $SyncQueueItemsTable extends SyncQueueItems
    with TableInfo<$SyncQueueItemsTable, SyncQueueItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncQueueItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _sourceTableMeta =
      const VerificationMeta('sourceTable');
  @override
  late final GeneratedColumn<String> sourceTable = GeneratedColumn<String>(
      'source_table', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _operationMeta =
      const VerificationMeta('operation');
  @override
  late final GeneratedColumn<String> operation = GeneratedColumn<String>(
      'operation', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _recordIdMeta =
      const VerificationMeta('recordId');
  @override
  late final GeneratedColumn<String> recordId = GeneratedColumn<String>(
      'record_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _payloadJsonMeta =
      const VerificationMeta('payloadJson');
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
      'payload_json', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _syncedMeta = const VerificationMeta('synced');
  @override
  late final GeneratedColumn<bool> synced = GeneratedColumn<bool>(
      'synced', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("synced" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _errorMessageMeta =
      const VerificationMeta('errorMessage');
  @override
  late final GeneratedColumn<String> errorMessage = GeneratedColumn<String>(
      'error_message', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        sourceTable,
        operation,
        recordId,
        payloadJson,
        createdAt,
        synced,
        errorMessage
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_queue_items';
  @override
  VerificationContext validateIntegrity(Insertable<SyncQueueItem> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('source_table')) {
      context.handle(
          _sourceTableMeta,
          sourceTable.isAcceptableOrUnknown(
              data['source_table']!, _sourceTableMeta));
    } else if (isInserting) {
      context.missing(_sourceTableMeta);
    }
    if (data.containsKey('operation')) {
      context.handle(_operationMeta,
          operation.isAcceptableOrUnknown(data['operation']!, _operationMeta));
    } else if (isInserting) {
      context.missing(_operationMeta);
    }
    if (data.containsKey('record_id')) {
      context.handle(_recordIdMeta,
          recordId.isAcceptableOrUnknown(data['record_id']!, _recordIdMeta));
    }
    if (data.containsKey('payload_json')) {
      context.handle(
          _payloadJsonMeta,
          payloadJson.isAcceptableOrUnknown(
              data['payload_json']!, _payloadJsonMeta));
    } else if (isInserting) {
      context.missing(_payloadJsonMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    if (data.containsKey('synced')) {
      context.handle(_syncedMeta,
          synced.isAcceptableOrUnknown(data['synced']!, _syncedMeta));
    }
    if (data.containsKey('error_message')) {
      context.handle(
          _errorMessageMeta,
          errorMessage.isAcceptableOrUnknown(
              data['error_message']!, _errorMessageMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncQueueItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncQueueItem(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      sourceTable: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}source_table'])!,
      operation: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}operation'])!,
      recordId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}record_id']),
      payloadJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}payload_json'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      synced: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}synced'])!,
      errorMessage: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}error_message']),
    );
  }

  @override
  $SyncQueueItemsTable createAlias(String alias) {
    return $SyncQueueItemsTable(attachedDatabase, alias);
  }
}

class SyncQueueItem extends DataClass implements Insertable<SyncQueueItem> {
  final int id;
  final String sourceTable;
  final String operation;
  final String? recordId;
  final String payloadJson;
  final DateTime createdAt;
  final bool synced;
  final String? errorMessage;
  const SyncQueueItem(
      {required this.id,
      required this.sourceTable,
      required this.operation,
      this.recordId,
      required this.payloadJson,
      required this.createdAt,
      required this.synced,
      this.errorMessage});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['source_table'] = Variable<String>(sourceTable);
    map['operation'] = Variable<String>(operation);
    if (!nullToAbsent || recordId != null) {
      map['record_id'] = Variable<String>(recordId);
    }
    map['payload_json'] = Variable<String>(payloadJson);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['synced'] = Variable<bool>(synced);
    if (!nullToAbsent || errorMessage != null) {
      map['error_message'] = Variable<String>(errorMessage);
    }
    return map;
  }

  SyncQueueItemsCompanion toCompanion(bool nullToAbsent) {
    return SyncQueueItemsCompanion(
      id: Value(id),
      sourceTable: Value(sourceTable),
      operation: Value(operation),
      recordId: recordId == null && nullToAbsent
          ? const Value.absent()
          : Value(recordId),
      payloadJson: Value(payloadJson),
      createdAt: Value(createdAt),
      synced: Value(synced),
      errorMessage: errorMessage == null && nullToAbsent
          ? const Value.absent()
          : Value(errorMessage),
    );
  }

  factory SyncQueueItem.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncQueueItem(
      id: serializer.fromJson<int>(json['id']),
      sourceTable: serializer.fromJson<String>(json['sourceTable']),
      operation: serializer.fromJson<String>(json['operation']),
      recordId: serializer.fromJson<String?>(json['recordId']),
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      synced: serializer.fromJson<bool>(json['synced']),
      errorMessage: serializer.fromJson<String?>(json['errorMessage']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'sourceTable': serializer.toJson<String>(sourceTable),
      'operation': serializer.toJson<String>(operation),
      'recordId': serializer.toJson<String?>(recordId),
      'payloadJson': serializer.toJson<String>(payloadJson),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'synced': serializer.toJson<bool>(synced),
      'errorMessage': serializer.toJson<String?>(errorMessage),
    };
  }

  SyncQueueItem copyWith(
          {int? id,
          String? sourceTable,
          String? operation,
          Value<String?> recordId = const Value.absent(),
          String? payloadJson,
          DateTime? createdAt,
          bool? synced,
          Value<String?> errorMessage = const Value.absent()}) =>
      SyncQueueItem(
        id: id ?? this.id,
        sourceTable: sourceTable ?? this.sourceTable,
        operation: operation ?? this.operation,
        recordId: recordId.present ? recordId.value : this.recordId,
        payloadJson: payloadJson ?? this.payloadJson,
        createdAt: createdAt ?? this.createdAt,
        synced: synced ?? this.synced,
        errorMessage:
            errorMessage.present ? errorMessage.value : this.errorMessage,
      );
  SyncQueueItem copyWithCompanion(SyncQueueItemsCompanion data) {
    return SyncQueueItem(
      id: data.id.present ? data.id.value : this.id,
      sourceTable:
          data.sourceTable.present ? data.sourceTable.value : this.sourceTable,
      operation: data.operation.present ? data.operation.value : this.operation,
      recordId: data.recordId.present ? data.recordId.value : this.recordId,
      payloadJson:
          data.payloadJson.present ? data.payloadJson.value : this.payloadJson,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      synced: data.synced.present ? data.synced.value : this.synced,
      errorMessage: data.errorMessage.present
          ? data.errorMessage.value
          : this.errorMessage,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncQueueItem(')
          ..write('id: $id, ')
          ..write('sourceTable: $sourceTable, ')
          ..write('operation: $operation, ')
          ..write('recordId: $recordId, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('synced: $synced, ')
          ..write('errorMessage: $errorMessage')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, sourceTable, operation, recordId,
      payloadJson, createdAt, synced, errorMessage);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncQueueItem &&
          other.id == this.id &&
          other.sourceTable == this.sourceTable &&
          other.operation == this.operation &&
          other.recordId == this.recordId &&
          other.payloadJson == this.payloadJson &&
          other.createdAt == this.createdAt &&
          other.synced == this.synced &&
          other.errorMessage == this.errorMessage);
}

class SyncQueueItemsCompanion extends UpdateCompanion<SyncQueueItem> {
  final Value<int> id;
  final Value<String> sourceTable;
  final Value<String> operation;
  final Value<String?> recordId;
  final Value<String> payloadJson;
  final Value<DateTime> createdAt;
  final Value<bool> synced;
  final Value<String?> errorMessage;
  const SyncQueueItemsCompanion({
    this.id = const Value.absent(),
    this.sourceTable = const Value.absent(),
    this.operation = const Value.absent(),
    this.recordId = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.synced = const Value.absent(),
    this.errorMessage = const Value.absent(),
  });
  SyncQueueItemsCompanion.insert({
    this.id = const Value.absent(),
    required String sourceTable,
    required String operation,
    this.recordId = const Value.absent(),
    required String payloadJson,
    this.createdAt = const Value.absent(),
    this.synced = const Value.absent(),
    this.errorMessage = const Value.absent(),
  })  : sourceTable = Value(sourceTable),
        operation = Value(operation),
        payloadJson = Value(payloadJson);
  static Insertable<SyncQueueItem> custom({
    Expression<int>? id,
    Expression<String>? sourceTable,
    Expression<String>? operation,
    Expression<String>? recordId,
    Expression<String>? payloadJson,
    Expression<DateTime>? createdAt,
    Expression<bool>? synced,
    Expression<String>? errorMessage,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sourceTable != null) 'source_table': sourceTable,
      if (operation != null) 'operation': operation,
      if (recordId != null) 'record_id': recordId,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (createdAt != null) 'created_at': createdAt,
      if (synced != null) 'synced': synced,
      if (errorMessage != null) 'error_message': errorMessage,
    });
  }

  SyncQueueItemsCompanion copyWith(
      {Value<int>? id,
      Value<String>? sourceTable,
      Value<String>? operation,
      Value<String?>? recordId,
      Value<String>? payloadJson,
      Value<DateTime>? createdAt,
      Value<bool>? synced,
      Value<String?>? errorMessage}) {
    return SyncQueueItemsCompanion(
      id: id ?? this.id,
      sourceTable: sourceTable ?? this.sourceTable,
      operation: operation ?? this.operation,
      recordId: recordId ?? this.recordId,
      payloadJson: payloadJson ?? this.payloadJson,
      createdAt: createdAt ?? this.createdAt,
      synced: synced ?? this.synced,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (sourceTable.present) {
      map['source_table'] = Variable<String>(sourceTable.value);
    }
    if (operation.present) {
      map['operation'] = Variable<String>(operation.value);
    }
    if (recordId.present) {
      map['record_id'] = Variable<String>(recordId.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (synced.present) {
      map['synced'] = Variable<bool>(synced.value);
    }
    if (errorMessage.present) {
      map['error_message'] = Variable<String>(errorMessage.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncQueueItemsCompanion(')
          ..write('id: $id, ')
          ..write('sourceTable: $sourceTable, ')
          ..write('operation: $operation, ')
          ..write('recordId: $recordId, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('synced: $synced, ')
          ..write('errorMessage: $errorMessage')
          ..write(')'))
        .toString();
  }
}

abstract class _$LocalDatabase extends GeneratedDatabase {
  _$LocalDatabase(QueryExecutor e) : super(e);
  $LocalDatabaseManager get managers => $LocalDatabaseManager(this);
  late final $CachedRecordsTable cachedRecords = $CachedRecordsTable(this);
  late final $SyncQueueItemsTable syncQueueItems = $SyncQueueItemsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities =>
      [cachedRecords, syncQueueItems];
}

typedef $$CachedRecordsTableCreateCompanionBuilder = CachedRecordsCompanion
    Function({
  Value<int> id,
  required String sourceTable,
  required String recordId,
  required String dataJson,
  Value<DateTime> cachedAt,
});
typedef $$CachedRecordsTableUpdateCompanionBuilder = CachedRecordsCompanion
    Function({
  Value<int> id,
  Value<String> sourceTable,
  Value<String> recordId,
  Value<String> dataJson,
  Value<DateTime> cachedAt,
});

class $$CachedRecordsTableFilterComposer
    extends Composer<_$LocalDatabase, $CachedRecordsTable> {
  $$CachedRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get sourceTable => $composableBuilder(
      column: $table.sourceTable, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get recordId => $composableBuilder(
      column: $table.recordId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get dataJson => $composableBuilder(
      column: $table.dataJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get cachedAt => $composableBuilder(
      column: $table.cachedAt, builder: (column) => ColumnFilters(column));
}

class $$CachedRecordsTableOrderingComposer
    extends Composer<_$LocalDatabase, $CachedRecordsTable> {
  $$CachedRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get sourceTable => $composableBuilder(
      column: $table.sourceTable, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get recordId => $composableBuilder(
      column: $table.recordId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get dataJson => $composableBuilder(
      column: $table.dataJson, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get cachedAt => $composableBuilder(
      column: $table.cachedAt, builder: (column) => ColumnOrderings(column));
}

class $$CachedRecordsTableAnnotationComposer
    extends Composer<_$LocalDatabase, $CachedRecordsTable> {
  $$CachedRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get sourceTable => $composableBuilder(
      column: $table.sourceTable, builder: (column) => column);

  GeneratedColumn<String> get recordId =>
      $composableBuilder(column: $table.recordId, builder: (column) => column);

  GeneratedColumn<String> get dataJson =>
      $composableBuilder(column: $table.dataJson, builder: (column) => column);

  GeneratedColumn<DateTime> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);
}

class $$CachedRecordsTableTableManager extends RootTableManager<
    _$LocalDatabase,
    $CachedRecordsTable,
    CachedRecord,
    $$CachedRecordsTableFilterComposer,
    $$CachedRecordsTableOrderingComposer,
    $$CachedRecordsTableAnnotationComposer,
    $$CachedRecordsTableCreateCompanionBuilder,
    $$CachedRecordsTableUpdateCompanionBuilder,
    (
      CachedRecord,
      BaseReferences<_$LocalDatabase, $CachedRecordsTable, CachedRecord>
    ),
    CachedRecord,
    PrefetchHooks Function()> {
  $$CachedRecordsTableTableManager(
      _$LocalDatabase db, $CachedRecordsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedRecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> sourceTable = const Value.absent(),
            Value<String> recordId = const Value.absent(),
            Value<String> dataJson = const Value.absent(),
            Value<DateTime> cachedAt = const Value.absent(),
          }) =>
              CachedRecordsCompanion(
            id: id,
            sourceTable: sourceTable,
            recordId: recordId,
            dataJson: dataJson,
            cachedAt: cachedAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String sourceTable,
            required String recordId,
            required String dataJson,
            Value<DateTime> cachedAt = const Value.absent(),
          }) =>
              CachedRecordsCompanion.insert(
            id: id,
            sourceTable: sourceTable,
            recordId: recordId,
            dataJson: dataJson,
            cachedAt: cachedAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CachedRecordsTableProcessedTableManager = ProcessedTableManager<
    _$LocalDatabase,
    $CachedRecordsTable,
    CachedRecord,
    $$CachedRecordsTableFilterComposer,
    $$CachedRecordsTableOrderingComposer,
    $$CachedRecordsTableAnnotationComposer,
    $$CachedRecordsTableCreateCompanionBuilder,
    $$CachedRecordsTableUpdateCompanionBuilder,
    (
      CachedRecord,
      BaseReferences<_$LocalDatabase, $CachedRecordsTable, CachedRecord>
    ),
    CachedRecord,
    PrefetchHooks Function()>;
typedef $$SyncQueueItemsTableCreateCompanionBuilder = SyncQueueItemsCompanion
    Function({
  Value<int> id,
  required String sourceTable,
  required String operation,
  Value<String?> recordId,
  required String payloadJson,
  Value<DateTime> createdAt,
  Value<bool> synced,
  Value<String?> errorMessage,
});
typedef $$SyncQueueItemsTableUpdateCompanionBuilder = SyncQueueItemsCompanion
    Function({
  Value<int> id,
  Value<String> sourceTable,
  Value<String> operation,
  Value<String?> recordId,
  Value<String> payloadJson,
  Value<DateTime> createdAt,
  Value<bool> synced,
  Value<String?> errorMessage,
});

class $$SyncQueueItemsTableFilterComposer
    extends Composer<_$LocalDatabase, $SyncQueueItemsTable> {
  $$SyncQueueItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get sourceTable => $composableBuilder(
      column: $table.sourceTable, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get operation => $composableBuilder(
      column: $table.operation, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get recordId => $composableBuilder(
      column: $table.recordId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get payloadJson => $composableBuilder(
      column: $table.payloadJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get synced => $composableBuilder(
      column: $table.synced, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get errorMessage => $composableBuilder(
      column: $table.errorMessage, builder: (column) => ColumnFilters(column));
}

class $$SyncQueueItemsTableOrderingComposer
    extends Composer<_$LocalDatabase, $SyncQueueItemsTable> {
  $$SyncQueueItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get sourceTable => $composableBuilder(
      column: $table.sourceTable, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get operation => $composableBuilder(
      column: $table.operation, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get recordId => $composableBuilder(
      column: $table.recordId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get payloadJson => $composableBuilder(
      column: $table.payloadJson, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get synced => $composableBuilder(
      column: $table.synced, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get errorMessage => $composableBuilder(
      column: $table.errorMessage,
      builder: (column) => ColumnOrderings(column));
}

class $$SyncQueueItemsTableAnnotationComposer
    extends Composer<_$LocalDatabase, $SyncQueueItemsTable> {
  $$SyncQueueItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get sourceTable => $composableBuilder(
      column: $table.sourceTable, builder: (column) => column);

  GeneratedColumn<String> get operation =>
      $composableBuilder(column: $table.operation, builder: (column) => column);

  GeneratedColumn<String> get recordId =>
      $composableBuilder(column: $table.recordId, builder: (column) => column);

  GeneratedColumn<String> get payloadJson => $composableBuilder(
      column: $table.payloadJson, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<bool> get synced =>
      $composableBuilder(column: $table.synced, builder: (column) => column);

  GeneratedColumn<String> get errorMessage => $composableBuilder(
      column: $table.errorMessage, builder: (column) => column);
}

class $$SyncQueueItemsTableTableManager extends RootTableManager<
    _$LocalDatabase,
    $SyncQueueItemsTable,
    SyncQueueItem,
    $$SyncQueueItemsTableFilterComposer,
    $$SyncQueueItemsTableOrderingComposer,
    $$SyncQueueItemsTableAnnotationComposer,
    $$SyncQueueItemsTableCreateCompanionBuilder,
    $$SyncQueueItemsTableUpdateCompanionBuilder,
    (
      SyncQueueItem,
      BaseReferences<_$LocalDatabase, $SyncQueueItemsTable, SyncQueueItem>
    ),
    SyncQueueItem,
    PrefetchHooks Function()> {
  $$SyncQueueItemsTableTableManager(
      _$LocalDatabase db, $SyncQueueItemsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncQueueItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncQueueItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncQueueItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> sourceTable = const Value.absent(),
            Value<String> operation = const Value.absent(),
            Value<String?> recordId = const Value.absent(),
            Value<String> payloadJson = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<bool> synced = const Value.absent(),
            Value<String?> errorMessage = const Value.absent(),
          }) =>
              SyncQueueItemsCompanion(
            id: id,
            sourceTable: sourceTable,
            operation: operation,
            recordId: recordId,
            payloadJson: payloadJson,
            createdAt: createdAt,
            synced: synced,
            errorMessage: errorMessage,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String sourceTable,
            required String operation,
            Value<String?> recordId = const Value.absent(),
            required String payloadJson,
            Value<DateTime> createdAt = const Value.absent(),
            Value<bool> synced = const Value.absent(),
            Value<String?> errorMessage = const Value.absent(),
          }) =>
              SyncQueueItemsCompanion.insert(
            id: id,
            sourceTable: sourceTable,
            operation: operation,
            recordId: recordId,
            payloadJson: payloadJson,
            createdAt: createdAt,
            synced: synced,
            errorMessage: errorMessage,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$SyncQueueItemsTableProcessedTableManager = ProcessedTableManager<
    _$LocalDatabase,
    $SyncQueueItemsTable,
    SyncQueueItem,
    $$SyncQueueItemsTableFilterComposer,
    $$SyncQueueItemsTableOrderingComposer,
    $$SyncQueueItemsTableAnnotationComposer,
    $$SyncQueueItemsTableCreateCompanionBuilder,
    $$SyncQueueItemsTableUpdateCompanionBuilder,
    (
      SyncQueueItem,
      BaseReferences<_$LocalDatabase, $SyncQueueItemsTable, SyncQueueItem>
    ),
    SyncQueueItem,
    PrefetchHooks Function()>;

class $LocalDatabaseManager {
  final _$LocalDatabase _db;
  $LocalDatabaseManager(this._db);
  $$CachedRecordsTableTableManager get cachedRecords =>
      $$CachedRecordsTableTableManager(_db, _db.cachedRecords);
  $$SyncQueueItemsTableTableManager get syncQueueItems =>
      $$SyncQueueItemsTableTableManager(_db, _db.syncQueueItems);
}
