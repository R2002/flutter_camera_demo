import 'dart:io';

import 'package:flutter/material.dart';
import './captures_screen.dart';
import './movie_screen.dart';

class PreviewScreen extends StatelessWidget {
  final File imageFile;
  final List<File> fileList;

  PreviewScreen({
    required this.imageFile,
    required this.fileList,
  });

  viewImage(File file) {
    if (file.path.contains('.mp4')) {
      return MoviePlayerWidget(file);
    } else if (file.path.contains('.jpg')) {
      return Image.file(file);
    }
    return Container();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextButton(
              onPressed: () {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (context) => CapturesScreen(
                      imageFileList: fileList,
                    ),
                  ),
                );
              },
              child: const Text('View All Captures'),
              style: TextButton.styleFrom(
                primary: Colors.black,
                backgroundColor: Colors.white,
              ),
            ),
          ),
          Expanded(
            child: viewImage(imageFile),
          ),
        ],
      ),
    );
  }
}
