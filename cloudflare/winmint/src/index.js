const DEFAULT_BOOTSTRAP_URL =
  "https://raw.githubusercontent.com/yanai-sh/winmint/main/winmint.ps1";

const BOOTSTRAP_PATHS = new Set(["/", "/winmint", "/winmint.ps1"]);
const CLI_PATHS = new Set(["/cli", "/cli.ps1"]);

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
    [string]$UupDumpZip = '',
    [string]$SourceIsoOverride = '',
    [ValidateSet('amd64','arm64','x86')]
    [string]$Architecture = '',
    [switch]$DryRun,
    [switch]$ExportHostDrivers,
    [switch]$Developer,
    [switch]$Copilot,
    [switch]$DesktopUI,
    [switch]$Gaming,
    [switch]$NonInteractive,
    [switch]$ValidateOnly,
    [switch]$Json,
    [switch]$NoProgress,
    [switch]$Quiet,
    [switch]$AllowElevate,
    [switch]$Yes,
    [switch]$NoLaunch,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$bootstrap = Invoke-RestMethod -UseBasicParsing -Uri '${bootstrapUrl}'
$forward = @{}
foreach ($key in $PSBoundParameters.Keys) {
    $forward[$key] = $PSBoundParameters[$key]
}
& ([scriptblock]::Create($bootstrap)) -Headless @forward
`;
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

    if (url.pathname === "/winmint/" || url.pathname === "/cli/") {
      return Response.redirect(`${url.origin}${url.pathname.slice(0, -1)}`, 308);
    }

    if (!BOOTSTRAP_PATHS.has(url.pathname) && !CLI_PATHS.has(url.pathname)) {
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
