class EscPosStatus {
  final bool online;
  final bool coverOpen;
  final bool paperFeedButtonPressed;

  const EscPosStatus({
    required this.online,
    required this.coverOpen,
    required this.paperFeedButtonPressed,
  });

  @override
  String toString() =>
      'EscPosStatus(online: $online, coverOpen: $coverOpen, '
      'feedBtn: $paperFeedButtonPressed)';
}

// DLE EOT n=1 fixed bits: bit0=0, bit1=1, bit4=1, bit7=0
const int _fixedMask = 0x93;
const int _fixedPattern = 0x12;

EscPosStatus parseStatusByte(int byte) {
  if ((byte & _fixedMask) != _fixedPattern) {
    throw FormatException(
      'Not an ESC/POS DLE EOT 1 response: 0x${byte.toRadixString(16)}',
    );
  }
  return EscPosStatus(
    online: (byte & 0x08) == 0,
    coverOpen: (byte & 0x20) != 0,
    paperFeedButtonPressed: (byte & 0x40) != 0,
  );
}
