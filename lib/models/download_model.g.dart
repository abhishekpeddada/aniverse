// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'download_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class DownloadAdapter extends TypeAdapter<Download> {
  @override
  final int typeId = 3;

  @override
  Download read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Download(
      id: fields[0] as String,
      animeId: fields[1] as String,
      animeTitle: fields[2] as String,
      animeImage: fields[3] as String?,
      episodeId: fields[4] as String,
      episodeNumber: fields[5] as int,
      episodeTitle: fields[6] as String?,
      downloadUrl: fields[7] as String,
      quality: fields[8] as String,
      status: fields[9] as String,
      filePath: fields[10] as String?,
      totalBytes: fields[11] as int,
      downloadedBytes: fields[12] as int,
      createdAt: fields[13] as DateTime,
      completedAt: fields[14] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, Download obj) {
    writer
      ..writeByte(15)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.animeId)
      ..writeByte(2)
      ..write(obj.animeTitle)
      ..writeByte(3)
      ..write(obj.animeImage)
      ..writeByte(4)
      ..write(obj.episodeId)
      ..writeByte(5)
      ..write(obj.episodeNumber)
      ..writeByte(6)
      ..write(obj.episodeTitle)
      ..writeByte(7)
      ..write(obj.downloadUrl)
      ..writeByte(8)
      ..write(obj.quality)
      ..writeByte(9)
      ..write(obj.status)
      ..writeByte(10)
      ..write(obj.filePath)
      ..writeByte(11)
      ..write(obj.totalBytes)
      ..writeByte(12)
      ..write(obj.downloadedBytes)
      ..writeByte(13)
      ..write(obj.createdAt)
      ..writeByte(14)
      ..write(obj.completedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DownloadAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
