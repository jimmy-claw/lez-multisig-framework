//! lez-multisig-ffi — C FFI wrapper for the LEZ Multisig program
//!
//! Enables Logos Core Qt plugins (C++) to interact with the LEZ multisig
//! program without depending on Rust directly.
//!
//! Pattern: JSON string in → JSON string out (matches logos-blockchain-c style)
//! All returned strings must be freed with `lez_multisig_free_string()`.

use std::ffi::{CStr, CString};
use std::os::raw::c_char;

mod multisig;

// ── Helpers ──────────────────────────────────────────────────────────────────

/// Convert a C string pointer to a Rust &str, returning an error JSON on failure.
fn cstr_to_str<'a>(ptr: *const c_char) -> Result<&'a str, String> {
    if ptr.is_null() {
        return Err("null pointer".to_string());
    }
    unsafe { CStr::from_ptr(ptr) }
        .to_str()
        .map_err(|e| format!("invalid UTF-8: {}", e))
}

/// Convert a Rust String to a C string (heap-allocated, caller must free).
fn to_cstring(s: String) -> *mut c_char {
    match CString::new(s) {
        Ok(cs) => cs.into_raw(),
        Err(_) => CString::new(r#"{"success":false,"error":"internal: string contains null byte"}"#)
            .unwrap()
            .into_raw(),
    }
}

/// Return a JSON error string.
fn error_json(msg: &str) -> *mut c_char {
    to_cstring(format!(r#"{{"success":false,"error":{}}}"#, serde_json::json!(msg)))
}

// ── Multisig Operations ────────────────────────────────────────────────────────

/// Create a new multisig account.
/// See lez_multisig.h for args_json schema.
#[no_mangle]
pub extern "C" fn lez_multisig_create(args_json: *const c_char) -> *mut c_char {
    let args = match cstr_to_str(args_json) {
        Ok(s) => s,
        Err(e) => return error_json(&e),
    };
    let result = multisig::create(args);
    to_cstring(result)
}

/// Create a new proposal in a multisig.
#[no_mangle]
pub extern "C" fn lez_multisig_propose(args_json: *const c_char) -> *mut c_char {
    let args = match cstr_to_str(args_json) {
        Ok(s) => s,
        Err(e) => return error_json(&e),
    };
    let result = multisig::propose(args);
    to_cstring(result)
}

/// Approve an existing proposal.
#[no_mangle]
pub extern "C" fn lez_multisig_approve(args_json: *const c_char) -> *mut c_char {
    let args = match cstr_to_str(args_json) {
        Ok(s) => s,
        Err(e) => return error_json(&e),
    };
    let result = multisig::approve(args);
    to_cstring(result)
}

/// Reject an existing proposal.
#[no_mangle]
pub extern "C" fn lez_multisig_reject(args_json: *const c_char) -> *mut c_char {
    let args = match cstr_to_str(args_json) {
        Ok(s) => s,
        Err(e) => return error_json(&e),
    };
    let result = multisig::reject(args);
    to_cstring(result)
}

/// Execute a fully-approved proposal.
#[no_mangle]
pub extern "C" fn lez_multisig_execute(args_json: *const c_char) -> *mut c_char {
    let args = match cstr_to_str(args_json) {
        Ok(s) => s,
        Err(e) => return error_json(&e),
    };
    let result = multisig::execute(args);
    to_cstring(result)
}

/// List proposals for a multisig.
#[no_mangle]
pub extern "C" fn lez_multisig_list_proposals(args_json: *const c_char) -> *mut c_char {
    let args = match cstr_to_str(args_json) {
        Ok(s) => s,
        Err(e) => return error_json(&e),
    };
    let result = multisig::list_proposals(args);
    to_cstring(result)
}

/// Get the state of a multisig.
#[no_mangle]
pub extern "C" fn lez_multisig_get_state(args_json: *const c_char) -> *mut c_char {
    let args = match cstr_to_str(args_json) {
        Ok(s) => s,
        Err(e) => return error_json(&e),
    };
    let result = multisig::get_state(args);
    to_cstring(result)
}

// ── Memory Management ─────────────────────────────────────────────────────────

/// Free a string returned by any lez_multisig_* function.
#[no_mangle]
pub extern "C" fn lez_multisig_free_string(s: *mut c_char) {
    if !s.is_null() {
        unsafe { drop(CString::from_raw(s)) };
    }
}

// ── Version ───────────────────────────────────────────────────────────────────

/// Returns the version string of this FFI library.
#[no_mangle]
pub extern "C" fn lez_multisig_version() -> *mut c_char {
    to_cstring(env!("CARGO_PKG_VERSION").to_string())
}
