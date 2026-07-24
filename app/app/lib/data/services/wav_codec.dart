import 'dart:typed_data';

/// Minimal WAV writer for 16-bit PCM — Gemma's audio input format.
class WavCodec {
  static Uint8List pcmToWav(
    Uint8List pcmData, {
    int sampleRate = 16000,
    int channels = 1,
    int bitsPerSample = 16,
  }) {
    final byteRate = sampleRate * channels * (bitsPerSample ~/ 8);
    final blockAlign = channels * (bitsPerSample ~/ 8);
    final dataSize = pcmData.length;

    final header = Uint8List(44);
    final bytes = ByteData.sublistView(header);

    header.setAll(0, 'RIFF'.codeUnits);
    bytes.setUint32(4, 36 + dataSize, Endian.little);
    header.setAll(8, 'WAVE'.codeUnits);

    header.setAll(12, 'fmt '.codeUnits);
    bytes.setUint32(16, 16, Endian.little);
    bytes.setUint16(20, 1, Endian.little); // PCM
    bytes.setUint16(22, channels, Endian.little);
    bytes.setUint32(24, sampleRate, Endian.little);
    bytes.setUint32(28, byteRate, Endian.little);
    bytes.setUint16(32, blockAlign, Endian.little);
    bytes.setUint16(34, bitsPerSample, Endian.little);

    header.setAll(36, 'data'.codeUnits);
    bytes.setUint32(40, dataSize, Endian.little);

    final wav = Uint8List(44 + dataSize);
    wav.setAll(0, header);
    wav.setAll(44, pcmData);
    return wav;
  }
}
