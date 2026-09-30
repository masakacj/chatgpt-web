const MAX_BODY_BYTES = 64 * 1024;
const MAX_SAMPLES = 20;

function clampNumber(value, min, max) {
  const n = Number(value);
  if (!Number.isFinite(n)) return 0;
  return Math.min(max, Math.max(min, n));
}

function safeString(value, max = 64) {
  return String(value ?? '')
    .replace(/[\r\n\t]/g, ' ')
    .slice(0, max);
}

function asInt(value) {
  return value ? 1 : 0;
}

function corsHeaders(origin) {
  const allowed =
    origin === 'https://chatgpt.com' ||
    origin === 'null';

  return {
    'Access-Control-Allow-Origin':
      allowed ? origin : 'https://chatgpt.com',
    'Access-Control-Allow-Methods':
      'GET,POST,OPTIONS',
    'Access-Control-Allow-Headers':
      'content-type,x-chatgpt-web-telemetry',
    'Access-Control-Max-Age': '86400',
    'Cache-Control': 'no-store',
  };
}

function json(data, status, headers) {
  return new Response(
    JSON.stringify(data),
    {
      status,
      headers: {
        ...headers,
        'Content-Type':
          'application/json; charset=utf-8',
      },
    }
  );
}

function metric(sample, key, max = 10_000_000) {
  return clampNumber(sample?.[key], 0, max);
}

function makeStatement(env, body, sample, receivedAt) {
  const sql = `
    INSERT INTO perf_samples (
      received_at,
      install_id,
      session_id,
      debug_id,
      script_version,
      app_version,
      gesture_version,
      mode,
      route_kind,
      reason,
      aggressive,
      streaming,
      phase_two,
      uptime_ms,
      mounted_turns,
      observer_callbacks,
      conversation_mutations,
      sidebar_mutations,
      turn_refreshes,
      tool_nodes_processed,
      tool_groups,
      tool_collapsed,
      loop_count,
      loop_avg_ms,
      loop_max_ms,
      loop_gt50,
      loop_gt100,
      loop_gt250,
      raf_count,
      raf_max_ms,
      raf_gt50,
      raf_gt100,
      raf_gt250,
      conversation_observer_ms,
      sidebar_observer_ms,
      turn_scan_ms,
      tool_process_ms
    ) VALUES (
      ?,?,?,?,?,?,?,?,?,?,
      ?,?,?,?,?,?,?,?,?,?,
      ?,?,?,?,?,?,?,?,?,?,
      ?,?,?,?,?,?,?
    )
  `;

  return env.DB.prepare(sql).bind(
    receivedAt,
    safeString(body.installId, 64),
    safeString(body.sessionId, 48),
    safeString(sample.debugId, 48),
    safeString(body.scriptVersion, 24),
    safeString(body.appVersion, 24),
    safeString(body.gestureVersion, 24),
    safeString(sample.mode, 16),
    safeString(sample.routeKind, 24),
    safeString(sample.reason, 24),
    asInt(sample.aggressive),
    asInt(sample.streaming),
    asInt(sample.phaseTwo),
    metric(sample, 'uptimeMs', 86_400_000),
    metric(sample, 'mountedTurns', 100_000),
    metric(sample, 'observerCallbacks'),
    metric(sample, 'conversationMutations'),
    metric(sample, 'sidebarMutations'),
    metric(sample, 'turnRefreshes'),
    metric(sample, 'toolNodesProcessed'),
    metric(sample, 'toolGroups', 100_000),
    metric(sample, 'toolCollapsed', 100_000),
    metric(sample, 'loopCount', 100_000),
    metric(sample, 'loopAvgMs', 60_000),
    metric(sample, 'loopMaxMs', 60_000),
    metric(sample, 'loopGt50', 100_000),
    metric(sample, 'loopGt100', 100_000),
    metric(sample, 'loopGt250', 100_000),
    metric(sample, 'rafCount', 1_000_000),
    metric(sample, 'rafMaxMs', 60_000),
    metric(sample, 'rafGt50', 1_000_000),
    metric(sample, 'rafGt100', 1_000_000),
    metric(sample, 'rafGt250', 1_000_000),
    metric(sample, 'conversationObserverMs', 60_000),
    metric(sample, 'sidebarObserverMs', 60_000),
    metric(sample, 'turnScanMs', 60_000),
    metric(sample, 'toolProcessMs', 60_000)
  );
}

async function ingest(request, env, headers) {
  const length =
    Number(
      request.headers.get(
        'content-length'
      ) || 0
    );

  if (
    length > 0 &&
    length > MAX_BODY_BYTES
  ) {
    return json(
      { ok: false, error: 'body_too_large' },
      413,
      headers
    );
  }

  let body;

  try {
    body = await request.json();
  } catch {
    return json(
      { ok: false, error: 'invalid_json' },
      400,
      headers
    );
  }

  if (
    body?.schema !== 1 ||
    !/^[A-Za-z0-9_-]{8,64}$/.test(
      String(body.installId || '')
    ) ||
    !/^[A-Za-z0-9_-]{8,48}$/.test(
      String(body.sessionId || '')
    ) ||
    !Array.isArray(body.samples) ||
    body.samples.length < 1 ||
    body.samples.length > MAX_SAMPLES
  ) {
    return json(
      { ok: false, error: 'invalid_schema' },
      400,
      headers
    );
  }

  const receivedAt = Date.now();
  const statements = [];

  for (const sample of body.samples) {
    if (
      !sample ||
      typeof sample !== 'object'
    ) {
      continue;
    }

    statements.push(
      makeStatement(
        env,
        body,
        sample,
        receivedAt
      )
    );
  }

  if (!statements.length) {
    return json(
      { ok: false, error: 'empty_samples' },
      400,
      headers
    );
  }

  await env.DB.batch(statements);

  return json(
    {
      ok: true,
      accepted: statements.length,
    },
    202,
    headers
  );
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const headers =
      corsHeaders(
        request.headers.get('Origin')
      );

    if (request.method === 'OPTIONS') {
      return new Response(null, {
        status: 204,
        headers,
      });
    }

    if (
      request.method === 'GET' &&
      url.pathname === '/health'
    ) {
      return json(
        {
          ok: true,
          service:
            'chatgpt-web-telemetry',
          schema: 1,
          storage: 'd1',
        },
        200,
        headers
      );
    }

    if (
      request.method === 'GET' &&
      url.pathname === '/v1/config'
    ) {
      return json(
        {
          schema: 1,
          telemetry: {
            sampleMs: 15000,
            loopProbeMs: 1000,
            flushMs: 30000,
            maxBatch: 20,
            debugDurationMs: 180000,
          },
        },
        200,
        headers
      );
    }

    if (
      request.method === 'POST' &&
      url.pathname === '/v1/telemetry'
    ) {
      return ingest(
        request,
        env,
        headers
      );
    }

    return json(
      { ok: false, error: 'not_found' },
      404,
      headers
    );
  },
};
