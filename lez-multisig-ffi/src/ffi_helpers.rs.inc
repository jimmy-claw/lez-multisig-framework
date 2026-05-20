
fn parse_create_key(v: &Value) -> Result<[u8; 32], String> {
    // Accept hex string ("aeb11f...") or JSON byte array ([174, 177, ...])
    if let Some(s) = v.as_str() {
        let s = s.trim_start_matches("0x").trim_start_matches("0X");
        if s.len() != 64 { return Err(format!("create_key hex must be 64 chars, got {}", s.len())); }
        let bytes = hex::decode(s).map_err(|e| format!("invalid hex: {}", e))?;
        let mut arr = [0u8; 32]; arr.copy_from_slice(&bytes);
        return Ok(arr);
    }
    serde_json::from_value(v.clone()).map_err(|e| format!("parse error: {}", e))
}

fn parse_bytes32(v: &Value) -> Result<[u8; 32], String> {
    // Accept base58 (with/without Public/ or Private/ prefix), hex, or JSON byte array.
    // Mirrors spel-cli hex.rs::decode_bytes_32 so wallet account IDs work as-is.
    // Upstream fix pending: https://github.com/logos-co/spel/pull/209
    if let Some(s) = v.as_str() {
        let s = s.strip_prefix("Public/").or_else(|| s.strip_prefix("Private/")).unwrap_or(s);
        if let Ok(bytes) = bs58::decode(s).into_vec() {
            if bytes.len() == 32 {
                let mut arr = [0u8; 32];
                arr.copy_from_slice(&bytes);
                return Ok(arr);
            }
        }
        let s = s.trim_start_matches("0x").trim_start_matches("0X");
        if s.len() == 64 {
            let bytes = hex::decode(s).map_err(|e| format!("invalid hex: {}", e))?;
            let mut arr = [0u8; 32];
            arr.copy_from_slice(&bytes);
            return Ok(arr);
        }
        return Err(format!("expected 32-byte base58, 64-char hex, or byte array"));
    }
    serde_json::from_value(v.clone()).map_err(|e| format!("parse error: {}", e))
}
