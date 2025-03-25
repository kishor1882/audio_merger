import 'package:audio_merger/view/merge_audio_page.dart';
import 'package:flutter/material.dart';
import 'package:ffmpeg_kit_flutter_full/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_full/return_code.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class CutAudioPage extends StatefulWidget {
  final List<String> audioPaths; 

  CutAudioPage(this.audioPaths);

  @override
  _CutAudioPageState createState() => _CutAudioPageState();
}

class _CutAudioPageState extends State<CutAudioPage> {
  List<AudioCutInfo> audioCutInfoList = [];

  @override
  void initState() {
    super.initState();
    for (var path in widget.audioPaths) {
      audioCutInfoList.add(AudioCutInfo(
        path: path,
        filename: path.split('/').last,
        startTime: "00:00:00",
        endTime: "00:01:00", // Default 1 minute
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Cut Audio Files'),
        actions: [
          IconButton(
            icon: Icon(Icons.navigate_next),
            onPressed: () async {
              List<String> cutAudioPaths = [];

              for (var info in audioCutInfoList) {
                String outputPath = await cutAudio(info);
                if (outputPath.isNotEmpty) {
                  cutAudioPaths.add(outputPath);
                }
              }

              if (cutAudioPaths.isNotEmpty) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => MergeAudioPage(cutAudioPaths),
                  ),
                );
              }
            },
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: audioCutInfoList.length,
        itemBuilder: (context, index) {
          return AudioCutTile(
            audioCutInfo: audioCutInfoList[index],
            onInfoChanged: (updatedInfo) {
              setState(() {
                audioCutInfoList[index] = updatedInfo;
              });
            },
          );
        },
      ),
    );
  }

  Future<String> cutAudio(AudioCutInfo info) async {
    final directory = await getTemporaryDirectory();
    final outputPath = '${directory.path}/${DateTime.now().millisecondsSinceEpoch}_cut_${info.filename}';

    final command = '-i "${info.path}" -ss ${info.startTime} -to ${info.endTime} -c copy "$outputPath"';

    final session = await FFmpegKit.execute(command);
    final returnCode = await session.getReturnCode();

    if (ReturnCode.isSuccess(returnCode)) {
      return outputPath;
    } else {
      print("Error cutting audio: ${await session.getOutput()}");
      return "";
    }
  }
}

class AudioCutInfo {
  final String path;
  final String filename;
  String startTime;
  String endTime;

  AudioCutInfo({
    required this.path,
    required this.filename,
    required this.startTime,
    required this.endTime,
  });
}

class AudioCutTile extends StatelessWidget {
  final AudioCutInfo audioCutInfo;
  final Function(AudioCutInfo) onInfoChanged;

  AudioCutTile({required this.audioCutInfo, required this.onInfoChanged});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.all(8.0),
      child: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              audioCutInfo.filename,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            SizedBox(height: 8.0),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: audioCutInfo.startTime,
                    decoration: InputDecoration(labelText: 'Start Time (HH:MM:SS)'),
                    onChanged: (value) {
                      final updatedInfo = AudioCutInfo(
                        path: audioCutInfo.path,
                        filename: audioCutInfo.filename,
                        startTime: value,
                        endTime: audioCutInfo.endTime,
                      );
                      onInfoChanged(updatedInfo);
                    },
                  ),
                ),
                SizedBox(width: 16.0),
                Expanded(
                  child: TextFormField(
                    initialValue: audioCutInfo.endTime,
                    decoration: InputDecoration(labelText: 'End Time (HH:MM:SS)'),
                    onChanged: (value) {
                      final updatedInfo = AudioCutInfo(
                        path: audioCutInfo.path,
                        filename: audioCutInfo.filename,
                        startTime: audioCutInfo.startTime,
                        endTime: value,
                      );
                      onInfoChanged(updatedInfo);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}