// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'watch_history_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class WatchHistoryAdapter extends TypeAdapter<WatchHistory> {
  @override
  final int typeId = 2;

  @override
  WatchHistory read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return WatchHistory(
      animeId: fields[0] as String,
      animeTitle: fields[1] as String,
      animeImage: fields[2] as String?,
      episodeNumber: fields[3] as int,
      episodeId: fields[4] as String,
      positionMs: fields[5] as int,
      durationMs: fields[6] as int,
      lastWatched: fields[7] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, WatchHistory obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.animeId)
      ..writeByte(1)
      ..write(obj.animeTitle)
      ..writeByte(2)
      ..write(obj.animeImage)
      ..writeByte(3)
      ..write(obj.episodeNumber)
      ..writeByte(4)
      ..write(obj.episodeId)
      ..writeByte(5)
      ..write(obj.positionMs)
      ..writeByte(6)
      ..write(obj.durationMs)
      ..writeByte(7)
      ..write(obj.lastWatched);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WatchHistoryAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
