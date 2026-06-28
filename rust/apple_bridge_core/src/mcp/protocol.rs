//! JSON-RPC types and constants for the MCP HTTP transport.

pub const JSONRPC_VERSION: &str = "2.0";
pub const PROTOCOL_VERSION: &str = "2024-11-05";
pub const SERVER_NAME: &str = "apple-bridge";
pub const SERVER_VERSION: &str = "0.1.0";

pub const INVALID_REQUEST: i64 = -32600;
pub const METHOD_NOT_FOUND: i64 = -32601;

pub fn json_rpc_result(id: serde_json::Value, result: serde_json::Value) -> serde_json::Value {
  serde_json::json!({
    "jsonrpc": JSONRPC_VERSION,
    "id": id,
    "result": result
  })
}

pub fn json_rpc_error(id: Option<serde_json::Value>, code: i64, message: &str) -> serde_json::Value {
  serde_json::json!({
    "jsonrpc": JSONRPC_VERSION,
    "id": id,
    "error": {
      "code": code,
      "message": message
    }
  })
}
