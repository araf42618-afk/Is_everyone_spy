
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';

void main() => runApp(const SpyApp());

const bg = Color(0xFF0B1020);
const panel = Color(0xFF171F35);
const purple = Color(0xFF8B5CF6);
const cyan = Color(0xFF22D3EE);

class SpyApp extends StatelessWidget {
  const SpyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IS EVERYONE SPY HERE?',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: purple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class Player {
  Player(this.id, this.name, {this.host = false});
  final String id;
  final String name;
  final bool host;

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'host': host};

  factory Player.fromJson(Map<String, dynamic> j) =>
      Player(j['id'].toString(), j['name'].toString(),
          host: j['host'] == true);
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final nameCtrl = TextEditingController();
  final ipCtrl = TextEditingController();
  final random = Random();

  final myId =
      '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(99999)}';

  ServerSocket? server;
  Socket? client;
  StreamSubscription<String>? clientSubscription;
  final Map<String, Socket> peers = {};

  List<Player> players = [];
  final Map<String, String> votes = {};

  String phase = 'home';
  String error = '';
  String hostIp = '';
  String myName = '';
  String role = '';
  String word = '';
  String category = '';
  String spyId = '';
  String spyName = '';
  String resultText = '';

  bool isHost = false;
  bool busy = false;
  bool hasVoted = false;

  int round = 1;
  int turn = 0;
  int seconds = 45;

  Timer? timer;

  final Map<String, List<String>> words = {
    'Places': [
      'Airport', 'Hospital', 'School', 'Beach',
      'Restaurant', 'Cinema', 'Library', 'Bank'
    ],
    'Food': [
      'Pizza', 'Burger', 'Mango', 'Biryani',
      'Ice cream', 'Sandwich', 'Noodles'
    ],
    'Objects': [
      'Umbrella', 'Laptop', 'Camera', 'Bicycle',
      'Watch', 'Guitar', 'Backpack'
    ],
    'Animals': [
      'Elephant', 'Dolphin', 'Tiger', 'Penguin',
      'Rabbit', 'Eagle', 'Giraffe'
    ],
  };

  @override
  void dispose() {
    timer?.cancel();
    clientSubscription?.cancel();
    client?.destroy();
    for (final s in peers.values) {
      s.destroy();
    }
    server?.close();
    nameCtrl.dispose();
    ipCtrl.dispose();
    super.dispose();
  }

  void showError(String message) {
    if (mounted) setState(() => error = message);
  }

  Future<void> createRoom() async {
    if (busy) return;

    setState(() {
      busy = true;
      error = '';
    });

    try {
      myName = nameCtrl.text.trim().isEmpty
          ? 'Host'
          : nameCtrl.text.trim();

      server = await ServerSocket.bind(
        InternetAddress.anyIPv4,
        4040,
      );

      final networks = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );

      final addresses = networks
          .expand((n) => n.addresses)
          .where((a) => !a.isLoopback)
          .map((a) => a.address)
          .toList();

      hostIp = addresses.isEmpty ? 'IP unavailable' : addresses.first;

      isHost = true;
      players = [Player(myId, myName, host: true)];
      phase = 'lobby';

      server!.listen(handleNewPeer);

      setState(() {});
    } catch (e) {
      showError('Room তৈরি করা যায়নি: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void handleNewPeer(Socket socket) {
    String buffer = '';
    String? peerId;

    socket.listen(
      (bytes) {
        buffer += utf8.decode(bytes, allowMalformed: true);

        while (buffer.contains('\n')) {
          final index = buffer.indexOf('\n');
          final line = buffer.substring(0, index).trim();
          buffer = buffer.substring(index + 1);

          if (line.isEmpty) continue;

          try {
            final data = jsonDecode(line) as Map<String, dynamic>;

            if (data['type'] == 'join') {
              final id = data['id'].toString();
              final name = data['name'].toString().trim();

              if (players.length >= 12 ||
                  players.any((p) => p.id == id)) {
                socket.write(
                  '${jsonEncode({
                    'type': 'error',
                    'message': 'Room full or duplicate player'
                  })}\n',
                );
                continue;
              }

              peerId = id;
              peers[id] = socket;

              players.add(
                Player(id, name.isEmpty ? 'Player' : name),
              );

              broadcast();
            } else if (peerId != null) {
              handleAction(peerId!, data);
            }
          } catch (_) {}
        }
      },
      onDone: () {
        if (peerId != null) {
          peers.remove(peerId);
          players.removeWhere((p) => p.id == peerId);
          votes.remove(peerId);
          broadcast();
        }
      },
      onError: (_) {
        if (peerId != null) {
          peers.remove(peerId);
          players.removeWhere((p) => p.id == peerId);
          votes.remove(peerId);
          broadcast();
        }
      },
    );
  }

  Future<void> joinRoom() async {
    if (busy) return;

    final ip = ipCtrl.text.trim();

    if (ip.isEmpty) {
      showError('Host IP Address লিখো।');
      return;
    }

    setState(() {
      busy = true;
      error = '';
    });

    try {
      myName = nameCtrl.text.trim().isEmpty
          ? 'Player'
          : nameCtrl.text.trim();

      client = await Socket.connect(
        ip,
        4040,
        timeout: const Duration(seconds: 8),
      );

      isHost = false;

      client!.write(
        '${jsonEncode({
          'type': 'join',
          'id': myId,
          'name': myName,
        })}\n',
      );

      clientSubscription = client!
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        try {
          final data = jsonDecode(line) as Map<String, dynamic>;

          if (data['type'] == 'error') {
            showError(data['message'].toString());
          } else if (data['type'] == 'state') {
            applyState(data);
          }
        } catch (_) {}
      }, onDone: () {
        showError('Host connection বিচ্ছিন্ন হয়েছে।');
      });

      setState(() => phase = 'connecting');
    } catch (e) {
      showError('Connect হয়নি। একই Wi-Fi/Hotspot ব্যবহার করো। $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void sendAction(Map<String, dynamic> data) {
    if (isHost) {
      handleAction(myId, data);
    } else {
      client?.write('${jsonEncode(data)}\n');
    }
  }

  void handleAction(String from, Map<String, dynamic> data) {
    switch (data['type']) {
      case 'start':
        if (isHost && phase == 'lobby' && players.length >= 2) {
          startGame();
        }
        break;

      case 'next':
        if (phase == 'playing') {
          turn++;

          if (turn >= players.length) {
            turn = 0;
            round++;

            if (round > 3) {
              phase = 'voting';
              timer?.cancel();
            } else {
              seconds = 45;
              startClock();
            }
          }

          broadcast();
        }
        break;

      case 'vote':
        if (phase == 'voting' &&
            !votes.containsKey(from) &&
            players.any((p) => p.id == data['target'])) {
          votes[from] = data['target'].toString();

          if (votes.length >= players.length) {
            finishGame();
          } else {
            broadcast();
          }
        }
        break;

      case 'rematch':
        if (isHost && phase == 'result') {
          timer?.cancel();
          votes.clear();
          resultText = '';
          hasVoted = false;
          round = 1;
          turn = 0;
          phase = 'lobby';
          broadcast();
        }
        break;
    }
  }

  void startGame() {
    final selectedCategory =
        words.keys.elementAt(random.nextInt(words.length));

    category = selectedCategory;
    word = words[category]![random.nextInt(words[category]!.length)];

    spyId = players[random.nextInt(players.length)].id;

    round = 1;
    turn = 0;
    seconds = 45;
    votes.clear();
    hasVoted = false;

    phase = 'playing';
    startClock();
    broadcast();
  }

  void startClock() {
    timer?.cancel();

    timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!isHost || phase != 'playing') {
        t.cancel();
        return;
      }

      if (seconds > 0) {
        seconds--;
        broadcast();
      } else {
        t.cancel();
        phase = 'voting';
        broadcast();
      }
    });
  }

  void finishGame() {
    final tally = <String, int>{};

    for (final id in votes.values) {
      tally[id] = (tally[id] ?? 0) + 1;
    }

    String accused = '';
    int highest = 0;

    tally.forEach((id, count) {
      if (count > highest) {
        highest = count;
        accused = id;
      }
    });

    final caught = accused == spyId && highest > 0;

    spyName = players
        .where((p) => p.id == spyId)
        .map((p) => p.name)
        .first;

    resultText = caught
        ? 'Excellent! Spy ধরা পড়েছে!'
        : 'Spy পালিয়ে গেছে!';

    timer?.cancel();
    phase = 'result';
    broadcast();
  }

  Map<String, dynamic> snapshot(String id) {
    final isSpy = id == spyId;

    return {
      'type': 'state',
      'phase': phase,
      'players': players.map((p) => p.toJson()).toList(),
      'round': round,
      'turn': turn,
      'seconds': seconds,
      'voteCount': votes.length,
      'myRole': phase == 'playing'
          ? (isSpy ? 'Spy' : 'Player')
          : '',
      'word': phase == 'playing' && !isSpy ? word : '',
      'category': phase == 'playing' && !isSpy ? category : '',
      'spyName': phase == 'result' ? spyName : '',
      'result': resultText,
    };
  }

  void broadcast() {
    if (!isHost) return;

    for (final entry in peers.entries.toList()) {
      try {
        entry.value.write(
          '${jsonEncode(snapshot(entry.key))}\n',
        );
      } catch (_) {}
    }

    applyState(snapshot(myId));
  }

  void applyState(Map<String, dynamic> data) {
    if (!mounted) return;

    setState(() {
      phase = data['phase'] ?? phase;

      players = (data['players'] as List? ?? [])
          .map((e) => Player.fromJson(
              Map<String, dynamic>.from(e)))
          .toList();

      round = data['round'] ?? round;
      turn = data['turn'] ?? turn;
      seconds = data['seconds'] ?? seconds;

      role = data['myRole'] ?? '';
      word = data['word'] ?? '';
      category = data['category'] ?? '';
      spyName = data['spyName'] ?? '';
      resultText = data['result'] ?? '';

      if (phase != 'voting') hasVoted = false;
    });
  }

  Widget gameButton(String label, VoidCallback? action,
      {IconData icon = Icons.arrow_forward}) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: purple,
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
        onPressed: action,
        icon: Icon(icon),
        label: Text(label,
            style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget gameCard(Widget child) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: purple.withOpacity(.35)),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: bg,
        title: const Text(
          'IS EVERYONE SPY HERE?',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        actions: [
          if (phase != 'home')
            IconButton(
              onPressed: leaveRoom,
              icon: const Icon(Icons.exit_to_app),
            ),
        ],
      ),
      body: SafeArea(
        child: screen(),
      ),
    );
  }

  Widget screen() {
    switch (phase) {
      case 'home':
        return homeScreen();
      case 'connecting':
        return const Center(child: CircularProgressIndicator());
      case 'lobby':
        return lobbyScreen();
      case 'playing':
        return playingScreen();
      case 'voting':
        return votingScreen();
      case 'result':
        return resultScreen();
      default:
        return homeScreen();
    }
  }

  Widget homeScreen() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.visibility_off, color: cyan, size: 76),
            const SizedBox(height: 15),
            const Text(
              'IS EVERYONE\nSPY HERE?',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 32, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            const Text(
              'TRUST NO ONE. FIND THE SPY.',
              style: TextStyle(color: cyan, letterSpacing: 2),
            ),
            const SizedBox(height: 28),
            gameCard(Column(
              children: [
                TextField(
                  controller: nameCtrl,
                  maxLength: 16,
                  decoration: const InputDecoration(
                    labelText: 'Your player name',
                    prefixIcon: Icon(Icons.person),
                  ),
                ),
                const SizedBox(height: 10),
                gameButton(
                  busy ? 'PLEASE WAIT' : 'CREATE ROOM',
                  busy ? null : createRoom,
                  icon: Icons.add_circle,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: ipCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Host IP Address',
                    hintText: '192.168.43.1',
                    prefixIcon: Icon(Icons.wifi),
                  ),
                ),
                const SizedBox(height: 10),
                gameButton(
                  'JOIN ROOM',
                  busy ? null : joinRoom,
                  icon: Icons.login,
                ),
              ],
            )),
            if (error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  error,
                  style: const TextStyle(color: Colors.redAccent),
                  textAlign: TextAlign.center,
                ),
              ),
            const SizedBox(height: 16),
            const Text(
              '2–12 PLAYERS • LOCAL WI-FI / HOTSPOT',
              style: TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget lobbyScreen() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Icon(Icons.groups, color: cyan, size: 58),
        const Text(
          'ROOM LOBBY',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        if (isHost)
          gameCard(Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('HOST IP ADDRESS',
                  style: TextStyle(color: cyan)),
              const SizedBox(height: 6),
              SelectableText(
                hostIp,
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const Text(
                'সবাই একই Wi-Fi / Hotspot-এ Connect করবে।',
              ),
              const Text('Port: 4040',
                  style: TextStyle(color: Colors.white54)),
            ],
          )),
        const SizedBox(height: 14),
        gameCard(Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('PLAYERS ${players.length}/12',
                style: const TextStyle(
                    color: cyan, fontWeight: FontWeight.bold)),
            ...players.map((p) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: purple,
                child: Text(p.name[0].toUpperCase()),
              ),
              title: Text(p.name),
              trailing: p.host
                  ? const Chip(label: Text('HOST'))
                  : const Icon(Icons.circle,
                      color: Colors.green, size: 10),
            )),
          ],
        )),
        const SizedBox(height: 16),
        if (isHost)
          gameButton(
            'START GAME',
            players.length >= 2
                ? () => sendAction({'type': 'start'})
                : null,
            icon: Icons.play_arrow,
          )
        else
          const Text(
            'Host-এর Game শুরু করার অপেক্ষায়...',
            textAlign: TextAlign.center,
            style: TextStyle(color: cyan),
          ),
      ],
    );
  }

  Widget playingScreen() {
    final isSpy = role == 'Spy';
    final current = players.isEmpty
        ? null
        : players[turn % players.length];

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('ROUND $round / 3',
                style: const TextStyle(
                    color: cyan, fontWeight: FontWeight.bold)),
            Chip(
              avatar: const Icon(Icons.timer, size: 16),
              label: Text('$seconds sec'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        gameCard(Column(
          children: [
            const Text('YOUR SECRET ROLE',
                style: TextStyle(
                    color: Colors.white60, letterSpacing: 2)),
            const SizedBox(height: 12),
            Icon(
              isSpy ? Icons.visibility_off : Icons.visibility,
              size: 58,
              color: isSpy ? Colors.redAccent : cyan,
            ),
            Text(
              isSpy ? 'YOU ARE THE SPY!' : 'YOU ARE NOT THE SPY',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: isSpy ? Colors.redAccent : cyan,
              ),
            ),
            const SizedBox(height: 12),
            if (isSpy)
              const Text(
                'অন্যদের কথা শুনে গোপন শব্দটি অনুমান করো।',
                textAlign: TextAlign.center,
              )
            else ...[
              Text('CATEGORY: $category',
                  style: const TextStyle(color: cyan)),
              Text(
                word,
                style: const TextStyle(
                    fontSize: 30, fontWeight: FontWeight.bold),
              ),
              const Text('শব্দটি Spy-কে বলবে না!'),
           
