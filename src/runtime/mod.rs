mod colab;
mod colab_notebook;
mod colab_sessions;
mod local;

pub use colab::Colab;
pub use colab_sessions::known_names as colab_session_names;
pub use local::Local;

pub struct Execution {
    pub success: bool,
    pub output: String,
    pub outputs: Vec<serde_json::Value>,
    pub execution_count: serde_json::Value,
    pub artifacts: Vec<String>,
}
