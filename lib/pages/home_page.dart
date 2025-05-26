import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sign_x/pages/loading.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:video_player/video_player.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool isListening = false;
  String translatedText = '';
  String recognizedText = '';
  String tamilScriptText = '';
  bool isProcessing = false;

  final SpeechToText _speechToText = SpeechToText();
  VideoPlayerController? _videoController;

  final Map<String, String> phoneticMap = {
    'vanakkam': 'வணக்கம்',
    'nandri': 'நன்றி',
    'kaalai': 'காலை',
    'malai': 'மாலை',
    'poimai': 'பொம்மை',
    'sindhikka': 'சிந்திக்க',
    'sari': 'சரி',
    'romba nandri ': 'ரொம்ப நன்றி',
    'enakku': 'எனக்கு',
    'ungalukku': 'உங்களுக்கு',
    'yeppadi': 'எப்படி',
    'irukkirathu': 'இருக்கிறது',
    'naan': 'நான்',
    'neenga': 'நீங்கள்',
    'avan': 'அவன்',
    'aval': 'அவள்',
    'namma': 'நம்ம',
    'vela': 'வேல',
    'poga': 'போக',
    'vandhen': 'வந்தேன்',
    'kudukka': 'கொடுக்க',
    'vanakkam nanri': 'வணக்கம் நன்றி',
    'yeppadi irukkirathu': 'எப்படி இருக்கிறது',
    'neenga epadi': 'நீங்கள் எப்படி',
    'naan vandhen': 'நான் வந்தேன்',
    'naan pesa poren': 'நான் பேசப் போறேன்',
    'rendu mani neram': 'ரெண்டு மணி நேரம்',
    'ondru': 'ஒன்று',
    'irandu': 'இரண்டு',
    'moondru': 'மூன்று',
    'naalu': 'நாலை',
    'aindhu': 'ஐந்து',
    'naalai': 'நாளை',
    'nelayam': 'நேரம்',
    'neram': 'நேரம்',
  };

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _initSpeech() async {
    await Permission.microphone.request();
    await Permission.speech.request();

    await _speechToText.initialize(
      onStatus: (status) => print('🔊 Status: $status'),
      onError: (error) => print('⚠️ Error: $error'),
    );
  }

  Future<String> translateTextMLKit(String text) async {
    final onDeviceTranslator = OnDeviceTranslator(
      sourceLanguage: TranslateLanguage.tamil,
      targetLanguage: TranslateLanguage.english,
    );

    try {
      final translated = await onDeviceTranslator.translateText(text);
      await onDeviceTranslator.close();
      return translated;
    } catch (e) {
      print('⛔ ML Kit Translation error: $e');
      return 'Translation error!';
    }
  }

  int _levenshteinDistance(String s, String t) {
    if (s == t) return 0;
    if (s.isEmpty) return t.length;
    if (t.isEmpty) return s.length;

    List<List<int>> v =
        List.generate(s.length + 1, (_) => List.filled(t.length + 1, 0));

    for (int i = 0; i <= s.length; i++) v[i][0] = i;
    for (int j = 0; j <= t.length; j++) v[0][j] = j;

    for (int i = 1; i <= s.length; i++) {
      for (int j = 1; j <= t.length; j++) {
        int cost = (s[i - 1] == t[j - 1]) ? 0 : 1;
        v[i][j] = [
          v[i - 1][j] + 1,
          v[i][j - 1] + 1,
          v[i - 1][j - 1] + cost,
        ].reduce((a, b) => a < b ? a : b);
      }
    }
    return v[s.length][t.length];
  }

  double similarity(String s1, String s2) {
    s1 = s1.toLowerCase();
    s2 = s2.toLowerCase();
    int maxLen = s1.length > s2.length ? s1.length : s2.length;
    if (maxLen == 0) return 1.0;
    int distance = _levenshteinDistance(s1, s2);
    return (maxLen - distance) / maxLen;
  }

  String applyFuzzyMatching(String recognized) {
    List<String> words = recognized.toLowerCase().split(' ');
    List<String> fixedWords = [];

    for (var word in words) {
      String bestMatch = word;
      double bestScore = 0.0;

      for (var key in phoneticMap.keys) {
        double score = similarity(word, key);
        if (score > bestScore) {
          bestScore = score;
          bestMatch = key;
        }
      }

      fixedWords.add(bestScore >= 0.4 ? bestMatch : word);
    }

    return fixedWords.join(' ');
  }

  String phoneticToTamil(String input) {
    final words = input.toLowerCase().trim().split(' ');
    final converted = words.map((w) => phoneticMap[w] ?? w).join(' ');
    return converted;
  }

  Future<void> playVideoForWord(String word) async {
    try {
      final fileName = '${word.toLowerCase()}.mp4';
      final ref = FirebaseStorage.instance.ref().child('videos/$fileName');
      final url = await ref.getDownloadURL();

      _videoController?.dispose();
      _videoController = VideoPlayerController.network(url);
      await _videoController!.initialize();
      _videoController!.play();

      setState(() {});
    } catch (e) {
      print("🎥 Video not found for: $word - $e");
      _videoController?.dispose();
      _videoController = null;
      setState(() {});
    }
  }

  Future<void> _onMicPressed() async {
    if (!_speechToText.isAvailable) {
      print("❌ Speech not available.");
      return;
    }

    if (!isListening) {
      setState(() {
        translatedText = "Listening...";
        recognizedText = "";
        tamilScriptText = "";
        isListening = true;
      });

      _speechToText.listen(
        onResult: (result) async {
          if (result.finalResult) {
            recognizedText = result.recognizedWords;
            print("Final recognized: $recognizedText");

            String fixedRecognized = applyFuzzyMatching(recognizedText);

            setState(() {
              isListening = false;
              translatedText = "";
              tamilScriptText = phoneticToTamil(fixedRecognized);
              isProcessing = true;
            });

            final translated = await translateTextMLKit(tamilScriptText);

            setState(() {
              translatedText = translated;
              isProcessing = false;
            });

            if (translated.isNotEmpty) {
              final firstWord = translated.split(' ').first.toLowerCase();
              await playVideoForWord(firstWord);
            }
          }
        },
        localeId: "ta_IN",
      );
    } else {
      await _speechToText.stop();
      setState(() {
        isListening = false;
        translatedText = "Stopped listening.";
      });
    }
  }

  void _logout() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const LoadingPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.grey[300],
        title: const Text("SignX", style: TextStyle(color: Colors.black)),
        centerTitle: true,
        elevation: 0,
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'logout') {
                _logout();
              }
            },
            itemBuilder: (BuildContext context) {
              return const [
                PopupMenuItem(
                  value: 'logout',
                  child: Text('Logout'),
                ),
              ];
            },
            icon: const Icon(Icons.more_vert, color: Colors.black),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (tamilScriptText.isNotEmpty)
                Text(
                  "Recognized:\n$tamilScriptText",
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.deepPurple,
                  ),
                  textAlign: TextAlign.center,
                ),
              if (translatedText.isNotEmpty)
                Text(
                  "Translated (English):\n$translatedText",
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              const SizedBox(height: 20),
              Container(
                height: 250,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: _videoController != null &&
                          _videoController!.value.isInitialized
                      ? AspectRatio(
                          aspectRatio: _videoController!.value.aspectRatio,
                          child: VideoPlayer(_videoController!),
                        )
                      : const Text("Video will play here"),
                ),
              ),
              const SizedBox(height: 40),
              IconButton(
                icon: Icon(
                  isListening ? Icons.mic : Icons.mic_none,
                  size: 50,
                  color: Colors.deepPurple,
                ),
                onPressed: _onMicPressed,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
