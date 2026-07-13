/// Models for the Database Manager / Admin API.
library;

class ForeignKeyInfo {
  final String table;
  final String column;

  const ForeignKeyInfo({required this.table, required this.column});

  factory ForeignKeyInfo.fromJson(Map<String, dynamic> json) => ForeignKeyInfo(
        table: json['table'] as String,
        column: json['column'] as String,
      );
}

class ColumnInfo {
  final String name;
  final String type;
  final bool nullable;
  final bool primaryKey;
  final bool autoincrement;
  final int? maxLength;
  final ForeignKeyInfo? foreignKey;
  final List<String>? enumValues;
  final String? defaultValue;

  const ColumnInfo({
    required this.name,
    required this.type,
    this.nullable = true,
    this.primaryKey = false,
    this.autoincrement = false,
    this.maxLength,
    this.foreignKey,
    this.enumValues,
    this.defaultValue,
  });

  factory ColumnInfo.fromJson(Map<String, dynamic> json) => ColumnInfo(
        name: json['name'] as String,
        type: json['type'] as String,
        nullable: json['nullable'] as bool? ?? true,
        primaryKey: json['primary_key'] as bool? ?? false,
        autoincrement: json['autoincrement'] as bool? ?? false,
        maxLength: json['max_length'] as int?,
        foreignKey: json['foreign_key'] != null
            ? ForeignKeyInfo.fromJson(json['foreign_key'])
            : null,
        enumValues: (json['enum_values'] as List<dynamic>?)
            ?.map((e) => e as String)
            .toList(),
        defaultValue: json['default'] as String?,
      );
}

class TableInfo {
  final String name;
  final int columnCount;
  final int rowCount;

  const TableInfo({
    required this.name,
    required this.columnCount,
    required this.rowCount,
  });

  factory TableInfo.fromJson(Map<String, dynamic> json) => TableInfo(
        name: json['name'] as String,
        columnCount: json['column_count'] as int,
        rowCount: json['row_count'] as int,
      );
}

class TableSchemaModel {
  final String name;
  final List<ColumnInfo> columns;

  const TableSchemaModel({required this.name, required this.columns});

  factory TableSchemaModel.fromJson(Map<String, dynamic> json) =>
      TableSchemaModel(
        name: json['name'] as String,
        columns: (json['columns'] as List<dynamic>)
            .map((c) => ColumnInfo.fromJson(c))
            .toList(),
      );
}

class RowsResponse {
  final List<Map<String, dynamic>> rows;
  final int total;
  final int limit;
  final int offset;

  const RowsResponse({
    required this.rows,
    required this.total,
    required this.limit,
    required this.offset,
  });

  factory RowsResponse.fromJson(Map<String, dynamic> json) => RowsResponse(
        rows: (json['rows'] as List<dynamic>)
            .map((r) => Map<String, dynamic>.from(r))
            .toList(),
        total: json['total'] as int,
        limit: json['limit'] as int,
        offset: json['offset'] as int,
      );
}

class FKOption {
  final dynamic id;
  final String label;

  const FKOption({required this.id, required this.label});

  factory FKOption.fromJson(Map<String, dynamic> json) => FKOption(
        id: json['id'],
        label: json['label'] as String,
      );
}
