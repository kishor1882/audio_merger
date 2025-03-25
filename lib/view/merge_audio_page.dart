import 'package:flutter/material.dart';
import 'package:ffmpeg_kit_flutter_full/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_full/return_code.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cross_file/cross_file.dart';  // For XFile
class MergeAudioPage extends StatefulWidget {
  final List<String> cutAudioPaths;

  MergeAudioPage(this.cutAudioPaths);

  @override 
  _MergeAudioPageState createState() => _MergeAudioPageState();
}

class _MergeAudioPageState extends State<MergeAudioPage> {
  bool isMerging = false;
  String? mergedFilePath;
  String outputFormat = 'mp3';
  List<String> availableFormats = ['mp3', 'wav', 'aac', 'm4a'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Merge Audio Files'),
      ),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Selected Audio Files (${widget.cutAudioPaths.length}):',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            SizedBox(height: 8.0),
            Expanded(
              child: ListView.builder(
                itemCount: widget.cutAudioPaths.length,
                itemBuilder: (context, index) {
                  return ListTile(
                    leading: Icon(Icons.audio_file),
                    title: Text(widget.cutAudioPaths[index].split('/').last),
                  );
                },
              ),
            ),
            Divider(),
            Row(
              children: [
                Text('Output Format: '),
                SizedBox(width: 8.0),
                DropdownButton<String>(
                  value: outputFormat,
                  items: availableFormats
                      .map((format) => DropdownMenuItem<String>(
                    value: format,
                    child: Text(format),
                  ))
                      .toList(),
                  onChanged: (value) {
                    setState(() {
                      outputFormat = value!;
                    });
                  },
                ),
              ],
            ),
            SizedBox(height: 16.0),
            Center(
              child: Column(
                children: [
                  ElevatedButton(
                    onPressed: isMerging || mergedFilePath != null
                        ? null
                        : () => mergeAudio(),
                    child: Text('Merge Audio Files'),
                  ),
                  SizedBox(height: 16.0),
                  if (isMerging)
                    Column(
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 8.0),
                        Text('Merging audio files...'),
                      ],
                    ),
                  if (mergedFilePath != null)
                    Column(
                      children: [
                        Text('Merge completed!'),
                        SizedBox(height: 8.0),
                        ElevatedButton(
                          onPressed: () => downloadFile(),
                          child: Text('Download Merged Audio'),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> mergeAudio() async {
    setState(() {
      isMerging = true;
    });

    try {
      final directory = await getTemporaryDirectory();
      final outputPath =
          '${directory.path}/merged_audio_${DateTime.now().millisecondsSinceEpoch}.$outputFormat';

      // Create input file list for FFmpeg with explicit ordering
      final inputFileListPath = '${directory.path}/input_files.txt';
      final inputFile = File(inputFileListPath);

      // Build the content with clear ordering
      String fileContent = '';
      for (int i = 0; i < widget.cutAudioPaths.length; i++) {
        String path = widget.cutAudioPaths[i];
        // Normalize path slashes for compatibility
        String normalizedPath = path.replaceAll('\\', '/');

        // Check if file exists and log its details
        bool fileExists = await File(normalizedPath).exists();
        int fileSize = fileExists ? await File(normalizedPath).length() : 0;
        print("File $i: $normalizedPath");
        print("Exists: $fileExists, Size: $fileSize bytes");

        // Make sure to escape single quotes in paths for FFmpeg
        String escapedPath = normalizedPath.replaceAll("'", "'\\''");
        fileContent += "file '$escapedPath'\n";
        print("Added to list - Song ${i+1}: ${escapedPath.split('/').last}");
      }

      // Make sure there's no trailing newline
      fileContent = fileContent.trimRight();

      await inputFile.writeAsString(fileContent);

      // Log for debugging
      print("Input file content:\n${await inputFile.readAsString()}");
      print("Output path: $outputPath");

      // Check if all input files exist and are readable
      bool allFilesExist = true;
      List<String> missingFiles = [];
      for (String path in widget.cutAudioPaths) {
        File file = File(path);
        if (!await file.exists()) {
          print("File doesn't exist: $path");
          missingFiles.add(path);
          allFilesExist = false;
        }
      }

      if (!allFilesExist) {
        throw Exception("Missing input files: ${missingFiles.join(', ')}");
      }

      // Always use the filter_complex approach first as it's more reliable for this task
      await mergeAudioWithFilterComplex(outputPath);

      // Verify output file exists and has content
      File outputFile = File(outputPath);
      if (await outputFile.exists() && await outputFile.length() > 0) {
        setState(() {
          mergedFilePath = outputPath;
        });
        print("Merge successful! Output at: $outputPath");
      } else {
        throw Exception("Output file is empty or doesn't exist");
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
      print("Exception: $e");

      // If the first method fails, try alternative method
      try {
        print("First method failed, trying alternative approach with concat demuxer...");
        final directory = await getTemporaryDirectory();
        final outputPath =
            '${directory.path}/merged_audio_alt_${DateTime.now().millisecondsSinceEpoch}.$outputFormat';
        await mergeAudioWithConcatDemuxer(outputPath);
      } catch (e2) {
        print("Alternative method also failed: $e2");
      }
    } finally {
      setState(() {
        isMerging = false;
      });
    }
  }

// Primary merging method using filter_complex
  Future<void> mergeAudioWithFilterComplex(String outputPath) async {
    try {
      // Build individual input arguments with proper escaping
      List<String> commandParts = [];

      // Add each input file as a separate argument
      for (int i = 0; i < widget.cutAudioPaths.length; i++) {
        commandParts.add('-i');
        commandParts.add('"${widget.cutAudioPaths[i]}"');
        print("Filter complex method - Song ${i+1}: ${widget.cutAudioPaths[i].split('/').last}");
      }

      // Build filter complex string preserving order
      String filterComplex = '';
      for (int i = 0; i < widget.cutAudioPaths.length; i++) {
        filterComplex += '[$i:a]';
      }
      filterComplex += 'concat=n=${widget.cutAudioPaths.length}:v=0:a=1[out]';

      // Add filter complex and output mapping
      commandParts.add('-filter_complex');
      commandParts.add('"$filterComplex"');
      commandParts.add('-map');
      commandParts.add('"[out]"');

      // Add output quality settings and path
      if (outputFormat == 'mp3') {
        commandParts.add('-b:a');
        commandParts.add('192k');
      } else if (outputFormat == 'aac' || outputFormat == 'm4a') {
        commandParts.add('-c:a');
        commandParts.add('aac');
        commandParts.add('-b:a');
        commandParts.add('192k');
      }
      commandParts.add('"$outputPath"');

      // Join all command parts
      final command = commandParts.join(' ');
      print("Executing filter_complex FFmpeg command: $command");

      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();
      final output = await session.getOutput();
      final logs = await session.getLogs();

      print("FFmpeg logs: $logs");
      print("FFmpeg output: $output");

      if (ReturnCode.isSuccess(returnCode)) {
        setState(() {
          mergedFilePath = outputPath;
        });
        print("Filter complex merge successful!");
      } else {
        throw Exception("Filter complex merging failed with return code: ${returnCode?.getValue() ?? 'unknown'}");
      }
    } catch (e) {
      print("Filter complex merging failed: $e");
      throw e;
    }
  }

// Alternative method using concat demuxer
  Future<void> mergeAudioWithConcatDemuxer(String outputPath) async {
    try {
      final directory = await getTemporaryDirectory();
      final inputFileListPath = '${directory.path}/input_files_alt.txt';
      final inputFile = File(inputFileListPath);

      // Write each file path on a separate line
      List<String> lines = [];
      for (int i = 0; i < widget.cutAudioPaths.length; i++) {
        String path = widget.cutAudioPaths[i];
        String escapedPath = path.replaceAll("'", "'\\''");
        lines.add("file '$escapedPath'");
        print("Concat demuxer method - Song ${i+1}: ${path.split('/').last}");
      }

      await inputFile.writeAsString(lines.join('\n'));

      print("Concat demuxer input file content:\n${await inputFile.readAsString()}");

      // Determine if codec copy can be used
      bool sameFormat = true;
      String? firstFormat;
      for (String path in widget.cutAudioPaths) {
        String ext = path.split('.').last.toLowerCase();
        if (firstFormat == null) {
          firstFormat = ext;
        } else if (ext != firstFormat) {
          sameFormat = false;
          break;
        }
      }

      String codecParam;
      if (sameFormat && firstFormat == outputFormat) {
        codecParam = '-c copy';
        print("Using codec copy for same format files");
      } else {
        if (outputFormat == 'mp3') {
          codecParam = '-c:a libmp3lame -b:a 192k';
        } else if (outputFormat == 'aac' || outputFormat == 'm4a') {
          codecParam = '-c:a aac -b:a 192k';
        } else {
          codecParam = '-c:a aac -b:a 192k';  // Default to AAC
        }
        print("Re-encoding with: $codecParam");
      }

      final command = '-f concat -safe 0 -i "$inputFileListPath" $codecParam "$outputPath"';
      print("Executing concat demuxer FFmpeg command: $command");

      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();
      final output = await session.getOutput();
      final logs = await session.getLogs();

      print("FFmpeg logs: $logs");
      print("FFmpeg output: $output");

      if (ReturnCode.isSuccess(returnCode)) {
        setState(() {
          mergedFilePath = outputPath;
        });
        print("Concat demuxer merge successful!");
      } else {
        throw Exception("Concat demuxer merging failed with return code: ${returnCode?.getValue() ?? 'unknown'}");
      }
    } catch (e) {
      print("Concat demuxer merging failed: $e");
      throw e;
    }
  }


  Future<bool> requestMediaPermission(BuildContext context) async {
    try {
      // Determine which permission to request based on Android version
      Permission permissionToRequest = Platform.isAndroid &&
         true
          ? Permission.audio
          : Permission.storage;
      // Check current permission status
      PermissionStatus status = await permissionToRequest.status;

      // If already granted, return true
      if (status.isGranted) return true;

      // Request permission
      status = await permissionToRequest.request();

      // Handle permission result
      if (status.isGranted) return true;

      if (status.isPermanentlyDenied) {
        bool? openSettings = await showDialog<bool>(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: Text('Permission Permanently Denied'),
            content: Text('Audio media permissions are permanently denied. Go to app settings to manually enable permissions.'),
            actions: [
              TextButton(
                child: Text('Cancel'),
                onPressed: () => Navigator.of(context).pop(false),
              ),
              TextButton(
                child: Text('Open Settings'),
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ],
          ),
        );

        if (openSettings == true) {
          await openAppSettings();
        }

        return false;
      }

      // For denied but not permanently denied
      bool? retry = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: Text('Media Permission Required'),
          content: Text('This app needs media permissions to save and merge audio files.'),
          actions: [
            TextButton(
              child: Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            TextButton(
              child: Text('Try Again'),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      );

      // If user wants to retry, recursively call the function
      return retry == true ? await requestMediaPermission(context) : false;
    } catch (e) {
      print("Media permission request error: $e");
      return false;
    }
  }


  Future<void> downloadFile() async {
    if (mergedFilePath == null) return;

    try {
      // Check if storage permission is granted
      // var status = await Permission.storage.status;
      // if (!status.isGranted) {
      //   status = await Permission.storage.request();
      //   if (!status.isGranted) {
      //     ScaffoldMessenger.of(context).showSnackBar(
      //       SnackBar(content: Text('Storage permission is required')),
      //     );
      //     return;
      //   }
      // }

      bool permissionGranted = await requestMediaPermission(context);

      if (!permissionGranted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Storage permission is required to download')),
        );
        return;
      }


      // Get the downloads directory
      final downloadsDir = await getExternalStorageDirectory();
      if (downloadsDir == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Downloads directory not found')),
        );
        return;
      }

      // Create the destination file
      final filename = 'merged_audio_${DateTime.now().millisecondsSinceEpoch}.$outputFormat';
      final destPath = '${downloadsDir.path}/$filename';
      await File(mergedFilePath!).copy(destPath);

      // Share the file using the correct method
      await Share.shareXFiles([XFile(destPath)], text: 'Check out my merged audio file!');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('File saved and shared')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error downloading file: $e')),
      );
      print("Download error: $e");
    }
  }
}