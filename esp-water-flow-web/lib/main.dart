import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:html';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

List<Data> dataLog = List.empty(growable: true);
int dataLogIndex = 0;
Stream<Data>? streamData;
StreamController<Data> streamController = StreamController<Data>.broadcast();

class Data {
  DateTime dateTime = DateTime.now();
  final int millis;
  final int pulse;

  Data(this.millis, this.pulse);

  double get milliLiter => pulse * (1 / 300 * 1000); // 300 pulses = 1L

  @override
  String toString() {
    return 'Data{dateTime: $dateTime, pulse: $pulse, millis: $millis}';
  }
}

class _ChartData {
  _ChartData(this.x, this.y);
  final int x;
  final double y;
}

void main() {
  streamData = streamController.stream;

  runApp(MyApp());
}

class MyApp extends StatelessWidget {

  Future<String> getStringFromBytes(String assetKey) async {
    ByteData data = await rootBundle.load(assetKey);
    final buffer = data.buffer;
    var list = buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    return utf8.decode(list);
  }

  Future<void> simulateLogs() async {
    if (dataLog.isEmpty) {
      dataLog = (await getStringFromBytes('assets/shower.csv')).split('\n').map((e) {
            try {
              List<String> eSplited = e.split(',');
              return Data(int.parse(eSplited[0]), int.parse(eSplited[1]));
            } catch (e) {
              return null;
            }
          }).where((element) => element != null).cast<Data>().toList();
      int dataLogCount = dataLog.length;

      Timer.periodic(new Duration(milliseconds: 1000), (timer) {
        if (dataLogIndex < dataLogCount) {
          Data data = dataLog[dataLogIndex++];
          data.dateTime = DateTime.now();
          streamController.add(data);
        } else {
          dataLogIndex = 0;
        }
      });
    }
  }

  void initWebSocket() {
    WebSocketChannel.connect(
      Uri.parse('ws://' + window.location.host + '/ws'),
    ).stream.listen((e) {
      try {
        List<String> eSplited = e.split(',');
        streamController.add(Data(int.parse(eSplited[0]), int.parse(eSplited[1])));
      } catch(e) {
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    //simulateLogs();
    initWebSocket();

    return MaterialApp(
      title: 'Water Flow',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key? key}) : super(key: key);

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  StreamSubscription? dataListening;
  Timer? timer;

  double instantMilliLiterSecond = 0;
  double instantLiterMinute = 0;
  int instantPulse = 0;
  int totalPulses = 0;
  double totalLiter = 0;
  int timerSeconds = 0;
  List<_ChartData> values = List.empty(growable: true);

  @override
  void initState() {
    super.initState();
    dataListening = streamData?.listen((event) {
      setState(() {
        debugPrint(event.toString());

        instantPulse = event.pulse;
        instantMilliLiterSecond = event.milliLiter;
        instantLiterMinute = instantMilliLiterSecond * (60 / 1000);

        if (timer?.isActive == true) {
          if (values.isNotEmpty) {
            _ChartData lastChartData = values.last;
            values.add(_ChartData(event.dateTime.millisecondsSinceEpoch ~/ 1000 - 1, lastChartData.y));
          }
          values.add(_ChartData(event.dateTime.millisecondsSinceEpoch ~/ 1000, event.milliLiter));

          totalPulses += instantPulse;
          totalLiter += instantMilliLiterSecond / 1000;
        }
      });
    });
  }

  @override
  void dispose() {
    super.dispose();
    dataListening?.cancel();
    timer?.cancel();
  }

  void _toggleTimer() {
    if (timer?.isActive == true) {
      timer!.cancel();
      setState(() {});
    } else {
      timer = Timer.periodic(new Duration(milliseconds: 1000), (timer) {
        setState(() {
          timerSeconds++;
        });
      });

      setState(() {
        totalLiter = 0;
        timerSeconds = 0;
        values.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Water Flow'),
      ),
      body:
      new Column(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child:
            new Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  new Column(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: <Widget>[
                        new Text(
                          instantLiterMinute.toStringAsFixed(2) + " L/min",
                          style: new TextStyle(fontSize:70.0,
                              color: const Color(0xFF000000),
                              fontWeight: FontWeight.bold,
                              fontFamily: "Roboto"),
                        ),
                        new Text(
                          instantMilliLiterSecond.toStringAsFixed(0) + " mL/s",
                          style: new TextStyle(fontSize:50.0,
                              color: const Color(0xFF000000),
                              fontWeight: FontWeight.bold,
                              fontFamily: "Roboto"),
                        ),
                        new Text(
                          instantPulse.toStringAsFixed(0) + " pulses",
                          style: new TextStyle(fontSize:20.0,
                              fontWeight: FontWeight.w200,
                              color: const Color(0xFF000000),
                              fontFamily: "Roboto"),
                        ),
                      ]
                  ),
                  new Column(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: <Widget>[
                      new Text(
                        totalLiter.toStringAsFixed(2) + " L used",
                        style: new TextStyle(fontSize:50.0,
                          color: const Color(0xFF000000),
                          fontWeight: FontWeight.w300,
                          fontFamily: "Roboto"),
                      ),
                      new Text(
                        timerSeconds.toString() + " seconds elapsed",
                        style: new TextStyle(fontSize:30.0,
                          color: const Color(0xFF000000),
                          fontWeight: FontWeight.w300,
                          fontFamily: "Roboto"),
                      ),
                      new Text(
                        totalPulses.toStringAsFixed(0) + " total pulses",
                        style: new TextStyle(fontSize:20.0,
                            fontWeight: FontWeight.w200,
                            color: const Color(0xFF000000),
                            fontFamily: "Roboto"),
                      ),
                    ],
                  ),
                ]
            )
          ),
          Expanded(child:
            SfCartesianChart(
              plotAreaBorderWidth: 0,
              legend: Legend(
                  isVisible: false,
                  overflowMode: LegendItemOverflowMode.wrap),
              primaryYAxis: NumericAxis(
                labelFormat: '{value}',
                axisLine: const AxisLine(width: 0),
                minimum: 0,
                maximum: 100
              ),
              series: [LineSeries<_ChartData, num>(
                animationDuration: 0,
                dataSource: values,
                xValueMapper: (_ChartData sales, _) => sales.x,
                yValueMapper: (_ChartData sales, _) => sales.y,
                width: 1,
              )],
              tooltipBehavior: TooltipBehavior(enable: true),
            ),
          )
        ],
      )
      ,
      floatingActionButton: FloatingActionButton(
        onPressed: _toggleTimer,
        tooltip: timer?.isActive == true ? 'Stop measure' : 'Start measure',
        child: timer?.isActive == true ? Icon(Icons.stop) : Icon(Icons.play_arrow),
      ),
    );
  }
}
