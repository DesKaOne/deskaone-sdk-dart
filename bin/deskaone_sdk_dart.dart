import 'package:deskaone_sdk_dart/deskaone_sdk_dart.dart' as deskaone_sdk_dart;
import 'package:deskaone_sdk_dart/proxy/proxy_config.dart';

void main(List<String> arguments) {
  print('Hello world: ${deskaone_sdk_dart.calculate()}!');

  //final uri = Uri.parse("s4://username:password@192.168.1.1:8080");
  final uri = Uri.parse("socks4://192.168.1.1:8080");
  final proxy = ProxyConfig.fromUrl(uri);
  print(proxy);
}
