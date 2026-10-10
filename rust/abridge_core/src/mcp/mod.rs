//! MCP JSON-RPC dispatch over authenticated HTTP POST /mcp.

mod protocol;

use std::sync::Arc;
use std::time::Instant;

use axum::{
  Json,
  extract::State,
  http::StatusCode,
  response::{IntoResponse, Response},
};
use serde_json::Value;

use crate::{
  arg_validation,
  config::{ProviderConfig, ProviderRequest},
  providers::ProviderBridge,
  tools::{self, ToolDefinition},
  usage_audit::{EVENT_MCP_INITIALIZE, EVENT_TOOL_CALL, UsageAuditStore},
};

#[derive(Clone)]
pub struct McpState {
  pub bearer_token: String,
  pub app_version: String,
  pub enabled_capabilities: Vec<String>,
  pub enabled_providers: Vec<ProviderConfig>,
  pub provider: Arc<dyn ProviderBridge>,
  pub audit_store: Arc<UsageAuditStore>,
}

use protocol::{
  INVALID_REQUEST, JSONRPC_VERSION, METHOD_NOT_FOUND, PROTOCOL_VERSION, SERVER_NAME, json_rpc_error, json_rpc_result,
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
    "initialize" => handle_initialize(id, params, &state),
    "tools/list" => handle_tools_list(id, &state),
    "tools/call" => handle_tools_call(id, params, &state),
    "notifications/initialized" => handle_notification_initialized(id),
    _ => json_response(StatusCode::OK, json_rpc_error(id, METHOD_NOT_FOUND, "method not found")),
  }
}

fn handle_initialize(id: Option<Value>, _params: Value, state: &McpState) -> Response {
  let Some(id) = id else {
    return StatusCode::NO_CONTENT.into_response();
  };

  let result = serde_json::json!({
    "protocolVersion": PROTOCOL_VERSION,
    "capabilities": { "tools": {} },
    "serverInfo": {
      "name": SERVER_NAME,
      "version": state.app_version
    }
  });

  state.audit_store.record(EVENT_MCP_INITIALIZE, None, true, None);

  json_response(StatusCode::OK, json_rpc_result(id, result))
}

fn handle_tools_list(id: Option<Value>, state: &McpState) -> Response {
  let Some(id) = id else {
    return StatusCode::NO_CONTENT.into_response();
  };

  let tools: Vec<Value> = tools::tools_for_capabilities(&state.enabled_capabilities)
    .into_iter()
    .filter(|tool| provider_enabled(state, tool.provider))
    .map(tool_descriptor)
    .collect();

  json_response(
    StatusCode::OK,
    json_rpc_result(id, serde_json::json!({ "tools": tools })),
  )
}

fn handle_tools_call(id: Option<Value>, params: Value, state: &McpState) -> Response {
  let started = Instant::now();

  let Some(id) = id else {
    return StatusCode::NO_CONTENT.into_response();
  };

  let record_tool_call = |tool_name: &str, success: bool| {
    state.audit_store.record(
      EVENT_TOOL_CALL,
      Some(tool_name),
      success,
      Some(started.elapsed().as_millis() as u64),
    );
  };

  let Some(name) = params.get("name").and_then(Value::as_str) else {
    record_tool_call("<missing>", false);
    return tool_error_response(id, "invalid_params", "missing tool name");
  };

  let Some(tool) = tools::resolve_tool(name) else {
    record_tool_call(name, false);
    return tool_error_response(id, "unknown_tool", &format!("unknown tool: {name}"));
  };
  // Audit under the registry name so wire and dotted calls log identically.
  let name = tool.name;

  if !capability_enabled(state, tool.capability) {
    record_tool_call(name, false);
    return tool_error_response(
      id,
      "capability_disabled",
      &format!("capability not enabled: {}", tool.capability),
    );
  }

  if !provider_enabled(state, tool.provider) {
    record_tool_call(name, false);
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

  // Enforce the advertised inputSchema before any provider hop (including diagnostics).
  if let Err(message) = arg_validation::validate_tool_arguments(tool, &arguments) {
    record_tool_call(name, false);
    return tool_error_response(id, "invalid_arguments", &message);
  }

  // Phase C: typed/normalize high-traffic create/update args after schema validation.
  let arguments = match crate::typed_args::normalize_tool_arguments(tool, arguments) {
    Ok(value) => value,
    Err(message) => {
      record_tool_call(name, false);
      return tool_error_response(id, "invalid_arguments", &message);
    }
  };

  if tool.name == tools::TOOL_GET_USAGE_LOG {
    let limit = parse_usage_log_limit(&arguments);
    record_tool_call(name, true);
    let payload = state.audit_store.usage_log_response(limit);
    let payload_json = match serde_json::to_string(&payload) {
      Ok(json) => json,
      Err(_) => {
        return tool_error_response(id, "serialization_error", "failed to serialize usage log");
      }
    };
    return json_response(
      StatusCode::OK,
      json_rpc_result(
        id,
        serde_json::json!({
          "content": [{ "type": "text", "text": payload_json }],
          "isError": false
        }),
      ),
    );
  }

  let payload_json = serde_json::to_string(&arguments).unwrap_or_else(|_| "{}".into());

  let response = state.provider.call_provider(ProviderRequest {
    provider: tool.provider.into(),
    operation: tool.operation.into(),
    payload_json,
  });

  record_tool_call(name, response.ok);

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
    "name": tools::wire_name(tool.name),
    "description": tool.description,
    "inputSchema": tools::input_schema(tool)
  })
}

fn parse_usage_log_limit(arguments: &Value) -> Option<usize> {
  arguments.get("limit").and_then(|value| match value {
    Value::Number(number) => number.as_u64().map(|limit| limit as usize),
    _ => None,
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
