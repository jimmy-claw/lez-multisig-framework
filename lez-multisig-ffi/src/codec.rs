//! IDL-driven instruction encode/decode (Phase 1).
//!
//! Encode: JSON args → Vec<u32> risc0-serde words (for Propose target_instruction_data)
//! Decode: Vec<u32> words → JSON {instruction, args} (for Proposal Detail display)
//!
//! Uses risc0_zkvm::serde format which is what all LEZ programs consume.

use spel_framework_core::idl::{IdlType, SpelIdl};
use serde_json::{Value, json};

// ── Encode ─────────────────────────────────────────────────────────────────

/// Serialize a single JSON value according to an IDL type into risc0 u32 words.
fn encode_value(ty: &IdlType, val: &Value) -> Result<Vec<u32>, String> {
    match ty {
        IdlType::Primitive(p) => encode_primitive(p, val),
        IdlType::Array { array: (elem_ty, len) } => {
            match elem_ty.as_ref() {
                IdlType::Primitive(p) if p == "u8" => {
                    // [u8; N]: each byte as one u32 word (risc0 serde format)
                    let bytes = parse_bytes_arg(val, *len)?;
                    Ok(bytes.iter().map(|&b| b as u32).collect())
                }
                IdlType::Primitive(p) if p == "u32" => {
                    // [u32; N]: N words
                    let arr = val.as_array().ok_or("expected array")?;
                    if arr.len() != *len { return Err(format!("expected {} elements, got {}", len, arr.len())); }
                    arr.iter().map(|v| v.as_u64().map(|n| n as u32).ok_or_else(|| "expected u32".to_string())).collect()
                }
                _ => Err(format!("unsupported array elem type: {:?}", elem_ty)),
            }
        }
        IdlType::Vec { vec: elem_ty } => {
            match elem_ty.as_ref() {
                IdlType::Primitive(p) if p == "u8" => {
                    // Vec<u8>: length + each byte as u32
                    let arr = val.as_array().ok_or("expected array for Vec<u8>")?;
                    let mut words = vec![arr.len() as u32];
                    for v in arr {
                        words.push(v.as_u64().unwrap_or(0) as u32);
                    }
                    Ok(words)
                }
                IdlType::Primitive(p) if p == "u32" => {
                    // Vec<u32>: length + values
                    let arr = val.as_array().ok_or("expected array for Vec<u32>")?;
                    let mut words = vec![arr.len() as u32];
                    for v in arr {
                        words.push(v.as_u64().unwrap_or(0) as u32);
                    }
                    Ok(words)
                }
                IdlType::Array { array: (inner_ty, inner_len) } if matches!(inner_ty.as_ref(), IdlType::Primitive(p) if p == "u8") => {
                    // Vec<[u8; N]>: length + each element's N bytes as N words
                    let arr = val.as_array().ok_or("expected array for Vec<[u8;N]>")?;
                    let mut words = vec![arr.len() as u32];
                    for elem in arr {
                        let bytes = parse_bytes_arg(elem, *inner_len)?;
                        words.extend(bytes.iter().map(|&b| b as u32));
                    }
                    Ok(words)
                }
                _ => Err(format!("unsupported Vec elem type: {:?}", elem_ty)),
            }
        }
        IdlType::Option { option } => {
            if val.is_null() {
                Ok(vec![0])  // None
            } else {
                let mut words = vec![1u32];  // Some
                words.extend(encode_value(option, val)?);
                Ok(words)
            }
        }
        IdlType::Defined { defined } => {
            Err(format!("user-defined type '{}' not supported in codec", defined))
        }
    }
}

fn encode_primitive(prim: &str, val: &Value) -> Result<Vec<u32>, String> {
    match prim {
        "bool" => Ok(vec![if val.as_bool().unwrap_or(false) { 1 } else { 0 }]),
        "u8" => Ok(vec![val.as_u64().ok_or("expected u8")? as u32]),
        "u32" | "program_id_word" => Ok(vec![val.as_u64().ok_or("expected u32")? as u32]),
        "u64" => {
            let n = val.as_u64().ok_or("expected u64")?;
            Ok(vec![(n & 0xffffffff) as u32, (n >> 32) as u32])
        }
        "u128" => {
            // Accept string or number
            let n: u128 = if let Some(s) = val.as_str() {
                s.parse().map_err(|_| "invalid u128 string".to_string())?
            } else {
                val.as_u64().ok_or("expected u128")? as u128
            };
            Ok(vec![
                (n & 0xffffffff) as u32,
                ((n >> 32) & 0xffffffff) as u32,
                ((n >> 64) & 0xffffffff) as u32,
                ((n >> 96) & 0xffffffff) as u32,
            ])
        }
        "string" | "String" => {
            let s = val.as_str().ok_or("expected string")?;
            let bytes = s.as_bytes();
            let mut words = vec![bytes.len() as u32];
            // Pack 4 bytes per word, little-endian
            for chunk in bytes.chunks(4) {
                let mut word = 0u32;
                for (i, &b) in chunk.iter().enumerate() {
                    word |= (b as u32) << (i * 8);
                }
                words.push(word);
            }
            Ok(words)
        }
        "program_id" => {
            // [u32; 8] — accept hex string or array of u32
            if let Some(s) = val.as_str() {
                let s = s.trim_start_matches("0x");
                if s.len() != 64 { return Err("program_id must be 64 hex chars".to_string()); }
                let bytes = hex::decode(s).map_err(|e| format!("hex: {}", e))?;
                let words: Vec<u32> = bytes.chunks(4)
                    .map(|c| u32::from_le_bytes(c.try_into().unwrap()))
                    .collect();
                Ok(words)
            } else if let Some(arr) = val.as_array() {
                arr.iter().map(|v| v.as_u64().map(|n| n as u32).ok_or_else(|| "expected u32".to_string())).collect()
            } else {
                Err("program_id: expected hex string or [u32; 8]".to_string())
            }
        }
        other => Err(format!("unsupported primitive type: {}", other)),
    }
}

/// Parse a JSON value as bytes for [u8; N]: accepts hex string or array of integers.
fn parse_bytes_arg(val: &Value, expected_len: usize) -> Result<Vec<u8>, String> {
    if let Some(s) = val.as_str() {
        let s = s.trim_start_matches("0x");
        let bytes = hex::decode(s).map_err(|e| format!("hex: {}", e))?;
        if bytes.len() != expected_len {
            return Err(format!("expected {} bytes, got {}", expected_len, bytes.len()));
        }
        Ok(bytes)
    } else if let Some(arr) = val.as_array() {
        if arr.len() != expected_len {
            return Err(format!("expected {} bytes, got {}", expected_len, arr.len()));
        }
        arr.iter().map(|v| v.as_u64().map(|n| n as u8).ok_or_else(|| "expected byte".to_string())).collect()
    } else {
        Err("expected hex string or byte array".to_string())
    }
}

/// Encode a named instruction's args to risc0 u32 words.
///
/// Returns `Ok(words)` where words[0] is the variant index, followed by the serialized args.
pub fn encode_instruction(idl: &SpelIdl, ix_name: &str, args: &Value) -> Result<Vec<u32>, String> {
    let (variant_idx, ix) = idl.instructions.iter().enumerate()
        .find(|(_, ix)| ix.name == ix_name)
        .ok_or_else(|| format!("instruction '{}' not found in IDL", ix_name))?;

    let mut words = vec![variant_idx as u32];

    for arg in &ix.args {
        let val = args.get(&arg.name)
            .or_else(|| {
                // Try snake_case → camelCase fallback
                let camel = to_camel(&arg.name);
                args.get(&camel)
            })
            .ok_or_else(|| format!("missing arg '{}'", arg.name))?;
        let arg_words = encode_value(&arg.type_, val)
            .map_err(|e| format!("arg '{}': {}", arg.name, e))?;
        words.extend(arg_words);
    }

    Ok(words)
}

fn to_camel(snake: &str) -> String {
    let mut out = String::new();
    let mut up = false;
    for c in snake.chars() {
        if c == '_' { up = true; }
        else if up { out.push(c.to_ascii_uppercase()); up = false; }
        else { out.push(c); }
    }
    out
}

// ── Decode ─────────────────────────────────────────────────────────────────

struct WordReader<'a> {
    words: &'a [u32],
    pos: usize,
}

impl<'a> WordReader<'a> {
    fn new(words: &'a [u32]) -> Self { Self { words, pos: 0 } }

    fn read_u32(&mut self) -> Result<u32, String> {
        if self.pos >= self.words.len() { return Err("unexpected end of instruction data".to_string()); }
        let v = self.words[self.pos];
        self.pos += 1;
        Ok(v)
    }

    fn read_u64(&mut self) -> Result<u64, String> {
        let lo = self.read_u32()? as u64;
        let hi = self.read_u32()? as u64;
        Ok(lo | (hi << 32))
    }

    fn read_u128(&mut self) -> Result<u128, String> {
        let w0 = self.read_u32()? as u128;
        let w1 = self.read_u32()? as u128;
        let w2 = self.read_u32()? as u128;
        let w3 = self.read_u32()? as u128;
        Ok(w0 | (w1 << 32) | (w2 << 64) | (w3 << 96))
    }
}

fn decode_value(ty: &IdlType, r: &mut WordReader) -> Result<Value, String> {
    match ty {
        IdlType::Primitive(p) => decode_primitive(p, r),
        IdlType::Array { array: (elem_ty, len) } => {
            match elem_ty.as_ref() {
                IdlType::Primitive(p) if p == "u8" => {
                    // [u8; N]: N words, each a u8
                    let bytes: Result<Vec<u8>, _> = (0..*len).map(|_| r.read_u32().map(|w| w as u8)).collect();
                    let hex = hex::encode(bytes?);
                    Ok(Value::String(format!("0x{}", hex)))
                }
                IdlType::Primitive(p) if p == "u32" => {
                    let vals: Result<Vec<Value>, _> = (0..*len).map(|_| r.read_u32().map(|w| json!(w))).collect();
                    Ok(Value::Array(vals?))
                }
                _ => Err(format!("unsupported array elem type for decode: {:?}", elem_ty)),
            }
        }
        IdlType::Vec { vec: elem_ty } => {
            let len = r.read_u32()? as usize;
            match elem_ty.as_ref() {
                IdlType::Primitive(p) if p == "u8" => {
                    let bytes: Result<Vec<u8>, _> = (0..len).map(|_| r.read_u32().map(|w| w as u8)).collect();
                    Ok(json!(hex::encode(bytes?)))
                }
                IdlType::Primitive(p) if p == "u32" => {
                    let vals: Result<Vec<Value>, _> = (0..len).map(|_| r.read_u32().map(|w| json!(w))).collect();
                    Ok(Value::Array(vals?))
                }
                IdlType::Array { array: (inner_ty, inner_len) } if matches!(inner_ty.as_ref(), IdlType::Primitive(p) if p == "u8") => {
                    let mut elems = Vec::new();
                    for _ in 0..len {
                        let bytes: Result<Vec<u8>, _> = (0..*inner_len).map(|_| r.read_u32().map(|w| w as u8)).collect();
                        elems.push(json!(format!("0x{}", hex::encode(bytes?))));
                    }
                    Ok(Value::Array(elems))
                }
                _ => Err(format!("unsupported Vec elem type for decode: {:?}", elem_ty)),
            }
        }
        IdlType::Option { option } => {
            let tag = r.read_u32()?;
            if tag == 0 { Ok(Value::Null) }
            else { decode_value(option, r) }
        }
        IdlType::Defined { defined } => {
            Err(format!("user-defined type '{}' not supported in codec", defined))
        }
    }
}

fn decode_primitive(prim: &str, r: &mut WordReader) -> Result<Value, String> {
    match prim {
        "bool"  => Ok(json!(r.read_u32()? != 0)),
        "u8"    => Ok(json!(r.read_u32()? as u8)),
        "u32"   => Ok(json!(r.read_u32()?)),
        "u64"   => Ok(json!(r.read_u64()?)),
        "u128"  => Ok(json!(r.read_u128()?.to_string())),
        "string" | "String" => {
            let byte_len = r.read_u32()? as usize;
            let word_count = (byte_len + 3) / 4;
            let mut bytes = Vec::with_capacity(byte_len);
            for _ in 0..word_count {
                let w = r.read_u32()?;
                bytes.extend_from_slice(&w.to_le_bytes());
            }
            bytes.truncate(byte_len);
            Ok(json!(String::from_utf8_lossy(&bytes).into_owned()))
        }
        "program_id" => {
            // [u32; 8]
            let words: Result<Vec<u32>, _> = (0..8).map(|_| r.read_u32()).collect();
            let words = words?;
            // Convert to hex
            let bytes: Vec<u8> = words.iter().flat_map(|w| w.to_le_bytes()).collect();
            Ok(json!(format!("0x{}", hex::encode(bytes))))
        }
        other => Err(format!("unsupported primitive type for decode: {}", other)),
    }
}

/// Decode instruction data words to {instruction, args} JSON.
pub fn decode_instruction(idl: &SpelIdl, words: &[u32]) -> Result<Value, String> {
    if words.is_empty() { return Err("empty instruction data".to_string()); }

    let variant_idx = words[0] as usize;
    let ix = idl.instructions.get(variant_idx)
        .ok_or_else(|| format!("variant index {} out of range (IDL has {} instructions)", variant_idx, idl.instructions.len()))?;

    let mut r = WordReader::new(&words[1..]);
    let mut args = serde_json::Map::new();

    for arg in &ix.args {
        let val = decode_value(&arg.type_, &mut r)
            .map_err(|e| format!("arg '{}': {}", arg.name, e))?;
        args.insert(arg.name.clone(), val);
    }

    Ok(json!({
        "instruction": ix.name,
        "args": Value::Object(args),
    }))
}

// ── C FFI exports ───────────────────────────────────────────────────────────

use std::ffi::{CStr, CString};
use std::os::raw::c_char;

fn cstr(ptr: *const c_char) -> Result<String, String> {
    if ptr.is_null() { return Err("null pointer".to_string()); }
    unsafe { CStr::from_ptr(ptr) }
        .to_str().map(|s| s.to_owned())
        .map_err(|e| format!("UTF-8: {}", e))
}

fn ok_json(v: Value) -> *mut c_char {
    CString::new(json!({"success": true, "result": v}).to_string())
        .unwrap().into_raw()
}

fn err_json(msg: &str) -> *mut c_char {
    CString::new(json!({"success": false, "error": msg}).to_string())
        .unwrap().into_raw()
}

/// Encode a named instruction's args to risc0 u32 words.
///
/// idl_json:  SpelIdl JSON string
/// ix_name:   instruction name (e.g. "transfer_tokens")
/// args_json: JSON object {"arg_name": value, ...}
///
/// Returns: {"success": true, "result": {"words": [u32, ...], "hex": "0x..."}}
///       or {"success": false, "error": "..."}
#[no_mangle]
pub extern "C" fn lez_multisig_encode_instruction(
    idl_json: *const c_char,
    ix_name: *const c_char,
    args_json: *const c_char,
) -> *mut c_char {
    let idl_str   = match cstr(idl_json)   { Ok(s) => s, Err(e) => return err_json(&e) };
    let name_str  = match cstr(ix_name)    { Ok(s) => s, Err(e) => return err_json(&e) };
    let args_str  = match cstr(args_json)  { Ok(s) => s, Err(e) => return err_json(&e) };

    let idl: SpelIdl = match serde_json::from_str(&idl_str) {
        Ok(v) => v, Err(e) => return err_json(&format!("IDL parse: {}", e)),
    };
    let args: Value = match serde_json::from_str(&args_str) {
        Ok(v) => v, Err(e) => return err_json(&format!("args parse: {}", e)),
    };

    match encode_instruction(&idl, &name_str, &args) {
        Ok(words) => {
            let hex_bytes: Vec<u8> = words.iter().flat_map(|w| w.to_le_bytes()).collect();
            ok_json(json!({
                "words": words,
                "hex": format!("0x{}", hex::encode(hex_bytes)),
            }))
        }
        Err(e) => err_json(&e),
    }
}

/// Decode instruction data (as a JSON array of u32 words) to human-readable args.
///
/// idl_json:   SpelIdl JSON string
/// words_json: JSON array of u32 values
///
/// Returns: {"success": true, "result": {"instruction": "name", "args": {...}}}
///       or {"success": false, "error": "..."}
#[no_mangle]
pub extern "C" fn lez_multisig_decode_instruction(
    idl_json: *const c_char,
    words_json: *const c_char,
) -> *mut c_char {
    let idl_str   = match cstr(idl_json)   { Ok(s) => s, Err(e) => return err_json(&e) };
    let words_str = match cstr(words_json) { Ok(s) => s, Err(e) => return err_json(&e) };

    let idl: SpelIdl = match serde_json::from_str(&idl_str) {
        Ok(v) => v, Err(e) => return err_json(&format!("IDL parse: {}", e)),
    };
    let words_val: Value = match serde_json::from_str(&words_str) {
        Ok(v) => v, Err(e) => return err_json(&format!("words parse: {}", e)),
    };
    let words: Vec<u32> = match words_val.as_array() {
        Some(arr) => arr.iter()
            .filter_map(|v| v.as_u64().map(|n| n as u32))
            .collect(),
        None => return err_json("words must be a JSON array"),
    };

    match decode_instruction(&idl, &words) {
        Ok(result) => ok_json(result),
        Err(e)     => err_json(&e),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn token_idl_fragment() -> SpelIdl {
        // Minimal IDL with a transfer_tokens instruction
        serde_json::from_str(r#"{
          "name": "token",
          "version": "0.1.0",
          "instructions": [
            {
              "name": "transfer_tokens",
              "args": [
                {"name": "amount_to_transfer", "type": "u64"},
                {"name": "recipient", "type": {"array": ["u8", 32]}}
              ],
              "accounts": []
            }
          ],
          "accounts": [],
          "types": []
        }"#).unwrap()
    }

    #[test]
    fn encode_decode_transfer_tokens() {
        let idl = token_idl_fragment();
        let recipient_hex = "0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20";

        let args = json!({
            "amount_to_transfer": 1000u64,
            "recipient": recipient_hex,
        });

        let words = encode_instruction(&idl, "transfer_tokens", &args).unwrap();
        // variant_idx=0, u64 amount = 2 words, [u8;32] = 32 words → 35 words total
        assert_eq!(words.len(), 35, "0 variant + 2 u64 + 32 bytes = 35");
        assert_eq!(words[0], 0, "variant index");
        assert_eq!(words[1], 1000, "amount lo");
        assert_eq!(words[2], 0, "amount hi");
        assert_eq!(words[3], 0x01, "recipient[0]");

        // Round-trip
        let decoded = decode_instruction(&idl, &words).unwrap();
        assert_eq!(decoded["instruction"], "transfer_tokens");
        let amount: u64 = decoded["args"]["amount_to_transfer"].as_u64().unwrap();
        assert_eq!(amount, 1000);
        assert!(decoded["args"]["recipient"].as_str().unwrap().contains(recipient_hex));
    }

    #[test]
    fn encode_decode_u8_and_vec_u8() {
        let idl: SpelIdl = serde_json::from_str(r#"{
          "name": "test", "version": "0.1.0",
          "instructions": [{
            "name": "set_data",
            "args": [
              {"name": "count", "type": "u8"},
              {"name": "data", "type": {"vec": "u8"}}
            ],
            "accounts": []
          }],
          "accounts": [], "types": []
        }"#).unwrap();

        let args = json!({ "count": 3, "data": [10, 20, 30] });
        let words = encode_instruction(&idl, "set_data", &args).unwrap();
        // variant=0, u8=1, vec_len=1, 3 bytes=3 → 6 words
        assert_eq!(words[0], 0);
        assert_eq!(words[1], 3);
        assert_eq!(words[2], 3); // vec length
        assert_eq!(words[3], 10);
        assert_eq!(words[4], 20);
        assert_eq!(words[5], 30);

        let decoded = decode_instruction(&idl, &words).unwrap();
        assert_eq!(decoded["args"]["count"], 3);
    }
}
