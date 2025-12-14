// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'notification_settings_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class NotificationSettingsAdapter extends TypeAdapter<NotificationSettings> {
  @override
  final int typeId = 5;

  @override
  NotificationSettings read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return NotificationSettings(
      newEpisodeAlerts: fields[0] as bool,
      watchReminders: fields[1] as bool,
      appUpdates: fields[2] as bool,
      reminderHours: fields[3] as int,
      sound: fields[4] as bool,
      vibration: fields[5] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, NotificationSettings obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.newEpisodeAlerts)
      ..writeByte(1)
      ..write(obj.watchReminders)
      ..writeByte(2)
      ..write(obj.appUpdates)
      ..writeByte(3)
      ..write(obj.reminderHours)
      ..writeByte(4)
      ..write(obj.sound)
      ..writeByte(5)
      ..write(obj.vibration);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NotificationSettingsAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
