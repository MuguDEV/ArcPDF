// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pdf_annotation.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class PdfAnnotationAdapter extends TypeAdapter<PdfAnnotation> {
  @override
  final int typeId = 2;

  @override
  PdfAnnotation read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return PdfAnnotation(
      id: fields[0] as String,
      pdfPath: fields[1] as String,
      pageNumber: fields[2] as int,
      type: fields[3] as String,
      color: fields[4] as int,
      bounds: (fields[5] as List).cast<double>(),
      content: fields[6] as String?,
      createdAt: fields[7] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, PdfAnnotation obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.pdfPath)
      ..writeByte(2)
      ..write(obj.pageNumber)
      ..writeByte(3)
      ..write(obj.type)
      ..writeByte(4)
      ..write(obj.color)
      ..writeByte(5)
      ..write(obj.bounds)
      ..writeByte(6)
      ..write(obj.content)
      ..writeByte(7)
      ..write(obj.createdAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PdfAnnotationAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
