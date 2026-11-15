param(
    [string]$Version = "2.4.0",
    [string]$GitHubOwner = "YOUR_GITHUB_NAME",
    [string]$RepositoryName = "SGimmicks-VPM",
    [switch]$SiteOnly,
    [switch]$PackageOnly,
    [string]$PackageOutputDirectory = ""
)

$ErrorActionPreference = "Stop"

$repositoryRoot = $PSScriptRoot
$sourceProject = Join-Path (Split-Path $repositoryRoot -Parent) "SGimmicksPackageProject"
$packageId = "com.ysasa.sgimmicks"
$packageRoot = Join-Path $repositoryRoot "source\$packageId"
$docsRoot = Join-Path $repositoryRoot "docs"
$releaseRoot = Join-Path $docsRoot "packages"
if ($PackageOutputDirectory) {
    if (-not $PackageOnly) { throw "PackageOutputDirectoryはPackageOnlyと併用してください。" }
    $releaseRoot = [IO.Path]::GetFullPath($PackageOutputDirectory)
}
$templateRoot = Join-Path $repositoryRoot "templates"
$baseUrl = "https://$GitHubOwner.github.io/$RepositoryName"
$packageUrl = "$baseUrl/packages/$packageId-$Version.zip"

function Write-RepositorySite {
    $htmlTemplate = Get-Content -LiteralPath (Join-Path $templateRoot "index.html") -Raw
    $html = $htmlTemplate.Replace("{{REPOSITORY_URL}}", "$baseUrl/index.json")
    $html = $html.Replace("{{VERSION}}", $Version)
    $html = $html.Replace("{{PACKAGE_URL}}", $packageUrl)
    $html | Set-Content -LiteralPath (Join-Path $docsRoot "index.html") -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $docsRoot ".nojekyll") -Value "" -Encoding ASCII
}

if ($SiteOnly) {
    if ($PackageOnly) { throw "SiteOnlyとPackageOnlyは併用できません。" }
    Write-RepositorySite
    Write-Host "Repository website: $baseUrl/"
    exit 0
}

if (-not (Test-Path -LiteralPath $sourceProject)) {
    throw "SGimmicksPackageProjectが見つかりません: $sourceProject"
}

function Remove-PackageOutput([string]$Target) {
    $fullTarget = [IO.Path]::GetFullPath($Target)
    $fullPackage = [IO.Path]::GetFullPath($packageRoot)
    $expectedPackage = [IO.Path]::GetFullPath((Join-Path $repositoryRoot "source\com.ysasa.sgimmicks"))
    if ($fullPackage -ne $expectedPackage -or ($fullTarget -ne $fullPackage -and -not $fullTarget.StartsWith($fullPackage + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase))) {
        throw "パッケージ作業領域の外は削除できません: $fullTarget"
    }
    if (Test-Path -LiteralPath $fullTarget) {
        if ((Get-Item -LiteralPath $fullTarget).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "リンク先は削除できません: $fullTarget" }
        Remove-Item -LiteralPath $fullTarget -Recurse -Force
    }
}
Remove-PackageOutput $packageRoot
New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null
New-Item -ItemType Directory -Path $releaseRoot -Force | Out-Null

Copy-Item -LiteralPath (Join-Path $sourceProject "Assets\SGimmicks") -Destination $packageRoot -Recurse
Copy-Item -LiteralPath (Join-Path $sourceProject "Assets\SGimmicks.meta") -Destination $packageRoot
Copy-Item -LiteralPath (Join-Path $sourceProject "Assets\CastTimerGimmick") -Destination $packageRoot -Recurse
Copy-Item -LiteralPath (Join-Path $sourceProject "Assets\CastTimerGimmick.meta") -Destination $packageRoot

$serializedRoot = Join-Path $packageRoot "SerializedUdonPrograms"
New-Item -ItemType Directory -Path $serializedRoot -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $sourceProject "Assets\SerializedUdonPrograms.meta") -Destination $packageRoot
# Assets直下へ生成されたプログラムも全て収集する。受付などの追加時に固定リストの更新漏れでMissingにしない。
$externalPrograms = @{}
Get-ChildItem -LiteralPath (Join-Path $sourceProject "Assets\SerializedUdonPrograms") -Filter '*.asset.meta' | ForEach-Object {
    $match = [regex]::Match((Get-Content -LiteralPath $_.FullName -Raw), '(?m)^guid: ([a-f0-9]{32})')
    if ($match.Success) { $externalPrograms[$match.Groups[1].Value] = $_.FullName }
}
$serializedReferences = [Collections.Generic.HashSet[string]]::new()
$legacyProgramFiles = [ordered]@{}
foreach ($sourceFolder in @('SGimmicks', 'CastTimerGimmick')) {
    Get-ChildItem -LiteralPath (Join-Path $sourceProject ("Assets\" + $sourceFolder)) -Filter '*.asset' -Recurse | ForEach-Object {
        $match = [regex]::Match((Get-Content -LiteralPath $_.FullName -Raw), 'serializedUdonProgramAsset:.*guid: ([a-f0-9]{32})')
        if ($match.Success -and $serializedReferences.Add($match.Groups[1].Value)) {
            $serializedGuid = $match.Groups[1].Value
            if ($externalPrograms.ContainsKey($serializedGuid)) {
                $metaPath = $externalPrograms[$serializedGuid]
                $assetPath = $metaPath.Substring(0, $metaPath.Length - 5)
                Copy-Item -LiteralPath $assetPath -Destination $serializedRoot
                Copy-Item -LiteralPath $metaPath -Destination $serializedRoot
                $legacyProgramFiles['Assets\SerializedUdonPrograms\' + [IO.Path]::GetFileName($assetPath)] = $serializedGuid
            }
        }
    }
}

# unitypackage専用ビルダーはVPM利用時には不要で、Packages配下へ書き込もうとするため除外する。
$legacyBuilders = @(
    (Join-Path $packageRoot "SGimmicks\Editor\SGPackageBuilder.cs"),
    (Join-Path $packageRoot "SGimmicks\Editor\SGPackageBuilder.cs.meta"),
    (Join-Path $packageRoot "SGimmicks\Editor\SGReceptionBuildChecks.cs"),
    (Join-Path $packageRoot "SGimmicks\Editor\SGReceptionBuildChecks.cs.meta"),
    (Join-Path $packageRoot "SGimmicks\Editor\SGReceptionValidationBuilder.cs"),
    (Join-Path $packageRoot "SGimmicks\Editor\SGReceptionValidationBuilder.cs.meta"),
    (Join-Path $packageRoot "SGimmicks\Editor\SGFixedInstancePortalBuildChecks.cs"),
    (Join-Path $packageRoot "SGimmicks\Editor\SGFixedInstancePortalBuildChecks.cs.meta"),
    (Join-Path $packageRoot "SGimmicks\Scenes\ReceptionValidation.unity"),
    (Join-Path $packageRoot "SGimmicks\Scenes\ReceptionValidation.unity.meta"),
    (Join-Path $packageRoot "CastTimerGimmick\Editor") ,
    (Join-Path $packageRoot "CastTimerGimmick\Editor.meta")
)
foreach ($legacyBuilder in $legacyBuilders) {
    Remove-PackageOutput $legacyBuilder
}

# 公開用は導入者自身の公開URLを設定する。個別の検証先を初期値として配布しない。
$receptionWindow = Join-Path $packageRoot 'SGimmicks\Editor\SGReceptionWindow.cs'
if (Test-Path -LiteralPath $receptionWindow) {
    $sourceText = Get-Content -LiteralPath $receptionWindow -Raw
    $sourceText = [regex]::Replace($sourceText, 'private const string DefaultApi = "[^"]*";', 'private const string DefaultApi = "";')
    [IO.File]::WriteAllText($receptionWindow, $sourceText, [Text.UTF8Encoding]::new($false))
}
$packagedGuids = [Collections.Generic.HashSet[string]]::new()
Get-ChildItem -LiteralPath $packageRoot -Filter '*.meta' -Recurse | ForEach-Object {
    $match = [regex]::Match((Get-Content -LiteralPath $_.FullName -Raw), '(?m)^guid: ([a-f0-9]{32})')
    if ($match.Success) { [void]$packagedGuids.Add($match.Groups[1].Value) }
}
foreach ($serializedGuid in $serializedReferences) {
    if (-not $packagedGuids.Contains($serializedGuid)) { throw "Serialized Udon Programが不足しています: $serializedGuid" }
}

# RuntimeをUdonSharpアセンブリとして明示登録し、Editorは通常のEditor asmdefへ分離する。
# これによりPackages配下でもUdonSharpBehaviourとEditor拡張の両方を解決できる。
Copy-Item -LiteralPath (Join-Path $templateRoot "SGimmicks.Runtime.asmdef") -Destination $packageRoot
Copy-Item -LiteralPath (Join-Path $templateRoot "SGimmicks.Runtime.asmdef.meta") -Destination $packageRoot
Copy-Item -LiteralPath (Join-Path $templateRoot "SGimmicks.Runtime.asset") -Destination $packageRoot
Copy-Item -LiteralPath (Join-Path $templateRoot "SGimmicks.Runtime.asset.meta") -Destination $packageRoot
$sgEditorRoot = Join-Path $packageRoot "SGimmicks\Editor"
Copy-Item -LiteralPath (Join-Path $templateRoot "SGimmicks.Editor.asmdef") -Destination $sgEditorRoot
Copy-Item -LiteralPath (Join-Path $templateRoot "SGimmicks.Editor.asmdef.meta") -Destination $sgEditorRoot

$manifest = [ordered]@{
    name = $packageId
    displayName = "SGimmicks"
    version = $Version
    unity = "2022.3"
    description = "PC向けVRChatワールド用ギミック集。固定インスタンスポータル（検証用）、カード受付・来店管理、テレポート、監視カメラ、内線、照明、お題表示、囁き声判定、透過画像立体化、VIZVIDシネマ、ローカル自動ドア、RTab注文・物体転送などを収録。"
    url = $packageUrl
    vpmDependencies = [ordered]@{
        "com.vrchat.worlds" = "3.10.x"
    }
    author = [ordered]@{
        name = "ysasa"
        email = "ysasa@users.noreply.github.com"
        url = "https://github.com/$GitHubOwner"
    }
    legacyFolders = [ordered]@{
        "Assets\SGimmicks" = "4266535577e7c06439e201b5910eba59"
        "Assets\CastTimerGimmick" = "b78e7576d609426409f7786d6e3ecab6"
    }
    legacyFiles = $legacyProgramFiles
}
$manifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $packageRoot "package.json") -Encoding UTF8
Copy-Item -LiteralPath (Join-Path $templateRoot "package.json.meta") -Destination $packageRoot

$zipPath = Join-Path $releaseRoot "$packageId-$Version.zip"
if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}
Compress-Archive -Path (Join-Path $packageRoot "*") -DestinationPath $zipPath -CompressionLevel Optimal
$hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash
$listingManifest = [ordered]@{}
foreach ($key in $manifest.Keys) {
    $listingManifest[$key] = $manifest[$key]
}
$listingManifest["zipSHA256"] = $hash

if ($PackageOnly) {
    Write-Host "Local VPM package: $zipPath"
    Write-Host "SHA256: $hash"
    Write-Host "Repository listing and website were not changed."
    exit 0
}

$indexPath = Join-Path $docsRoot "index.json"
if (Test-Path -LiteralPath $indexPath) {
    $repository = Get-Content -LiteralPath $indexPath -Raw | ConvertFrom-Json -AsHashtable
} else {
    $repository = [ordered]@{
        name = "SGimmicks VPM Repository"
        id = "com.ysasa.sgimmicks.repository"
        url = "$baseUrl/index.json"
        author = "ysasa"
        description = "PC向けVRChatワールド用ギミック集 SGimmicks のVPMリポジトリ"
        packages = [ordered]@{}
    }
}

$repository.name = "SGimmicks VPM Repository"
$repository.id = "com.ysasa.sgimmicks.repository"
$repository.url = "$baseUrl/index.json"
$repository.author = "ysasa"
$repository.description = "PC向けVRChatワールド用ギミック集 SGimmicks のVPMリポジトリ"
if (-not $repository.Contains("packages")) {
    $repository.packages = [ordered]@{}
}
if (-not $repository.packages.Contains($packageId)) {
    $repository.packages[$packageId] = [ordered]@{ versions = [ordered]@{} }
}
if (-not $repository.packages[$packageId].Contains("versions")) {
    $repository.packages[$packageId].versions = [ordered]@{}
}
$repository.packages[$packageId].versions[$Version] = $listingManifest
$repository | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $indexPath -Encoding UTF8

Write-RepositorySite

Write-Host "VPM package: $zipPath"
Write-Host "Repository JSON: $indexPath"
Write-Host "VCC repository URL: $baseUrl/index.json"
Write-Host "SHA256: $hash"
