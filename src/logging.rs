//! Logging setup for omaviz.

use std::sync::Once;
use tracing_subscriber::{EnvFilter, fmt};

static INIT: Once = Once::new();

/// Initialize logging for the daemon with ASCII meter support.
/// Safe to call multiple times - only the first call takes effect.
pub fn init_daemon(debug: bool) {
    INIT.call_once(|| {
        let filter = if debug {
            EnvFilter::new("debug,omaviz=trace")
        } else {
            EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| EnvFilter::new("info,omaviz=debug"))
        };

        fmt()
            .with_env_filter(filter)
            .with_target(false)
            .with_thread_ids(false)
            .with_file(false)
            .with_line_number(false)
            .compact()
            .init();
    });
}