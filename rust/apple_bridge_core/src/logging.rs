use std::sync::Once;

static INIT: Once = Once::new();

pub fn init_logging() {
  INIT.call_once(|| {
    tracing_subscriber::fmt()
      .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
      .with_ansi(false)
      .init();
  });
}
