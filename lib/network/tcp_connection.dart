import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

abstract interface class TcpConnection {
  Socket get socket;

  Stream<Uint8List> get stream;

  Future<void> get done;

  void add(List<int> data);

  void write(String data);

  Future<void> flush();

  Future<void> close();

  void destroy();
}

final class DirectTcpConnection implements TcpConnection {
  @override
  final Socket socket;

  DirectTcpConnection(this.socket);

  @override
  Stream<Uint8List> get stream => socket;

  @override
  Future<void> get done => socket.done;

  @override
  void add(List<int> data) {
    socket.add(data);
  }

  @override
  void write(String data) {
    socket.write(data);
  }

  @override
  Future<void> flush() {
    return socket.flush();
  }

  @override
  Future<void> close() async {
    try {
      await socket.close();
    } catch (_) {
      // Ignore close error.
    }
  }

  @override
  void destroy() {
    socket.destroy();
  }
}
