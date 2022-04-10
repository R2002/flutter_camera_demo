import 'dart:io';

import 'package:flutter/material.dart';
import './preview_screen.dart';

class CapturesScreen extends StatelessWidget {
  final List<File> imageFileList;

  const CapturesScreen({required this.imageFileList});

  viewImage(File file) {
    if (file.path.contains('.mp4')) {
      return const Image(
        image: NetworkImage(
            'https://storage.googleapis.com/cms-storage-bucket/c823e53b3a1a7b0d36a9.png'),
      );
    } else if (file.path.contains('.jpg')) {
      return Image.file(
        file,
        fit: BoxFit.cover,
      );
    }
    return Container();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SingleChildScrollView(
        physics: BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'All Captures',
                style: TextStyle(
                  fontSize: 24.0,
                  color: Colors.white,
                ),
              ),
            ),
            GridView.count(
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
              crossAxisCount: 3,
              children: [
                for (File imageFile in imageFileList.reversed)
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Colors.black,
                        width: 2,
                      ),
                    ),
                    child: InkWell(
                      onTap: () {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (context) => PreviewScreen(
                              fileList: imageFileList,
                              imageFile: imageFile,
                            ),
                          ),
                        );
                      },
                      child: viewImage(imageFile),
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
