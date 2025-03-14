import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'package:flutter/services.dart'; // Импортируем для SystemNavigator
//import 'package:shared_preferences/shared_preferences.dart';
//import 'dart:isolate';


void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.light().copyWith(
        scaffoldBackgroundColor: Colors.white, // Фон в дневном режиме
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
  final List<int> _nonFunctionalStations = [];
  final List<String> _blockedStations = [
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
  final Set<int> _favoriteStations = {};
  final TextEditingController _searchController = TextEditingController();
  bool _isNightMode = false;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    fetchStations();
  }

  Future<void> fetchStations({bool loadMore = false}) async {
    if (loadMore && _isLoadingMore) return;

    setState(() => _isLoadingMore = true);

    final apiUrl =
        "https://de1.api.radio-browser.info/json/stations/topvote?limit=${_loadLimit}&offset=${_page * _loadLimit}";
    try {
      final response = await http.get(Uri.parse(apiUrl));

      if (response.statusCode == 200) {
        List<dynamic> fetchedStations = json.decode(response.body);

        setState(() {
          if (loadMore) {
            _stations.addAll(fetchedStations);
          } else {
            _stations = fetchedStations;
          }
          _filterStationsByTab(_tabController!.index);
          _isLoadingMore = false;
        });
      } else {
        print("Ошибка загрузки API: ${response.statusCode}");
        setState(() => _isLoadingMore = false);
      }
    } catch (e) {
      print("Ошибка сети: $e");
      setState(() => _isLoadingMore = false);
    }
  }

 void _playPauseStation(int index) async {
  if (_filteredStations.isEmpty || index >= _filteredStations.length) return;

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

  // Обновляем состояние текущей радиостанции
  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        backgroundColor: _isNightMode
            ? const Color(0xFF6D0108)
            : const Color(0xFFF0302E),
        title: Center(
          child: Text(
            _filteredStations[index]['name'] ?? 'Без названия',
            textAlign: TextAlign.center,
          ),
        ),
        content: Container(
          width: 300,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                _isNightMode
                    ? const Color(0xFF6D0108)
                    : const Color(0xFFF0302E),
                _isNightMode
                    ? const Color(0xFF90013F)
                    : const Color(0xFFFE533E),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                backgroundImage:
                    NetworkImage(_filteredStations[index]['favicon'] ?? ''),
                radius: 40,
              ),
              const SizedBox(height: 16),
              Text(
                _filteredStations[index]['country'] ?? 'Неизвестная страна',
                style: const TextStyle(fontSize: 16, color: Colors.white),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                    onPressed: () {
                      _playPauseStation(
                          (index - 1 + _filteredStations.length) %
                              _filteredStations.length);
                      Navigator.of(context).pop(); // Закрываем диалог
                    },
                  ),
                  IconButton(
                    icon: Icon(
                      _isPlaying
                          ? Icons.pause_circle_filled
                          : Icons.play_circle_filled,
                      color: Colors.white,
                      size: 50,
                    ),
                    onPressed: () {
                      _playPauseStation(index);
                      Navigator.of(context).pop(); // Закрываем диалог
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_forward_ios, color: Colors.white),
                    onPressed: () {
                      _playPauseStation(
                          (index + 1) % _filteredStations.length);
                      Navigator.of(context).pop(); // Закрываем диалог
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [IconButton(
                                      icon: Icon(
                                        _favoriteStations.contains(index)
                                            ? Icons.favorite
                                            : Icons.favorite_border,
                                        color: const Color.fromARGB(255, 250, 249, 249),
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          if (_favoriteStations
                                              .contains(index)) {
                                            _favoriteStations.remove(index);
                                          } else {
                                            _favoriteStations.add(index);
                                          }
                                          _filterStationsByTab(
                                              _tabController!.index);
                                        });
                                      },
                                    ),
              IconButton(
                icon: Icon(Icons.access_time, color: Colors.white),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (BuildContext context) {
                      int selectedMinutes = 0;
                      int selectedSeconds = 0;

                      return AlertDialog(
                        backgroundColor: Colors.white,
                        title: Text("Таймер сна",
                            style: TextStyle(color: Colors.black)),
                        content: StatefulBuilder(
                          builder: (BuildContext context, StateSetter setState) {
                            return Container(
                              width: 300,
                              height: 200,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text("Настройте таймер сна",
                                      style: TextStyle(color: Colors.black)),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Container(
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(5),
                                        ),
                                        child: DropdownButton<int>(
                                          value: selectedMinutes,
                                          dropdownColor: Colors.white,
                                          items: List.generate(121, (index) => index)
                                              .map((int value) {
                                            return DropdownMenuItem<int>(
                                              value: value,
                                              child: Text("$value минут",
                                                  style: TextStyle(
                                                      color: Colors.black)),
                                            );
                                          }).toList(),
                                          onChanged: (int? newValue) {
                                            if (newValue != null) {
                                              setState(() {
                                                selectedMinutes = newValue;
                                              });
                                            }
                                          },
                                        ),
                                      ),
                                      SizedBox(width: 20),
                                      Container(
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(5),
                                        ),
                                        child: DropdownButton<int>(
                                          value: selectedSeconds,
                                          dropdownColor: Colors.white,
                                          items: List.generate(60, (index) => index)
                                              .map((int value) {
                                            return DropdownMenuItem<int>(
                                              value: value,
                                              child: Text("$value секунд",
                                                  style: TextStyle(
                                                      color: Colors.black)),
                                            );
                                          }).toList(),
                                          onChanged: (int? newValue) {
                                            if (newValue != null) {
                                              setState(() {
                                                selectedSeconds = newValue;
                                              });
                                            }
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: 20),
                                  Text(
                                      "Выбрано: $selectedMinutes минут и $selectedSeconds секунд",
                                      style: TextStyle(color: Colors.black)),
                                ],
                              ),
                            );
                          },
                        ),
                        actions: [
                          TextButton(
                            child: Text("Свернуть",
                                style: TextStyle(color: Colors.black)),
                            onPressed: () {
                              Navigator.of(context).pop();
                            },
                          ),
                          TextButton(
                            child: Text("Установить",
                                style: TextStyle(color: Colors.black)),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => SleepTimerScreen(
                                    audioPlayer: _audioPlayer,
                                    minutes: selectedMinutes,
                                    seconds: selectedSeconds,
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      );
                    },
                  );
                },
              ),],),
            ],
          ),
        )
  );});
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
    } else {
      // All stations tab
      setState(() {
        _filteredStations = _stations
            .where((station) =>
                !_nonFunctionalStations.contains(_stations.indexOf(station)) &&
                !_blockedStations.contains(station['name']))
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
            .contains(query.toLowerCase()))
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
    return WillPopScope(
      onWillPop: () async {
        if (_tabController!.index != 0) {
          _tabController!.animateTo(0);
          return false;
        }
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor:
              _isNightMode ? const Color(0xFF670000) : const Color(0xFFF0302E),
          title: Center(
            child: const Text(
              "Online Radio",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white, // Цвет текста белый
              ),
            ),
          ),
          bottom: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: "Радиостанции"),
              Tab(text: "Избранное"),
              Tab(text: "Рекомендации"),
            ],
            indicator: const UnderlineTabIndicator(
              borderSide: BorderSide(width: 2.0, color: Colors.white),
              insets: EdgeInsets.symmetric(horizontal: 16.0),
            ),
            labelStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white), // Цвет текста табов белый
            onTap: (index) => _filterStationsByTab(index),
          ),
          actions: [
            IconButton(
              icon: Icon(
                _isNightMode ? Icons.wb_sunny : Icons.nightlight_round,
                color: Colors.white,
              ),
              onPressed: () {
                setState(() {
                  _isNightMode = !_isNightMode;
                });
              },
            ),
            
            
          ],
        ),
        body: Container(
          color: _isNightMode
              ? const Color(0xFF2F0101)
              : Colors.white, // Фон в зависимости от режима
          child: Column(
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
                    ? Center(
                        child: _tabController!.index == 1
                            ? Text("Вы пока ничего не выбрали",
                                style: TextStyle(
                                    color: _isNightMode
                                        ? Colors.white
                                        : Colors.black))
                            : CircularProgressIndicator(),
                      )
                    : NotificationListener<ScrollEndNotification>(
                        onNotification: (scrollEnd) {
                          if (scrollEnd.metrics.pixels ==
                                  scrollEnd.metrics.maxScrollExtent &&
                              !_isLoadingMore) {
                            _page++;
                            fetchStations(loadMore: true);
                          }
                          return true;
                        },
                        child: ListView.builder(
                          itemCount: _filteredStations.length +
                              (_isLoadingMore ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index >= _filteredStations.length) {
                              return const Padding(
                                padding: EdgeInsets.all(10.0),
                                child:
                                    Center(child: CircularProgressIndicator()),
                              );
                            }

                            final station = _filteredStations[index];
                            bool isActive =
                                index == _currentIndex && _isPlaying;

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
                                                  255, 139, 4, 4)
                                              : const Color.fromARGB(
                                                  255, 255, 0, 0),
                                          _isNightMode
                                              ? const Color.fromARGB(
                                                  255, 73, 5, 5)
                                              : const Color.fromARGB(
                                                  255, 255, 255, 0)
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
                                      backgroundImage: NetworkImage(
                                          station['favicon'] ?? ''),
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
                                                    : Color.fromARGB(
                                                        255, 10, 10, 10)),
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
                                      onPressed: () {
                                        setState(() {
                                          if (_favoriteStations
                                              .contains(index)) {
                                            _favoriteStations.remove(index);
                                          } else {
                                            _favoriteStations.add(index);
                                          }
                                          _filterStationsByTab(
                                              _tabController!.index);
                                        });
                                      },
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
      ),
    );
  }
}



class SleepTimerScreen extends StatefulWidget {
  final AudioPlayer audioPlayer;
  final int minutes;
  final int seconds;

  const SleepTimerScreen({
    super.key,
    required this.audioPlayer,
    required this.minutes,
    required this.seconds,
  });

  @override
  _SleepTimerScreenState createState() => _SleepTimerScreenState();
}

class _SleepTimerScreenState extends State<SleepTimerScreen>
    with WidgetsBindingObserver {
  Timer? _timer;
  int _remainingTime = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _remainingTime = widget.minutes * 60 + widget.seconds;
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          if (_remainingTime > 0) {
            _remainingTime--;
          } else {
            _timer!.cancel();
            _closeApp();
          }
        });
      }
    });
  }

  void _closeApp() {
    widget.audioPlayer.stop();
    Navigator.of(context).pop();
    Future.delayed(const Duration(milliseconds: 100), () {
      SystemNavigator.pop();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // Приложение свернуто, таймер продолжает работать
      print("Приложение свернуто, таймер продолжает работать");
    } else if (state == AppLifecycleState.resumed) {
      // Приложение снова активно
      print("Приложение активно");
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
            Text(
              _remainingTime > 0
                  ? "Оставшееся время: $_remainingTime секунд"
                  : "Таймер не запущен",
              style: const TextStyle(fontSize: 20),
            ),
            const SizedBox(height: 20),
            TextButton(
              child: Text("Свернуть", style: TextStyle(color: Colors.black)),
              onPressed: () {
                // Просто возвращаемся на предыдущий экран
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
      ),
    );
  }
}
