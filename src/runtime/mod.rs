mod colab;
mod local;

pub use colab::Colab;
pub use local::Local;

pub struct Execution {
    pub success: bool,
    pub output: String,
}
