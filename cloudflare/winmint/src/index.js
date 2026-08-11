const DEFAULT_BOOTSTRAP_URL =
  "https://raw.githubusercontent.com/yanai-sh/winmint/main/winmint.ps1";

const BOOTSTRAP_PATHS = new Set(["/", "/winmint", "/winmint.ps1"]);
const CLI_PATHS = new Set(["/cli", "/cli.ps1"]);
const PRIMARY_GATE_PATHS = new Set(["/primary-gate", "/primary-gate.ps1"]);
const VALIDATE_PATHS = new Set(["/validate", "/validate.ps1"]);

function escapePsSingleQuoted(value) {
  return String(value).replace(/'/g, "''");
}

function queryString(searchParams, key) {
  if (!searchParams.has(key)) {
    return null;
  }
  const raw = searchParams.get(key);
  if (raw == null || /[\r\n\0]/.test(raw)) {
    throw new Error(`Invalid query value for ${key}`);
  }
  return raw;
}

function bakedForwardArgs(searchParams, extras) {
  const work = queryString(searchParams, "Work");
  const repository = queryString(searchParams, "Repository");
  const version = queryString(searchParams, "Version");
  const force = searchParams.has("Force");
  const cacheRelease = searchParams.has("CacheRelease");
  const lines = [];
  for (const [key, value] of Object.entries(extras)) {
    if (typeof value === "boolean") {
      if (value) {
        lines.push(`  ${key} = $true`);
      }
    } else {
      lines.push(`  ${key} = '${escapePsSingleQuoted(value)}'`);
    }
  }
  if (work) {
    lines.push(`  Work = '${escapePsSingleQuoted(work)}'`);
  }
  if (repository) {
    lines.push(`  Repository = '${escapePsSingleQuoted(repository)}'`);
  }
  if (version) {
    lines.push(`  Version = '${escapePsSingleQuoted(version)}'`);
  }
  if (force) {
    lines.push("  Force = $true");
  }
  if (cacheRelease) {
    lines.push("  CacheRelease = $true");
  }
  return lines;
}

function cliWrapper(origin) {
  const bootstrapUrl = `${origin}/`;
  return `#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Repository = 'yanai-sh/winmint',
    [string]$Version = 'latest',
    [string]$InstallRoot = '',
    [string]$ProfilePath = '',
    [string]$SourceIso = '',
    [string]$Work = '',
    [switch]$ValidateOnly,
    [switch]$PrimaryGate,
    [switch]$NoLaunch,
    [switch]$Force,
    [switch]$CacheRelease
)

$ErrorActionPreference = 'Stop'
$bootstrap = Invoke-RestMethod -UseBasicParsing -Uri '${bootstrapUrl}'
$forward = @{}
foreach ($key in $PSBoundParameters.Keys) {
    $forward[$key] = $PSBoundParameters[$key]
}
if ($PrimaryGate) {
    & ([scriptblock]::Create($bootstrap)) @forward
} else {
    & ([scriptblock]::Create($bootstrap)) -Headless @forward
}
`;
}

function primaryGateWrapper(origin, searchParams) {
  const bootstrapUrl = `${origin}/`;
  const sourceIso = queryString(searchParams, "SourceIso");
  const profilePath =
    queryString(searchParams, "ProfilePath") ?? "samples/sl7.profile.json";

  const lines = [
    "#Requires -Version 5.1",
    "$ErrorActionPreference = 'Stop'",
    `if ([string]::IsNullOrWhiteSpace('${escapePsSingleQuoted(sourceIso ?? "")}')) {`,
    "  throw 'Usage: irm ''https://winmint.yanai.sh/primary-gate?SourceIso=C:\\path\\to\\source.iso&ProfilePath=samples\\sl7.profile.json'' | iex'",
    "}",
    `$bootstrap = Invoke-RestMethod -UseBasicParsing -Uri '${bootstrapUrl}'`,
    "$args = @{",
    ...bakedForwardArgs(searchParams, {
      PrimaryGate: true,
      SourceIso: sourceIso ?? "",
      ProfilePath: profilePath,
    }),
    "}",
    "& ([scriptblock]::Create($bootstrap)) @args",
    "",
  ];
  return lines.join("\n");
}

function validateWrapper(origin, searchParams) {
  const bootstrapUrl = `${origin}/`;
  const profilePath =
    queryString(searchParams, "ProfilePath") ?? "samples/smoke.profile.json";

  const lines = [
    "#Requires -Version 5.1",
    "$ErrorActionPreference = 'Stop'",
    `$bootstrap = Invoke-RestMethod -UseBasicParsing -Uri '${bootstrapUrl}'`,
    "$args = @{",
    ...bakedForwardArgs(searchParams, {
      Headless: true,
      ValidateOnly: true,
      ProfilePath: profilePath,
    }),
    "}",
    "& ([scriptblock]::Create($bootstrap)) @args",
    "",
  ];
  return lines.join("\n");
}

function textResponse(body, status = 200, extraHeaders = {}) {
  return new Response(body, {
    status,
    headers: {
      "content-type": "text/plain; charset=utf-8",
      "cache-control": "no-store",
      "x-content-type-options": "nosniff",
      ...extraHeaders,
    },
  });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (
      url.pathname === "/winmint/" ||
      url.pathname === "/cli/" ||
      url.pathname === "/primary-gate/" ||
      url.pathname === "/validate/"
    ) {
      return Response.redirect(`${url.origin}${url.pathname.slice(0, -1)}`, 308);
    }

    if (
      !BOOTSTRAP_PATHS.has(url.pathname) &&
      !CLI_PATHS.has(url.pathname) &&
      !PRIMARY_GATE_PATHS.has(url.pathname) &&
      !VALIDATE_PATHS.has(url.pathname)
    ) {
      return textResponse("Not found\n", 404);
    }

    if (request.method !== "GET" && request.method !== "HEAD") {
      return textResponse("Method not allowed\n", 405, { allow: "GET, HEAD" });
    }

    const headers = {
      "content-type": "text/plain; charset=utf-8",
      "cache-control": "public, max-age=300",
      "x-content-type-options": "nosniff",
    };

    if (request.method === "HEAD") {
      return new Response(null, { status: 200, headers });
    }

    if (CLI_PATHS.has(url.pathname)) {
      return new Response(cliWrapper(url.origin), { status: 200, headers });
    }

    if (PRIMARY_GATE_PATHS.has(url.pathname)) {
      try {
        return new Response(primaryGateWrapper(url.origin, url.searchParams), {
          status: 200,
          headers,
        });
      } catch (err) {
        return textResponse(`${err.message || err}\n`, 400);
      }
    }

    if (VALIDATE_PATHS.has(url.pathname)) {
      try {
        return new Response(validateWrapper(url.origin, url.searchParams), {
          status: 200,
          headers,
        });
      } catch (err) {
        return textResponse(`${err.message || err}\n`, 400);
      }
    }

    const bootstrapUrl = env.BOOTSTRAP_URL || DEFAULT_BOOTSTRAP_URL;
    const upstream = await fetch(bootstrapUrl, {
      headers: { "user-agent": "WinMint-Bootstrap-Worker" },
      cf: { cacheEverything: true, cacheTtl: 300 },
    });

    if (!upstream.ok) {
      return textResponse(`Bootstrap source returned HTTP ${upstream.status}\n`, 502);
    }

    return new Response(await upstream.text(), { status: 200, headers });
  },
};
