import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import 'cut_audo_page.dart';

class AddAudioPage extends StatefulWidget {
  @override 
  _AddAudioPageState createState() => _AddAudioPageState();
}
 
class _AddAudioPageState extends State<AddAudioPage> {
  List<String> selectedAudioPaths = [];

  Future<void> pickAudioFiles() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: true,
    );

    if (result != null) {
      setState(() {
        selectedAudioPaths.addAll(result.paths.map((path) => path!).toList());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Add Audio Files'),
        actions: [
          IconButton(
            icon: Icon(Icons.navigate_next),
            onPressed: selectedAudioPaths.isNotEmpty
                ? () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => CutAudioPage(selectedAudioPaths),
              ),
            )
                : null,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: selectedAudioPaths.length,
              itemBuilder: (context, index) {
                return ListTile(
                  leading: Icon(Icons.audio_file),
                  title: Text(selectedAudioPaths[index].split('/').last),
                  trailing: IconButton(
                    icon: Icon(Icons.delete),
                    onPressed: () {
                      setState(() {
                        selectedAudioPaths.removeAt(index);
                      });
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: pickAudioFiles,
        child: Icon(Icons.add),
        tooltip: 'Add Audio Files',
      ),
    );
  }
}