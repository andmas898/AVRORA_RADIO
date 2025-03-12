import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:async';
import 'dart:math';
import 'package:flutter/services.dart'; // Импортируем для SystemNavigator

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color.fromARGB(255, 245, 245, 245),
      ),
      home: const RadioScreen(),
    );
  }
}

class RadioScreen extends StatefulWidget {
  const RadioScreen({super.key});

  @override
  State<RadioScreen> createState() => _RadioScreenState();
}

class _RadioScreenState extends State<RadioScreen>
    with SingleTickerProviderStateMixin {
  final AudioPlayer _audioPlayer = AudioPlayer();
  List<dynamic> _stations = [];
  List<dynamic> _filteredStations = [];
  List<int> _nonFunctionalStations = [];
  List<String> _blockedStations = [
    "Dance Wave!",
    "REYFM",
    "Iran International",
    "REYFM - #original"
  ];
  int _currentIndex = -1; // -1 means nothing is playing
  bool _isPlaying = false;
  bool _isLoadingMore = false;
  final int _loadLimit = 20;
  TabController? _tabController;
  Set<int> _favoriteStations = {};
  TextEditingController _searchController = TextEditingController();
  bool _isNightMode = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this); // Изменено на 4
    fetchStations();
  }

  Future<void> fetchStations({bool loadMore = false}) async {
    if (loadMore) {
      setState(() => _isLoadingMore = true);
    }

    const apiUrl = "https://de1.api.radio-browser.info/json/stations/topvote";
    try {
      final response = await http.get(Uri.parse(apiUrl));

      if (response.statusCode == 200) {
        List<dynamic> fetchedStations = json.decode(response.body);

        setState(() {
          if (loadMore) {
            _stations.addAll(
                fetchedStations.skip(_stations.length).take(_loadLimit));
          } else {
            _stations = fetchedStations.take(_loadLimit).toList();
          }
          _filterStationsByTab(
              _tabController!.index); // Show the current tab by default
        });
      } else {
        developer.log("Ошибка загрузки API: ${response.statusCode}");
      }
    } catch (e) {
      developer.log("Ошибка сети: $e");
    } finally {
      if (loadMore) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  void _playPauseStation(int index) async {
    if (_filteredStations.isEmpty || index >= _filteredStations.length) return;

    try {
      if (_currentIndex == index && _isPlaying) {
        await _audioPlayer.pause();
        setState(() {
          _isPlaying = false;
        });
      } else {
        String url = _filteredStations[index]['urlResolved'] ??
            _filteredStations[index]['url'];
        await _audioPlayer.play(UrlSource(url));
        setState(() {
          _currentIndex = index;
          _isPlaying = true;
        });
      }

      // Open the station details screen
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => RadioStationScreen(
            station: _filteredStations[index],
            onPrevious: () => _playPauseStation(
                (index - 1 + _filteredStations.length) %
                    _filteredStations.length),
            onNext: () =>
                _playPauseStation((index + 1) % _filteredStations.length),
            onPause: () => _playPauseStation(index),
            isPlaying: _isPlaying,
            isNightMode: _isNightMode, // Передаем состояние ночного режима
          ),
        ),
      );
    } catch (e) {
      developer.log("Error playing audio: $e");
      // Handle the error, e.g., show a message to the user
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Не удалось воспроизвести радиостанцию: $e")),
      );
      // Mark the station as non-functional
      setState(() {
        _nonFunctionalStations.add(index);
      });
    }
  }

  void _nextStation() {
    if (_filteredStations.isEmpty) return;

    int nextIndex = (_currentIndex + 1) % _filteredStations.length;
    _playPauseStation(nextIndex);
  }

  void _previousStation() {
    if (_filteredStations.isEmpty) return;

    int prevIndex = (_currentIndex - 1 + _filteredStations.length) %
        _filteredStations.length;
    _playPauseStation(prevIndex);
  }

  void _toggleFavorite(int index) {
    setState(() {
      if (_favoriteStations.contains(index)) {
        _favoriteStations.remove(index);
      } else {
        _favoriteStations.add(index);
      }
      _filterStationsByTab(_tabController!.index);
    });
  }

  void _filterStationsByTab(int tabIndex) {
    if (tabIndex == 1) {
      // Favorites tab
      setState(() {
        _filteredStations = _stations
            .asMap()
            .entries
            .where((entry) => _favoriteStations.contains(entry.key))
            .map((entry) => entry.value)
            .toList();
      });
    } else if (tabIndex == 2) {
      // Recommendations tab
      setState(() {
        _filteredStations = _getRandomStations(5);
      });
    } else if (tabIndex == 3) {
      // Sleep Timer tab
      Navigator.push(
        context,
        MaterialPageRoute(
            builder: (context) => SleepTimerScreen(
                  audioPlayer: _audioPlayer,
                )),
      );
    } else {
      // All stations tab
      setState(() {
        _filteredStations = _stations
            .asMap()
            .entries
            .where((entry) =>
                !_nonFunctionalStations.contains(entry.key) &&
                !_blockedStations.contains(entry.value['name']))
            .map((entry) => entry.value)
            .toList();
      });
    }
  }

  List<dynamic> _getRandomStations(int count) {
    final random = Random();
    final List<dynamic> randomStations = [];
    final List<dynamic> first30Stations = _stations.take(30).toList();

    while (randomStations.length < count && first30Stations.isNotEmpty) {
      final index = random.nextInt(first30Stations.length);
      randomStations.add(first30Stations.removeAt(index));
    }

    return randomStations;
  }

  void _filterStations(String query) {
    if (query.isEmpty) {
      _filterStationsByTab(_tabController!.index);
      return;
    }

    List<dynamic> filtered = _stations
        .where((station) => (station['name'] as String)
            .toLowerCase()
            .startsWith(query.toLowerCase()))
        .toList();

    setState(() {
      _filteredStations = filtered;
    });
  }

  void _toggleNightMode() {
    setState(() {
      _isNightMode = !_isNightMode;
    });
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _tabController?.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // Always return to the main screen when back is pressed
        if (_tabController!.index != 0) {
          _tabController!.animateTo(0);
          return false;
        }
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Online Radio"),
          flexibleSpace: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _isNightMode
                      ? Colors.blue[700]!
                      : Color.fromARGB(252, 230, 78, 78),
                  _isNightMode
                      ? Colors.blue[400]!
                      : Color.fromARGB(255, 242, 64, 40)
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          elevation: 0,
          bottom: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: "Радиостанции"),
              Tab(text: "Избранное"),
              Tab(text: "Рекомендации"),
              Tab(text: "Таймер сна"), // Новый таб
            ],
            indicator: const UnderlineTabIndicator(
              borderSide: BorderSide(width: 2.0, color: Colors.white),
              insets: EdgeInsets.symmetric(horizontal: 16.0),
            ),
            labelStyle:
                const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            onTap: (index) => _filterStationsByTab(index),
          ),
          actions: [
            IconButton(
              icon: Icon(
                _isNightMode ? Icons.wb_sunny : Icons.nightlight_round,
                color: Colors.white,
              ),
              onPressed: _toggleNightMode,
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                controller: _searchController,
                onChanged: _filterStations,
                decoration: InputDecoration(
                  hintText: "Поиск",
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: _isNightMode
                      ? const Color.fromARGB(255, 30, 30, 30)
                      : const Color.fromARGB(255, 255, 255, 255),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(25),
                    borderSide: BorderSide.none,
                  ),
                ),
                style: TextStyle(
                    color: _isNightMode
                        ? Colors.white
                        : Color.fromARGB(176, 10, 10, 10)),
              ),
            ),
            Expanded(
              child: _filteredStations.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : NotificationListener<ScrollEndNotification>(
                      onNotification: (scrollEnd) {
                        if (scrollEnd.metrics.pixels ==
                                scrollEnd.metrics.maxScrollExtent &&
                            !_isLoadingMore) {
                          fetchStations(loadMore: true);
                        }
                        return true;
                      },
                      child: ListView.builder(
                        itemCount:
                            _filteredStations.length + (_isLoadingMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index >= _filteredStations.length) {
                            return const Padding(
                              padding: EdgeInsets.all(10.0),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }

                          final station = _filteredStations[index];
                          bool isActive = index == _currentIndex && _isPlaying;

                          return GestureDetector(
                            onTap: () => _playPauseStation(index),
                            child: Container(
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(15),
                                gradient: isActive
                                    ? LinearGradient(colors: [
                                        _isNightMode
                                            ? const Color.fromARGB(
                                                255, 0, 0, 255) // Темно-синий
                                            : const Color.fromARGB(
                                                255, 255, 0, 0), // Красный
                                        _isNightMode
                                            ? const Color.fromARGB(
                                                255, 0, 0, 200) // Темно-синий
                                            : const Color.fromARGB(
                                                255, 255, 255, 0) // Желтый
                                      ])
                                    : LinearGradient(colors: [
                                        _isNightMode
                                            ? const Color.fromARGB(
                                                255, 50, 50, 50)
                                            : const Color.fromARGB(
                                                255, 255, 255, 255),
                                        _isNightMode
                                            ? const Color.fromARGB(
                                                255, 70, 70, 70)
                                            : const Color.fromARGB(
                                                255, 230, 222, 222)
                                      ]),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.5),
                                    blurRadius: 10,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    isActive
                                        ? Icons.radio
                                        : Icons.radio_outlined,
                                    color: _isNightMode
                                        ? Colors.white
                                        : const Color.fromARGB(255, 4, 4, 4),
                                    size: 30,
                                  ),
                                  const SizedBox(width: 15),
                                  CircleAvatar(
                                    backgroundImage:
                                        NetworkImage(station['favicon'] ?? ''),
                                    radius: 20,
                                  ),
                                  const SizedBox(width: 15),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          station['name'] ?? 'Без названия',
                                          style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                              color: _isNightMode
                                                  ? Colors.white
                                                  : Color.fromARGB(
                                                      255, 18, 18, 18)),
                                        ),
                                        Text(
                                          station['country'] ??
                                              'Неизвестная страна',
                                          style: TextStyle(
                                              fontSize: 14,
                                              color: _isNightMode
                                                  ? Colors.white70
                                                  : const Color.fromARGB(
                                                      255, 16, 15, 15)),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      _favoriteStations.contains(index)
                                          ? Icons.favorite
                                          : Icons.favorite_border,
                                      color: Colors.red,
                                    ),
                                    onPressed: () => _toggleFavorite(index),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class RadioStationScreen extends StatefulWidget {
  final Map<String, dynamic> station;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onPause;
  final bool isPlaying;
  final bool isNightMode; // Добавлено поле для ночного режима

  const RadioStationScreen({
    super.key,
    required this.station,
    required this.onPrevious,
    required this.onNext,
    required this.onPause,
    required this.isPlaying,
    required this.isNightMode, // Передаем состояние ночного режима
  });

  @override
  State<RadioStationScreen> createState() => _RadioStationScreenState();
}

class _RadioStationScreenState extends State<RadioStationScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.station['name'] ?? 'Без названия'),
        backgroundColor: widget.isNightMode
            ? const Color(0xFF001F3F)
            : const Color(0xFF2F0101), // Темно-синий в ночном режиме
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Center(
        child: Container(
          width: 300, // Limit the width of the square
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                widget.isNightMode
                    ? Colors.blue[700]!
                    : Color.fromARGB(252, 230, 78, 78),
                widget.isNightMode
                    ? Colors.blue[400]!
                    : Color.fromARGB(255, 242, 64, 40)
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                backgroundImage: NetworkImage(widget.station['favicon'] ?? ''),
                radius: 40,
              ),
              const SizedBox(height: 16),
              Text(
                widget.station['name'] ?? 'Без названия',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold),
                textAlign: TextAlign.center, // Center the text
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios,
                        color: Colors.white, size: 40),
                    onPressed: widget.onPrevious,
                  ),
                  IconButton(
                    icon: Icon(
                      widget.isPlaying
                          ? Icons.pause_circle_filled
                          : Icons.play_circle_filled,
                      color: Colors.white,
                      size: 50,
                    ),
                    onPressed: widget.onPause,
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_forward_ios,
                        color: Colors.white, size: 40),
                    onPressed: widget.onNext,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Новый экран для таймера сна
class SleepTimerScreen extends StatefulWidget {
  final AudioPlayer audioPlayer; // Добавляем audioPlayer
  const SleepTimerScreen({super.key, required this.audioPlayer});

  @override
  _SleepTimerScreenState createState() => _SleepTimerScreenState();
}

class _SleepTimerScreenState extends State<SleepTimerScreen>
    with WidgetsBindingObserver {
  final TextEditingController _timerController = TextEditingController();
  Timer? _timer;
  int _remainingTime = 0; // Время в секундах

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addObserver(this); // Подписываемся на изменения состояния приложения
  }

  @override
  void dispose() {
    _timer?.cancel(); // Отменяем таймер при уничтожении виджета
    _timerController.dispose();
    WidgetsBinding.instance
        .removeObserver(this); // Отписываемся от изменений состояния приложения
    super.dispose();
  }

  void _startTimer() {
    if (_timer != null) {
      _timer!.cancel(); // Отменяем предыдущий таймер, если он существует
    }

    // Получаем время из текстового поля
    int? inputTime = int.tryParse(_timerController.text);
    if (inputTime != null && inputTime > 0) {
      setState(() {
        _remainingTime = inputTime; // Устанавливаем оставшееся время
      });

      // Запускаем таймер
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        setState(() {
          if (_remainingTime > 0) {
            _remainingTime--;
          } else {
            _timer!.cancel();
            _closeApp(); // Закрываем приложение, когда таймер истекает
          }
        });
      });
    } else {
      // Если введено некорректное значение, показываем сообщение
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Введите корректное время в секундах.")),
      );
    }
  }

  void _closeApp() {
    // Останавливаем радио
    widget.audioPlayer.stop(); // Останавливаем воспроизведение радио
    // Закрываем приложение
    Navigator.of(context).pop(); // Возвращаемся на предыдущий экран
    Future.delayed(const Duration(milliseconds: 100), () {
      // Закрываем приложение через небольшую задержку
      SystemNavigator.pop(); // Закрываем приложение
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // Приложение приостановлено, можно сохранить состояние таймера
      // Здесь можно добавить логику, если нужно
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Таймер сна"),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _timerController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                hintText: "Введите время в секундах",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _startTimer,
              child: const Text("Запустить таймер"),
            ),
            const SizedBox(height: 20),
            Text(
              _remainingTime > 0
                  ? "Оставшееся время: $_remainingTime секунд"
                  : "Таймер не запущен",
              style: const TextStyle(fontSize: 20),
            ),
          ],
        ),
      ),
    );
  }
}
