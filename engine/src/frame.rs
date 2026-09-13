//! Spectrum frame builder — the exact stdout contract the Quickshell plugin
//! parses via Model.parseSpectrumLine.
//!
//! Frame (one JSON object per line, flushed):
//!   {"bands":[..],"energy":f,"beat":f,"silent":b,"source":"<name>"}

use serde::Serialize;

#[derive(Debug, Clone, Serialize)]
pub struct Frame<'a> {
    pub bands: &'a [f32],
    pub energy: f32,
    pub beat: f32,
    pub silent: bool,
    pub source: &'a str,
}

/// Serialize a frame to a single-line JSON string.
/// Order is fixed: bands, energy, beat, silent, source.
/// The source name is escaped so it can never break the JSON contract.
pub fn build_frame(frame: &Frame) -> String {
    // Build manually to guarantee key order + stable numeric formatting.
    let bands_json: Vec<String> = frame.bands.iter().map(|v| format!("{:.4}", v)).collect();
    let source_escaped = frame
        .source
        .replace('\\', "\\\\")
        .replace('"', "\\\"")
        .replace('\n', "\\n")
        .replace('\r', "\\r")
        .replace('\t', "\\t");
    format!(
        "{{\"bands\":[{}],\"energy\":{:.4},\"beat\":{:.4},\"silent\":{},\"source\":\"{}\"}}",
        bands_json.join(","),
        frame.energy,
        frame.beat,
        frame.silent,
        source_escaped
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_bands() -> Vec<f32> {
        vec![0.0, 0.25, 0.5, 0.75, 1.0, 0.1, 0.9]
    }

    #[test]
    fn includes_all_required_keys_in_order() {
        let b = sample_bands();
        let f = Frame { bands: &b, energy: 0.4, beat: 0.1, silent: false, source: "pipewire" };
        let s = build_frame(&f);
        // key order must be bands, energy, beat, silent, source
        let bi = s.find("\"bands\"").unwrap();
        let ei = s.find("\"energy\"").unwrap();
        let ti = s.find("\"beat\"").unwrap();
        let si = s.find("\"silent\"").unwrap();
        let soi = s.find("\"source\"").unwrap();
        assert!(bi < ei && ei < ti && ti < si && si < soi, "key order wrong: {s}");
    }

    #[test]
    fn is_valid_json_and_round_trips() {
        let b = sample_bands();
        let f = Frame { bands: &b, energy: 0.4, beat: 0.1, silent: false, source: "pipewire" };
        let s = build_frame(&f);
        let v: serde_json::Value = serde_json::from_str(&s).expect("valid json");
        assert_eq!(v["bands"].as_array().unwrap().len(), 7);
        assert_eq!(v["energy"].as_f64().unwrap(), 0.4);
        assert_eq!(v["beat"].as_f64().unwrap(), 0.1);
        assert_eq!(v["silent"].as_bool().unwrap(), false);
        assert_eq!(v["source"].as_str().unwrap(), "pipewire");
    }

    #[test]
    fn silent_true_when_flag_set() {
        let b = sample_bands();
        let f = Frame { bands: &b, energy: 0.0, beat: 0.0, silent: true, source: "pipewire" };
        let s = build_frame(&f);
        let v: serde_json::Value = serde_json::from_str(&s).unwrap();
        assert_eq!(v["silent"].as_bool().unwrap(), true);
    }

    #[test]
    fn band_values_formatted_to_4dp() {
        let b = vec![0.1234567];
        let f = Frame { bands: &b, energy: 0.0, beat: 0.0, silent: true, source: "pipewire" };
        let s = build_frame(&f);
        assert!(s.contains("0.1235"), "expected 4dp rounding: {s}");
        assert!(!s.contains("0.12345"), "should not carry extra precision");
    }

    #[test]
    fn empty_bands_is_valid() {
        let b: Vec<f32> = vec![];
        let f = Frame { bands: &b, energy: 0.0, beat: 0.0, silent: true, source: "pipewire" };
        let s = build_frame(&f);
        let v: serde_json::Value = serde_json::from_str(&s).unwrap();
        assert_eq!(v["bands"].as_array().unwrap().len(), 0);
    }

    #[test]
    fn source_can_be_other_backend_names() {
        // future-proofing: source string is opaque to the builder
        let b = vec![0.5];
        for src in ["pipewire", "pulse", "jack", "alsa", "file"] {
            let f = Frame { bands: &b, energy: 0.1, beat: 0.0, silent: false, source: src };
            let s = build_frame(&f);
            assert!(s.contains(&format!("\"source\":\"{src}\"")), "missing source {src}: {s}");
        }
    }

    #[test]
    fn source_with_special_chars_stays_valid_json() {
        let b = vec![0.5];
        let f = Frame { bands: &b, energy: 0.1, beat: 0.0, silent: false, source: "we\"ird\\name" };
        let s = build_frame(&f);
        let v: serde_json::Value = serde_json::from_str(&s).expect("escaped source must parse");
        assert_eq!(v["source"].as_str().unwrap(), "we\"ird\\name");
    }
}
