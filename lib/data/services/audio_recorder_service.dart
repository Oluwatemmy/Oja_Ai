import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:record/record.dart';

import 'wav_codec.dart';

/// Captures 16 kHz mono PCM16 from the microphone — the exact format
/// Gemma's audio encoder expects — and splits long recordings into
/// <=30 s chunks cut at the quietest moment, never mid-word.
class AudioRecorderService {
  AudioRecorderService({AudioRecorder? recorder})
      : _recorder = recorder ?? AudioRecorder();

  static const int sampleRate = 16000;
  static const int bytesPerSecond = sampleRate * 2; // 16-bit mono

  /// Gemma's audio encoder processes clips up to 30 s; stay safely under.
  static const int maxChunkSeconds = 28;

  /// Hard cap so a forgotten mic can't eat all RAM (~5.5 MB at 3 min).
  static const int maxRecordSeconds = 180;

  final AudioRecorder _recorder;
  final BytesBuilder _buffer = BytesBuilder(copy: false);
  StreamSubscription<Uint8List>? _subscription;

  final _amplitudeController = StreamController<double>.broadcast();
  final _silenceController = StreamController<void>.broadcast();

  /// 0..1 loudness for the waveform UI.
  Stream<double> get amplitude => _amplitudeController.stream;

  /// Fires once when ~2.5 s of trailing silence follows speech.
  Stream<void> get endOfUtterance => _silenceController.stream;

  bool _recording = false;
  bool get isRecording => _recording;

  bool _heardSpeech = false;

  /// True once the current/last recording contained actual speech —
  /// callers should skip the agent entirely when this is false.
  bool get heardSpeech => _heardSpeech;
  int _trailingSilentMs = 0;
  bool _silenceFired = false;

  static const double _speechRms = 0.02;
  static const int _silenceHoldMs = 2500;

  Future<bool> hasPermission() => _recorder.hasPermission();

  Future<void> start() async {
    if (_recording) return;
    _buffer.clear();
    _heardSpeech = false;
    _trailingSilentMs = 0;
    _silenceFired = false;

    final stream = await _recorder.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: sampleRate,
      numChannels: 1,
      autoGain: true,
      echoCancel: true,
      noiseSuppress: true,
    ));
    _recording = true;

    _subscription = stream.listen((chunk) {
      if (_buffer.length >= maxRecordSeconds * bytesPerSecond) {
        if (!_silenceFired) {
          _silenceFired = true;
          _silenceController.add(null);
        }
        return;
      }
      _buffer.add(chunk);
      final rms = _rms(chunk);
      _amplitudeController.add(math.min(1.0, rms * 12));

      final chunkMs = (chunk.length / 2) * 1000 ~/ sampleRate;
      if (rms >= _speechRms) {
        _heardSpeech = true;
        _trailingSilentMs = 0;
      } else if (_heardSpeech) {
        _trailingSilentMs += chunkMs;
        if (_trailingSilentMs >= _silenceHoldMs && !_silenceFired) {
          _silenceFired = true;
          _silenceController.add(null);
        }
      }
    });
  }

  /// Stops the mic and returns the utterance as WAV chunks, each <=30 s.
  Future<List<Uint8List>> stop() async {
    if (!_recording) return const [];
    _recording = false;
    await _subscription?.cancel();
    _subscription = null;
    await _recorder.stop();

    final pcm = _buffer.takeBytes();
    if (pcm.isEmpty) return const [];
    return _chunkPcm(pcm)
        .map((c) => WavCodec.pcmToWav(c, sampleRate: sampleRate))
        .toList();
  }

  Future<void> cancel() async {
    if (!_recording) return;
    _recording = false;
    await _subscription?.cancel();
    _subscription = null;
    await _recorder.stop();
    _buffer.clear();
  }

  /// Splits PCM at the quietest 200 ms window near each 28 s boundary.
  static List<Uint8List> _chunkPcm(Uint8List pcm) {
    const maxChunkBytes = maxChunkSeconds * bytesPerSecond;
    if (pcm.length <= maxChunkBytes) return [pcm];

    final chunks = <Uint8List>[];
    var start = 0;
    while (pcm.length - start > maxChunkBytes) {
      // Search the last 6 s of the window for the quietest 200 ms.
      final windowEnd = start + maxChunkBytes;
      final searchStart = windowEnd - 6 * bytesPerSecond;
      const step = bytesPerSecond ~/ 5; // 200 ms
      var bestOffset = windowEnd;
      var bestRms = double.infinity;
      for (var offset = searchStart;
          offset + step <= windowEnd;
          offset += step) {
        final rms = _rms(Uint8List.sublistView(pcm, offset, offset + step));
        if (rms < bestRms) {
          bestRms = rms;
          bestOffset = offset + step ~/ 2;
        }
      }
      // Keep sample alignment (2 bytes per sample).
      bestOffset -= bestOffset % 2;
      chunks.add(Uint8List.sublistView(pcm, start, bestOffset));
      start = bestOffset;
    }
    chunks.add(Uint8List.sublistView(pcm, start));
    return chunks;
  }

  static double _rms(Uint8List chunk) {
    if (chunk.length < 2) return 0;
    final data = ByteData.sublistView(chunk);
    var sum = 0.0;
    final samples = chunk.length ~/ 2;
    for (var i = 0; i < samples; i++) {
      final sample = data.getInt16(i * 2, Endian.little) / 32768.0;
      sum += sample * sample;
    }
    return math.sqrt(sum / samples);
  }

  Future<void> dispose() async {
    await cancel();
    await _amplitudeController.close();
    await _silenceController.close();
    _recorder.dispose();
  }
}
