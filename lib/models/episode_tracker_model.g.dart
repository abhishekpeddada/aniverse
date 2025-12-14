// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'episode_tracker_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class EpisodeTrackerAdapter extends TypeAdapter<EpisodeTracker> {
  @override
  final int typeId = 6;

  @override
  EpisodeTracker read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return EpisodeTracker(
      animeId: fields[0] as String,
      animeTitle: fields[1] as String,
      lastKnownEpisodeCount: fields[2] as int,
      lastChecked: fields[3] as DateTime,
      animeImage: fields[4] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, EpisodeTracker obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.animeId)
      ..writeByte(1)
      ..write(obj.animeTitle)
      ..writeByte(2)
      ..write(obj.lastKnownEpisodeCount)
      ..writeByte(3)
      ..write(obj.lastChecked)
      ..writeByte(4)
      ..write(obj.animeImage);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EpisodeTrackerAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
