//! MCP JSON-RPC dispatch over authenticated HTTP POST /mcp.

mod protocol;

use std::sync::Arc;

use axum::{
  Json,
  extract::State,
  http::StatusCode,
  response::{IntoResponse, Response},
};
use serde_json::Value;

use crate::{
  config::{ProviderConfig, ProviderRequest},
  providers::ProviderBridge,
  tools::{self, ToolDefinition},
};

#[derive(Clone)]
pub struct McpState {
  pub bearer_token: String,
  pub enabled_capabilities: Vec<String>,
  pub enabled_providers: Vec<ProviderConfig>,
  pub provider: Arc<dyn ProviderBridge>,
}

use protocol::{
  INVALID_REQUEST, JSONRPC_VERSION, METHOD_NOT_FOUND, PROTOCOL_VERSION, SERVER_NAME, SERVER_VERSION, json_rpc_error,
  json_rpc_result,
};

pub async fn handle_mcp(State(state): State<McpState>, body: axum::body::Bytes) -> Response {
  let parsed: Value = match serde_json::from_slice(&body) {
    Ok(value) => value,
    Err(_) => {
      return json_response(
        StatusCode::OK,
        json_rpc_error(None, INVALID_REQUEST, "invalid JSON-RPC request"),
      );
    }
  };

  let method = parsed.get("method").and_then(Value::as_str);
  let id = parsed.get("id").cloned();
  let params = parsed.get("params").cloned().unwrap_or(Value::Null);

  let Some(method) = method else {
    return json_response(StatusCode::OK, json_rpc_error(id, INVALID_REQUEST, "missing method"));
  };

  if parsed.get("jsonrpc").and_then(Value::as_str) != Some(JSONRPC_VERSION) {
    return json_response(
      StatusCode::OK,
      json_rpc_error(id, INVALID_REQUEST, "invalid jsonrpc version"),
    );
  }

  match method {
    "initialize" => handle_initialize(id, params),
    "tools/list" => handle_tools_list(id, &state),
    "tools/call" => handle_tools_call(id, params, &state),
    "notifications/initialized" => handle_notification_initialized(id),
    _ => json_response(StatusCode::OK, json_rpc_error(id, METHOD_NOT_FOUND, "method not found")),
  }
}

fn handle_initialize(id: Option<Value>, params: Value) -> Response {
  let Some(id) = id else {
    return StatusCode::NO_CONTENT.into_response();
  };

  let protocol_version = params
    .get("protocolVersion")
    .and_then(Value::as_str)
    .unwrap_or(PROTOCOL_VERSION);

  let result = serde_json::json!({
    "protocolVersion": protocol_version,
    "capabilities": { "tools": {} },
    "serverInfo": {
      "name": SERVER_NAME,
      "version": SERVER_VERSION
    }
  });

  json_response(StatusCode::OK, json_rpc_result(id, result))
}

fn handle_tools_list(id: Option<Value>, state: &McpState) -> Response {
  let Some(id) = id else {
    return StatusCode::NO_CONTENT.into_response();
  };

  let tools: Vec<Value> = tools::tools_for_capabilities(&state.enabled_capabilities)
    .into_iter()
    .map(tool_descriptor)
    .collect();

  json_response(
    StatusCode::OK,
    json_rpc_result(id, serde_json::json!({ "tools": tools })),
  )
}

fn handle_tools_call(id: Option<Value>, params: Value, state: &McpState) -> Response {
  let Some(id) = id else {
    return StatusCode::NO_CONTENT.into_response();
  };

  let Some(name) = params.get("name").and_then(Value::as_str) else {
    return tool_error_response(id, "invalid_params", "missing tool name");
  };

  let Some(tool) = tools::resolve_tool(name) else {
    return tool_error_response(id, "unknown_tool", &format!("unknown tool: {name}"));
  };

  if !capability_enabled(state, tool.capability) {
    return tool_error_response(
      id,
      "capability_disabled",
      &format!("capability not enabled: {}", tool.capability),
    );
  }

  if !provider_enabled(state, tool.provider) {
    return tool_error_response(
      id,
      "provider_disabled",
      &format!("provider not enabled: {}", tool.provider),
    );
  }

  let arguments = params
    .get("arguments")
    .cloned()
    .unwrap_or_else(|| serde_json::json!({}));
  let payload_json = serde_json::to_string(&arguments).unwrap_or_else(|_| "{}".into());

  let response = state.provider.call_provider(ProviderRequest {
    provider: tool.provider.into(),
    operation: tool.operation.into(),
    payload_json,
  });

  if response.ok {
    json_response(
      StatusCode::OK,
      json_rpc_result(
        id,
        serde_json::json!({
          "content": [{ "type": "text", "text": response.payload_json }],
          "isError": false
        }),
      ),
    )
  } else {
    let error_text = response.error_json.unwrap_or_else(|| {
      serde_json::json!({ "code": "provider_error", "message": "provider call failed" }).to_string()
    });
    json_response(
      StatusCode::OK,
      json_rpc_result(
        id,
        serde_json::json!({
          "content": [{ "type": "text", "text": error_text }],
          "isError": true
        }),
      ),
    )
  }
}

fn handle_notification_initialized(id: Option<Value>) -> Response {
  if id.is_none() {
    return StatusCode::NO_CONTENT.into_response();
  }

  json_response(
    StatusCode::OK,
    json_rpc_result(id.expect("id checked"), serde_json::json!({})),
  )
}

fn tool_descriptor(tool: &ToolDefinition) -> Value {
  serde_json::json!({
    "name": tool.name,
    "description": tool.description,
    "inputSchema": tools::input_schema(tool)
  })
}

fn capability_enabled(state: &McpState, capability: &str) -> bool {
  state.enabled_capabilities.iter().any(|enabled| enabled == capability)
}

fn provider_enabled(state: &McpState, provider: &str) -> bool {
  state
    .enabled_providers
    .iter()
    .any(|entry| entry.name == provider && entry.enabled)
}

fn tool_error_response(id: Value, code: &str, message: &str) -> Response {
  let text = serde_json::json!({ "code": code, "message": message }).to_string();
  json_response(
    StatusCode::OK,
    json_rpc_result(
      id,
      serde_json::json!({
        "content": [{ "type": "text", "text": text }],
        "isError": true
      }),
    ),
  )
}

fn json_response(status: StatusCode, body: Value) -> Response {
  (status, Json(body)).into_response()
}
