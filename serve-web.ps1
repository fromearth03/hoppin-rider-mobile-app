# Serves the built web app for review.
#
# `flutter run -d web-server` keeps a debug service alive and dies when its
# parent goes away; a review session outlives that. This serves the static
# bundle from build/web instead, so the URL stays up.
#
#   flutter build web --dart-define-from-file=../config/dev.json   (from app/)
#   powershell -File serve-web.ps1
#
param(
    [int]$Port = 8080,
    [string]$Root = "$PSScriptRoot\app\build\web"
)

if (-not (Test-Path $Root)) {
    Write-Error "No build at $Root. Run: cd app; flutter build web --dart-define-from-file=../config/dev.json"
    exit 1
}

$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://127.0.0.1:$Port/")
$listener.Start()
Write-Host "Serving $Root at http://127.0.0.1:$Port/"

$mime = @{
    '.html' = 'text/html; charset=utf-8'
    '.js'   = 'application/javascript; charset=utf-8'
    '.mjs'  = 'application/javascript; charset=utf-8'
    '.css'  = 'text/css; charset=utf-8'
    '.json' = 'application/json; charset=utf-8'
    '.wasm' = 'application/wasm'
    '.png'  = 'image/png'
    '.jpg'  = 'image/jpeg'
    '.svg'  = 'image/svg+xml'
    '.ico'  = 'image/x-icon'
    '.otf'  = 'font/otf'
    '.ttf'  = 'font/ttf'
    '.woff' = 'font/woff'
    '.woff2' = 'font/woff2'
}

try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $path = [Uri]::UnescapeDataString($context.Request.Url.AbsolutePath.TrimStart('/'))
        if ([string]::IsNullOrWhiteSpace($path)) { $path = 'index.html' }

        $file = Join-Path $Root $path
        # Client-side routing: an unknown path is a Flutter route, not a 404,
        # so unmatched requests fall back to the app shell.
        if (-not (Test-Path $file -PathType Leaf)) {
            $file = Join-Path $Root 'index.html'
        }

        try {
            $bytes = [System.IO.File]::ReadAllBytes($file)
            $ext = [System.IO.Path]::GetExtension($file).ToLower()
            $context.Response.ContentType =
                if ($mime.ContainsKey($ext)) { $mime[$ext] } else { 'application/octet-stream' }
            $context.Response.Headers.Add('Cache-Control', 'no-store')
            $context.Response.ContentLength64 = $bytes.Length
            $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
        } catch {
            $context.Response.StatusCode = 500
        } finally {
            $context.Response.OutputStream.Close()
        }
    }
} finally {
    $listener.Stop()
}
