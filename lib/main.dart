import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:developer';
//import 'package:flutter_localizations/flutter_localizations.dart';

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
  int _currentIndex = -1; // -1 означает, что ничего не играет
  bool _isPlaying = false;
  bool _isLoadingMore = false;
  final int _loadLimit = 20;
  TabController? _tabController;
  Set<int> _favoriteStations = {};
  TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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
              _tabController!.index); // По умолчанию показываем текущую вкладку
        });
      } else {
        log("Ошибка загрузки API: ${response.statusCode}");
      }
    } catch (e) {
      log("Ошибка сети: $e");
    } finally {
      if (loadMore) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  void _playPauseStation(int index) async {
    if (_filteredStations.isEmpty || index >= _filteredStations.length)
      return; // Проверяем, что индекс валиден

    if (_currentIndex == index && _isPlaying) {
      await _audioPlayer.pause();
      setState(() {
        _isPlaying = false;
      });
    } else {
      await _audioPlayer.play(UrlSource(_filteredStations[index]['url']));
      setState(() {
        _currentIndex = index;
        _isPlaying = true;
      });
    }

    // Открываем новое окно с информацией о радиостанции
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
        ),
      ),
    );
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
      // Вторая вкладка - Избранное
      setState(() {
        _filteredStations = _stations
            .asMap()
            .entries
            .where((entry) => _favoriteStations.contains(entry.key))
            .map((entry) => entry.value)
            .toList();
      });
    } else {
      // Другие вкладки - все станции
      setState(() {
        _filteredStations = _stations;
      });
    }
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

  @override
  void dispose() {
    _audioPlayer.dispose();
    _tabController?.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Online Radio"),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color.fromARGB(252, 230, 78, 78),
                Color.fromARGB(255, 242, 64, 40)
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
          ],
          indicator: BoxDecoration(
            color: Colors.red,
            borderRadius: BorderRadius.circular(25),
          ),
          labelStyle:
              const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          onTap: (index) => _filterStationsByTab(index),
        ),
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
                fillColor: const Color.fromARGB(255, 255, 255, 255),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                  borderSide: BorderSide.none,
                ),
              ),
              style: const TextStyle(color: Color.fromARGB(176, 10, 10, 10)),
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
                                  ? LinearGradient(
                                      colors: [Colors.blue, Colors.green])
                                  : LinearGradient(colors: [
                                      const Color.fromARGB(255, 255, 255, 255),
                                      const Color.fromARGB(255, 230, 222, 222)
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
                                  isActive ? Icons.radio : Icons.radio_outlined,
                                  color: const Color.fromARGB(255, 4, 4, 4),
                                  size: 30,
                                ),
                                const SizedBox(width: 15),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        station['name'] ?? 'Без названия',
                                        style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: Color.fromARGB(
                                                255, 18, 18, 18)),
                                      ),
                                      Text(
                                        station['country'] ??
                                            'Неизвестная страна',
                                        style: TextStyle(
                                            fontSize: 14,
                                            color: const Color.fromARGB(
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
    );
  }
}

class RadioStationScreen extends StatelessWidget {
  final Map<String, dynamic> station;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onPause;

  const RadioStationScreen({
    super.key,
    required this.station,
    required this.onPrevious,
    required this.onNext,
    required this.onPause,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(station['name'] ?? 'Без названия'),
        backgroundColor: const Color(0xFF2F0101),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Center(
        child: Container(
          width: 300, // Ограничиваем ширину квадрата
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color.fromARGB(252, 230, 78, 78),
                Color.fromARGB(255, 242, 64, 40)
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                station['name'] ?? 'Без названия',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold),
                textAlign: TextAlign.center, // Центрируем текст
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios,
                        color: Colors.white, size: 40),
                    onPressed: onPrevious,
                  ),
                  IconButton(
                    icon: const Icon(Icons.pause_circle_filled,
                        color: Colors.white, size: 50),
                    onPressed: onPause,
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_forward_ios,
                        color: Colors.white, size: 40),
                    onPressed: onNext,
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
