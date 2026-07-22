param(
    [Parameter(Mandatory = $true)]
    [string]$ApkPath,
    [string]$AppName = "",
    [string]$Variant = "",
    [string]$ChatId = "",
    [string]$FolderToken = "",
    [ValidateSet("auto", "drive-link", "im-file")]
    [string]$Mode = "auto",
    [string]$ConfigPath = "",
    [string]$FlutterAppVersion = ""
)

$ErrorActionPreference = "Stop"

$skillRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $skillRoot "config\feishu.local.json"
}

function Read-JsonFile([string]$path) {
    if (-not (Test-Path $path)) {
        throw "Missing Feishu config at $path. Copy config\feishu.example.json to config\feishu.local.json and fill it."
    }
    return Get-Content -Raw $path | ConvertFrom-Json
}

function Invoke-FeishuJson(
    [string]$Method,
    [string]$Uri,
    [hashtable]$Headers,
    [object]$Body = $null
) {
    $json = $null
    if ($null -ne $Body) {
        $json = $Body | ConvertTo-Json -Depth 20 -Compress
    }
    try {
        $response = Invoke-RestMethod -Method $Method -Uri $Uri -Headers $Headers -Body $json -ContentType "application/json"
    } catch {
        $body = ""
        if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
            $body = $_.ErrorDetails.Message
        }
        if ($body -match '"code"\s*:\s*1061044') {
            throw "Feishu Drive parent folder was not found or is not accessible by this app. Check default_folder_token or pass -FolderToken. Token should come from a Feishu Drive folder URL, and the app must have permission. Raw response: $body"
        }
        throw
    }
    if ($null -ne $response.code -and $response.code -ne 0) {
        throw "Feishu API failed: $($response | ConvertTo-Json -Depth 10 -Compress)"
    }
    return $response
}

function Upload-DriveFileInParts(
    [string]$BaseUrl,
    [string]$Token,
    [System.IO.FileInfo]$File,
    [string]$ParentNode
) {
    $prepare = Invoke-FeishuJson `
        -Method "POST" `
        -Uri "$BaseUrl/drive/v1/files/upload_prepare" `
        -Headers @{ Authorization = "Bearer $Token" } `
        -Body @{
            file_name = $File.Name
            parent_type = "explorer"
            parent_node = $ParentNode
            size = $File.Length
        }

    $uploadId = [string]$prepare.data.upload_id
    $blockSize = [int64]$prepare.data.block_size
    $blockNum = [int]$prepare.data.block_num
    if ([string]::IsNullOrWhiteSpace($uploadId) -or $blockSize -le 0 -or $blockNum -le 0) {
        throw "Feishu upload_prepare response is invalid: $($prepare | ConvertTo-Json -Depth 10 -Compress)"
    }

    Write-Host ("Feishu multipart upload_id: " + $uploadId)
    Write-Host ("Feishu multipart blocks: " + $blockNum + ", block_size: " + $blockSize)

    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("gkprep-feishu-upload-" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tempDir | Out-Null
    try {
        $input = [System.IO.File]::OpenRead($File.FullName)
        try {
            $buffer = New-Object byte[] $blockSize
            for ($seq = 0; $seq -lt $blockNum; $seq++) {
                $read = $input.Read($buffer, 0, $buffer.Length)
                if ($read -le 0) {
                    throw "Unexpected end of file at block $seq"
                }

                $chunkPath = Join-Path $tempDir ("part-" + $seq)
                $output = [System.IO.File]::Open($chunkPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
                try {
                    $output.Write($buffer, 0, $read)
                } finally {
                    $output.Dispose()
                }

                Write-Host ("Uploading part " + ($seq + 1) + "/" + $blockNum)
                $partRaw = & curl.exe -s -X POST "$BaseUrl/drive/v1/files/upload_part" `
                    -H "Authorization: Bearer $Token" `
                    -F "upload_id=$uploadId" `
                    -F "seq=$seq" `
                    -F "size=$read" `
                    -F "file=@$chunkPath"
                if ($LASTEXITCODE -ne 0) {
                    throw "curl upload_part failed with exit code $LASTEXITCODE"
                }
                $partResp = $partRaw | ConvertFrom-Json
                if ($null -ne $partResp.code -and $partResp.code -ne 0) {
                    throw "Feishu upload_part failed: $($partResp | ConvertTo-Json -Depth 10 -Compress)"
                }

                Remove-Item -LiteralPath $chunkPath -Force
            }
        } finally {
            $input.Dispose()
        }
    } finally {
        Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    $finish = Invoke-FeishuJson `
        -Method "POST" `
        -Uri "$BaseUrl/drive/v1/files/upload_finish" `
        -Headers @{ Authorization = "Bearer $Token" } `
        -Body @{
            upload_id = $uploadId
            block_num = $blockNum
        }

    return $finish
}

function Get-FlutterAppVersionLine([string]$value) {
    if ([string]::IsNullOrWhiteSpace($value)) {
        return ""
    }

    $label = "flutter" + [string]::Concat(
        [char]0x5347,
        [char]0x7EA7,
        [char]0x5305,
        [char]0x5339,
        [char]0x914D,
        [char]0x533A,
        [char]0x95F4,
        [char]0x503C,
        [char]0xFF1A
    )
    return $label + $value
}

if (-not (Test-Path $ApkPath)) {
    throw "APK does not exist: $ApkPath"
}

$config = Read-JsonFile $ConfigPath
$appId = [string]$config.app_id
$appSecret = [string]$config.app_secret
if ([string]::IsNullOrWhiteSpace($appId) -or [string]::IsNullOrWhiteSpace($appSecret)) {
    throw "Feishu config requires app_id and app_secret"
}

if ([string]::IsNullOrWhiteSpace($ChatId)) {
    $ChatId = [string]$config.default_chat_id
}
if ([string]::IsNullOrWhiteSpace($FolderToken)) {
    $FolderToken = [string]$config.default_folder_token
}
if ($Mode -eq "auto" -and -not [string]::IsNullOrWhiteSpace([string]$config.mode)) {
    $Mode = [string]$config.mode
}
if ([string]::IsNullOrWhiteSpace($ChatId)) {
    throw "Missing chat id. Set default_chat_id in config or pass -ChatId."
}

$baseUrl = "https://open.feishu.cn/open-apis"
$tokenResp = Invoke-FeishuJson `
    -Method "POST" `
    -Uri "$baseUrl/auth/v3/tenant_access_token/internal" `
    -Headers @{} `
    -Body @{ app_id = $appId; app_secret = $appSecret }

$token = [string]$tokenResp.tenant_access_token
if ([string]::IsNullOrWhiteSpace($token)) {
    throw "Feishu token response did not include tenant_access_token"
}

$headers = @{ Authorization = "Bearer $token" }
$file = Get-Item -LiteralPath $ApkPath
$sizeMb = [Math]::Round($file.Length / 1MB, 2)
$parentNode = ""
if (-not [string]::IsNullOrWhiteSpace($FolderToken)) {
    $parentNode = $FolderToken
}

Write-Host ("Feishu upload mode: " + $Mode)
Write-Host ("Feishu chat: " + $ChatId)
Write-Host ("Feishu file: " + $file.Name)
Write-Host ("Feishu size: " + $sizeMb + " MB")

$flutterAppVersionLine = Get-FlutterAppVersionLine $FlutterAppVersion
$appLabel = if ([string]::IsNullOrWhiteSpace($AppName)) { "Android" } else { $AppName }

$resolvedMode = $Mode
if ($resolvedMode -eq "auto") {
    if ([string]::IsNullOrWhiteSpace($FolderToken)) {
        $resolvedMode = "im-file"
    } else {
        $resolvedMode = "drive-link"
    }
}

if ($resolvedMode -eq "drive-link" -and [string]::IsNullOrWhiteSpace($FolderToken)) {
    throw "Feishu drive-link mode requires default_folder_token in config/feishu.local.json or -FolderToken."
}

if ($resolvedMode -eq "drive-link" -and $FolderToken -notmatch '^(fld|box|nod|[A-Za-z0-9_-]{16,})') {
    Write-Warning "Folder token format is unusual. Use the token from a Feishu Drive folder URL and make sure this app can access it."
}

if ($resolvedMode -eq "im-file" -and $file.Length -gt 30MB) {
    throw "Feishu IM file mode cannot send this APK because it is $sizeMb MB. Configure default_folder_token and use drive-link mode."
}

if ($resolvedMode -eq "im-file") {
    $uploadRaw = & curl.exe -s -X POST "$baseUrl/im/v1/files" `
        -H "Authorization: Bearer $token" `
        -F "file_type=stream" `
        -F "file_name=$($file.Name)" `
        -F "file=@$($file.FullName)"
    if ($LASTEXITCODE -ne 0) {
        throw "curl IM file upload failed with exit code $LASTEXITCODE"
    }

    $uploadResp = $uploadRaw | ConvertFrom-Json
    if ($null -ne $uploadResp.code -and $uploadResp.code -ne 0) {
        throw "Feishu IM file upload failed: $($uploadResp | ConvertTo-Json -Depth 10 -Compress)"
    }

    $fileKey = [string]$uploadResp.data.file_key
    if ([string]::IsNullOrWhiteSpace($fileKey)) {
        throw "Feishu IM file upload response did not include file_key"
    }

    $message = @(
        "$appLabel APK build completed",
        "",
        "Variant: $Variant",
        "File: $($file.Name)",
        "Size: $sizeMb MB"
    )
    if (-not [string]::IsNullOrWhiteSpace($flutterAppVersionLine)) {
        $message += $flutterAppVersionLine
    }
    $message = $message -join "`n"

    Invoke-FeishuJson `
        -Method "POST" `
        -Uri "$baseUrl/im/v1/messages?receive_id_type=chat_id" `
        -Headers $headers `
        -Body @{
            receive_id = $ChatId
            msg_type = "text"
            content = (@{ text = $message } | ConvertTo-Json -Compress)
        } | Out-Null

    Invoke-FeishuJson `
        -Method "POST" `
        -Uri "$baseUrl/im/v1/messages?receive_id_type=chat_id" `
        -Headers $headers `
        -Body @{
            receive_id = $ChatId
            msg_type = "file"
            content = (@{ file_key = $fileKey } | ConvertTo-Json -Compress)
        } | Out-Null

    Write-Host ("Feishu file_key: " + $fileKey)
    Write-Host "Feishu file message sent."
    exit 0
}

if ($file.Length -gt 20MB) {
    $uploadResp = Upload-DriveFileInParts -BaseUrl $baseUrl -Token $token -File $file -ParentNode $parentNode
} else {
    $uploadRaw = & curl.exe -s -X POST "$baseUrl/drive/v1/files/upload_all" `
        -H "Authorization: Bearer $token" `
        -F "file_name=$($file.Name)" `
        -F "parent_type=explorer" `
        -F "parent_node=$parentNode" `
        -F "size=$($file.Length)" `
        -F "file=@$($file.FullName)"
    if ($LASTEXITCODE -ne 0) {
        throw "curl Drive upload failed with exit code $LASTEXITCODE"
    }

    $uploadResp = $uploadRaw | ConvertFrom-Json
    if ($null -ne $uploadResp.code -and $uploadResp.code -ne 0) {
        throw "Feishu Drive upload failed: $($uploadResp | ConvertTo-Json -Depth 10 -Compress)"
    }
}

$fileToken = [string]$uploadResp.data.file_token
if ([string]::IsNullOrWhiteSpace($fileToken)) {
    throw "Feishu Drive upload response did not include file_token"
}

$fileUrl = ""
if ($uploadResp.data.url) {
    $fileUrl = [string]$uploadResp.data.url
}

$messageLines = @(
    "$appLabel APK build completed",
    "",
    "Variant: $Variant",
    "File: $($file.Name)",
    "Size: $sizeMb MB",
    "File token: $fileToken"
)
if (-not [string]::IsNullOrWhiteSpace($flutterAppVersionLine)) {
    $messageLines += $flutterAppVersionLine
}
if (-not [string]::IsNullOrWhiteSpace($fileUrl)) {
    $messageLines += "URL: $fileUrl"
} else {
    $messageLines += "Uploaded to Feishu Drive. Use file token to locate the file if no URL is returned."
}

Invoke-FeishuJson `
    -Method "POST" `
    -Uri "$baseUrl/im/v1/messages?receive_id_type=chat_id" `
    -Headers $headers `
    -Body @{
        receive_id = $ChatId
        msg_type = "text"
        content = (@{ text = ($messageLines -join "`n") } | ConvertTo-Json -Compress)
    } | Out-Null

Write-Host ("Feishu file_token: " + $fileToken)
if (-not [string]::IsNullOrWhiteSpace($fileUrl)) {
    Write-Host ("Feishu url: " + $fileUrl)
}
Write-Host "Feishu Drive message sent."

