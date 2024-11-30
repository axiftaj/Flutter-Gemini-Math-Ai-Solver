

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';



class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {

  late final GenerativeModel _model;
  late final ChatSession _chat;

  late final ScrollController _scrollController;
  final TextEditingController _textController = TextEditingController();
  final FocusNode _textFieldFocus = FocusNode();

  List<DataModel> list = [] ;
  StreamSocket streamSocket = StreamSocket();

  bool _loading = false;

  //save it in .env file or define system files
   String _apiKey = '';

  File? _image ;

  final ImagePicker _picker = ImagePicker();

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback(
          (_) => _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(
          milliseconds: 750,
        ),
        curve: Curves.easeOutCirc,
      ),
    );
  }

  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    _scrollController = ScrollController() ;
    _apiKey = dotenv.env['GOOGLE_GEMINI_API_KEY'] ?? '';
    streamSocket.getResponse ;
    _model = GenerativeModel(
      model: 'gemini-1.5-flash',
      apiKey: _apiKey,
      safetySettings: [
        SafetySetting(HarmCategory.harassment, HarmBlockThreshold.high),
        SafetySetting(HarmCategory.hateSpeech, HarmBlockThreshold.high),
      ],
    );
    _chat = _model.startChat();
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(

      appBar: AppBar(
        title: const Text('Gemini'),
      ),

      body: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          StreamBuilder<List<DataModel>>(
            stream: streamSocket.getResponse,
            initialData: [
              DataModel('No Data Found', 'No Data Found', 'No Data Found')
            ],
            builder: (BuildContext context,  snapshot) {
              if(!snapshot.hasData){
                return const Center(child:  CircularProgressIndicator());
              }else {
                if (list.isEmpty) {
                  return const Expanded(child:  Center(child: Text('Greetings!\n How i can help you', textAlign: TextAlign.center, style: TextStyle(color: Colors.white))));
                }
                return Expanded(
                  child: ListView.builder(
                      itemCount:  snapshot.data!.length,
                      controller: _scrollController,
                      itemBuilder: (context, index){
                        final data = list[index] ;
                        return   MessageBubbleWidget( text: data.prompt, isFromUser: data.isMe, type: data.type, image: data.image, );
                      }
                  ),
                );
              }
            },
          ),

          Padding(
            padding: const EdgeInsets.symmetric(
              vertical: 25,
              horizontal: 15,
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    autofocus: true,
                    focusNode: _textFieldFocus,
                    decoration:  InputDecoration(
                      contentPadding: const EdgeInsets.all(15),
                      hintText: 'Enter a prompt...',
                      border: OutlineInputBorder(
                        borderRadius: const BorderRadius.all(
                          Radius.circular(14),
                        ),
                        borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.secondary,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: const BorderRadius.all(
                          Radius.circular(14),
                        ),
                        borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.secondary,
                        ),
                      ),
                    ),
                    controller: _textController,
                    onSubmitted: (String value) {
                    },
                  ),
                ),
                const SizedBox.square(
                  dimension: 15,
                ),
                if (!_loading)
                  IconButton(
                    onPressed: () async {

                      if(_textController.text.isEmpty){
                        _showError('Please enter prompt');
                      }else {
                        if(_image == null){
                          _sendChatMessage(_textController.text);
                        }else {
                          _sendImageMessage(_textController.text);
                        }
                      }

                    },
                    icon: Icon(
                      Icons.send,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                if (!_loading)
                  IconButton(
                    onPressed: () async {
                      pickImage();
                    },
                    icon: Icon(
                      Icons.camera,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  )
                else
                  const CircularProgressIndicator(),

              ],
            ),
          )
        ],
      ),
    );
  }

  Future<void> _sendChatMessage(String message) async {
    setState(() {
      _loading = true;
    });

    try {

      list.add(DataModel('', 'text', message , isMe: true));
      streamSocket.addResponse(list);

      var response = await _chat.sendMessage(
        Content.text(message ),
      );


      var text = response.text;

      if (text == null) {
        _showError('No response from API.');
        return;
      } else {

        list.add(DataModel('', 'text', text , isMe: false));
        streamSocket.addResponse(list);
        setState(() {
          _loading = false;
          _scrollDown();
        });
      }
    } catch (e) {
      _showError(e.toString());
      setState(() {
        _loading = false;
      });
    } finally {
      _textController.clear();
      setState(() {
        _loading = false;
      });
      _textFieldFocus.requestFocus();
    }
  }

  Future<void> _sendImageMessage(String message) async {

    try {

      setState(() {
        _loading = true;
      });


      list.add(DataModel(_image!.path.toString(), 'image', message , isMe: true));
      list.add(DataModel(_image!.path.toString(), 'text', message , isMe: true));
      streamSocket.addResponse(list);

      setState(() {
        _scrollDown();
      });

      final firstImage = await _image!.readAsBytes();

      final prompt = TextPart(message);

      final imageParts = [
        DataPart('image/jpeg', firstImage),
      ];

      final response = await _model.generateContent([
        Content.multi([prompt, ...imageParts])
      ]);

      var text = response.text;

      if (text == null) {
        _showError('No response from API.');
        return;
      } else {

        list.add(DataModel('', 'text', text , isMe: false));
        streamSocket.addResponse(list);

        setState(() {
          _loading = false;
          _scrollDown();
        });
      }
    } catch (e) {
      _showError(e.toString());
      setState(() {
        _loading = false;
      });
    } finally {
      _textController.clear();
      setState(() {
        _loading = false;
      });
      _textFieldFocus.requestFocus();
    }
  }

  Future<void> pickImage()async{
    final pickedFile = await _picker.pickImage(source: ImageSource.camera);

    if (pickedFile != null) {
      // setState(() {
      //   _image = File(pickedFile.path);
      // });
    }

    CroppedFile? croppedFile = await ImageCropper().cropImage(
      sourcePath: pickedFile!.path,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Cropper',
          toolbarColor: Colors.deepOrange,
          toolbarWidgetColor: Colors.white,
        ),
        IOSUiSettings(
          title: 'Cropper',
        ),
        WebUiSettings(
          context: context,
        ),
      ],
    );

    _image = File(croppedFile!.path);
  }
  void _showError(String message) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Something went wrong'),
          content: SingleChildScrollView(
            child: SelectableText(message),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('OK'),
            )
          ],
        );
      },
    );
  }

}




class StreamSocket {

  final _socketResponse = StreamController<List<DataModel>>.broadcast();

  void Function(List<DataModel>) get addResponse => _socketResponse.sink.add;
  Stream<List<DataModel>> get getResponse => _socketResponse.stream.asBroadcastStream();

}

class DataModel{
  String prompt, type, image;
  bool isMe ;
  DataModel(this.image , this.type, this.prompt , {this.isMe = false});
}


class MessageBubbleWidget extends StatelessWidget {
  final String text, type, image;
  final bool isFromUser;

  const MessageBubbleWidget({
    super.key,
    required this.text,
    required this.isFromUser,
    required this.type,
    required this.image,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: isFromUser ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        Flexible(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 600),
            decoration: BoxDecoration(
              color: isFromUser ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.surfaceVariant,
              borderRadius: BorderRadius.circular(18),
            ),
            padding: const EdgeInsets.symmetric(
              vertical: 10,
              horizontal: 10,
            ),
            margin: const EdgeInsets.only(bottom: 8),
            child: type == 'image'
                ? Image.file(height: 250, width: 250, fit: BoxFit.cover, File(image.toString()))
                : MarkdownBody(
              selectable: true,
              data: text,
            ),
          ),
        ),
      ],
    );
  }
}