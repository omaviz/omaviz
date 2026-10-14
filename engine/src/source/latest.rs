//! A small capture mailbox. Overflow evicts oldest audio, never the newest.
use std::collections::VecDeque;
use std::sync::{Arc, Mutex};
use std::sync::mpsc::TryRecvError;

struct State<T> { items: VecDeque<T>, capacity: usize, connected: bool }
pub struct Sender<T>(Arc<Mutex<State<T>>>);
pub struct Receiver<T>(Arc<Mutex<State<T>>>);
pub fn channel<T>(capacity: usize) -> (Sender<T>, Receiver<T>) {
    assert!(capacity > 0);
    let state = Arc::new(Mutex::new(State { items: VecDeque::with_capacity(capacity), capacity, connected: true }));
    (Sender(state.clone()), Receiver(state))
}
impl<T> Sender<T> {
    pub fn send(&self, value: T) -> Result<(), ()> {
        if Arc::strong_count(&self.0) == 1 { return Err(()); }
        let mut state = self.0.lock().unwrap();
        if state.items.len() == state.capacity { state.items.pop_front(); }
        state.items.push_back(value);
        Ok(())
    }
}
impl<T> Drop for Sender<T> {
    fn drop(&mut self) { self.0.lock().unwrap().connected = false; }
}
impl<T> Receiver<T> {
    pub fn try_recv(&self) -> Result<T, TryRecvError> {
        let mut state = self.0.lock().unwrap();
        state.items.pop_front().ok_or(if state.connected { TryRecvError::Empty } else { TryRecvError::Disconnected })
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn stalled_consumer_resumes_with_recent_audio_and_observes_disconnect() {
        let (tx, rx) = channel(4);
        for i in 0..10000 { tx.send(i).unwrap(); }
        drop(tx);
        for expected in 9996..10000 { assert_eq!(rx.try_recv(), Ok(expected)); }
        assert_eq!(rx.try_recv(), Err(TryRecvError::Disconnected));
    }
}
