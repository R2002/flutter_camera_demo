import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class MoviePlayerWidget extends StatefulWidget {
  File movieURL; // 動画URL
  MoviePlayerWidget(this.movieURL) : super();

  @override
  _MoviePlayerWidgetState createState() => _MoviePlayerWidgetState();
}

class _MoviePlayerWidgetState extends State<MoviePlayerWidget> {
  VideoPlayerController? _controller;

  @override
  void initState() {
    _controller = VideoPlayerController.file(widget.movieURL)
      ..initialize().then((_) {
        setState(() {});
        _controller!.play();
        _controller!.setLooping(true);
      });
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null) return Container();

    if (_controller!.value.isInitialized) {
      return Container(
        child: AspectRatio(
          aspectRatio: _controller!.value.aspectRatio,
          child: VideoPlayer(_controller!),
        ),
      );
    } else {
      return Container(
        height: 150.0,
        child: const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller!.dispose();
    super.dispose();
  }
}
