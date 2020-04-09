// Struct for users
extern crate ws;

use std::thread;
use std::sync::mpsc;
use std::rc::Rc;
use std::cell::Cell;
use std::sync::Arc;
use std::sync::Mutex;

use ws::{listen, Handler, Sender, Result, Message, Handshake, CloseCode, Error};

struct Server {
    out: Sender,
    count: Rc<Cell<u32>>,
    id: u32,
    t_game: mpsc::Sender<String>,
    r_server:  Arc<Mutex<mpsc::Receiver<String>>>
}

struct _Player {
    id: u32,
    inp: f32,
    vel: f32,
    pos: f32,
    state: i8,
}

impl Handler for Server {
    fn on_open(&mut self, conn: Handshake) -> Result<()> {
        // Print the remote address
        let addr = conn.remote_addr();
        println!("Connection ID {} opened with: {:?}", self.id, addr.unwrap().unwrap());
        // We have a new connection, so we increment the connection counter
        Ok(self.count.set(self.count.get() + 1))
    }

    fn on_message(&mut self, msg: Message) -> Result<()> {
        let data = msg.to_string();
        // Send Data to main thread
        self.t_game.send(data).unwrap();
        // Recieve data from main thread
        let out_msg = self.r_server.lock().unwrap().try_recv();
        if !out_msg.is_err() {
            println!("Connection ID {}: {:?}", self.id, out_msg.unwrap());
        }
    }

    fn on_close(&mut self, code: CloseCode, reason: &str) {
        match code {
            CloseCode::Normal => println!("The client on ID {} is done with the connection.", self.id),
            CloseCode::Away   => println!("The client on ID {} is leaving the site.", self.id),
            CloseCode::Abnormal => println!(
                "Closing handshake failed! Unable to obtain closing status from client on ID {}.", self.id),
            _ => println!("The client encountered an error: {}", reason),
        }

        // The connection is going down, so we need to decrement the count
        self.count.set(self.count.get() - 1)
    }

    fn on_error(&mut self, err: Error) {
        println!("The server encountered an error on ID {}: {:?}", self.id, err);
    }
}

fn main() {
    // Channels for sending data to / from the server
    let (t_game, r_game): (mpsc::Sender<String>, mpsc::Receiver<String>) = mpsc::channel();
    let (t_server, r_server): (mpsc::Sender<String>, mpsc::Receiver<String>) = mpsc::channel();
    let receiver = Arc::new(Mutex::new(r_server));
    // Spawn a thread for our Server
    let server = thread::spawn(move || {
        // Cell gives us interior mutability so we can increment
        // or decrement the count between handlers.
        // Rc is a reference-counted box for sharing the count between handlers
        // since each handler needs to own its contents.
        let count = Rc::new(Cell::new(0));
        let url = "127.0.0.1:9001";
        println!("Server Listening on port: {}", url);
        listen(url, |out| { Server {
            out: out, count: count.clone(), id: count.get(), t_game: t_game.clone(),
            r_server: Arc::clone(&receiver)
        }}).unwrap();
    });

    // Main server loop
    let running : bool = true;
    while running {
        let received = r_game.try_recv();
        if !received.is_err() {
            t_server.send(received.unwrap()).unwrap();
        }
    }
    // Called when all thread closes
    let _ = server.join();
    println!("Shutting Down.");
}
