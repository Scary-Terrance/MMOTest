fn main() {
    use std::net::TcpListener;
    use std::thread::spawn;
    use tungstenite::server::accept;

    let url = "127.0.0.1:9001";

    // A WebSocket echo server
    let server = TcpListener::bind(url).unwrap();
    println!("Listening at: {}", url);
    for stream in server.incoming() {
        spawn (move || {
            let mut websocket = accept(stream.unwrap()).unwrap();
            //println!("{}", websocket);
            loop {
                let msg = websocket.read_message().unwrap();
                println!("{}", msg);
                // We do not want to send back ping/pong messages.
                if msg.is_binary() || msg.is_text() {
                    websocket.write_message(msg).unwrap();
                }
                else if msg.is_close() {
                    println!("Connection closed by user");
                    break;
                }
            }
        });
    }
}
