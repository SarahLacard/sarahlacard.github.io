# Build script for generating entries
$ErrorActionPreference = "Stop"
$VerbosePreference = "Continue"

# Add System.Web assembly for HTML encoding
Add-Type -AssemblyName System.Web

# Verify we're in the correct directory
if (-not (Test-Path ".git")) {
    throw "Must run from repository root directory"
}

function Write-Log {
    param([string]$Message)
    try {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logMessage = "[$timestamp] $Message"
        Write-Verbose $logMessage
        Add-Content -Path "build.log" -Value $logMessage -ErrorAction Stop
    }
    catch {
        Write-Warning "Could not write to log file: $($_.Exception.Message)"
        Write-Verbose $logMessage
    }
}

function Write-FileInfo {
    param([string]$FilePath)
    if (Test-Path $FilePath) {
        $file = Get-Item $FilePath
        Write-Log "File: $FilePath"
        Write-Log "  Last Write Time: $($file.LastWriteTime)"
        Write-Log "  Size: $($file.Length) bytes"
    } else {
        Write-Log "File not found: $FilePath"
    }
}

# Function to clean up orphaned HTML files
function Remove-OrphanedHtml {
    param (
        [string]$sourceDir,
        [string]$outputDir,
        [string]$sourceExtension = ".txt"
    )
    
    Write-Log "Cleaning up orphaned HTML files in $outputDir"
    
    # Get all HTML files
    if (Test-Path "$outputDir/*.html") {
        Get-ChildItem "$outputDir/*.html" | ForEach-Object {
            $htmlFile = $_
            $sourceFile = if ($sourceDir -eq "_vera") {
                Join-Path $sourceDir "log.txt"
            } else {
                Join-Path $sourceDir ($htmlFile.BaseName + $sourceExtension)
            }
            
            # If corresponding source file doesn't exist, remove the html file
            if (-not (Test-Path $sourceFile)) {
                Write-Log "Removing orphaned file: $($htmlFile.Name)"
                Remove-Item $htmlFile.FullName -Force
            }
        }
    }
}

try {
    Write-Log "Starting build..."

    # Verify required directories exist
    @("_weblogs", "_dialogues", "_vera", "_sessions", "_templates", "weblogs", "dialogues", "vera", "sessions") | ForEach-Object {
        Write-Log "Checking directory: $_"
        if (-not (Test-Path $_)) {
            Write-Log "Creating directory: $_"
            New-Item -ItemType Directory -Path $_ -ErrorAction Stop
        }
    }

    # Clean up orphaned files first
    Remove-OrphanedHtml "_weblogs" "weblogs"
    Remove-OrphanedHtml "_dialogues" "dialogues"
    Remove-OrphanedHtml "_vera" "vera"
    Remove-OrphanedHtml "_sessions" "sessions" ".jsonl"

    # Verify template files exist
    @("_templates/post.html", "_templates/vera.html", "_templates/session.html") | ForEach-Object {
        if (-not (Test-Path $_)) {
            throw "Required template file not found: $_"
        }
    }

    # Read templates
    Write-Log "Reading templates"
    $postTemplate = Get-Content -Raw "_templates/post.html" -ErrorAction Stop
    $veraTemplate = Get-Content -Raw "_templates/vera.html" -ErrorAction Stop
    $sessionTemplate = Get-Content -Raw "_templates/session.html" -ErrorAction Stop

    # Function to convert entries for a section
    function Convert-Section {
        param (
            [string]$sourceDir,
            [string]$outputDir,
            [string]$sectionPattern,
            [string]$template = $postTemplate,
            [switch]$isVera,
            [switch]$isSessions
        )
        
        Write-Log "Converting section: $sourceDir -> $outputDir"
        $entries = @()
        
        if ($isVera) {
            # Handle Vera's commentary
            $veraLog = Join-Path $sourceDir "log.txt"
            if (Test-Path $veraLog) {
                Write-Log "Converting Vera's commentary"
                Write-FileInfo $veraLog
                
                # Read content with UTF8 encoding
                $content = Get-Content -Raw -Encoding UTF8 $veraLog -ErrorAction Stop
                
                # Apply template without HTML encoding
                $html = $template -replace "{{content}}", $content
                
                # Generate output filename and ensure directory exists
                $outputDirPath = Join-Path (Get-Location) $outputDir
                $outputFile = Join-Path $outputDirPath "log.html"
                if (-not (Test-Path $outputDirPath)) {
                    New-Item -ItemType Directory -Path $outputDirPath -Force | Out-Null
                }
                
                Write-Log "Generating HTML file: $outputFile"
                # Save with UTF8 encoding without BOM
                [System.IO.File]::WriteAllText($outputFile, $html, [System.Text.UTF8Encoding]::new($false))
                Write-FileInfo $outputFile
                
                # Add to entries with current timestamp
                $entries += @"
                <div class="weblog-entry">
                    <span class="weblog-date">$(Get-Date -Format "[yyyy-MM-dd HH:mm]")</span>
                    <a href="./$outputDir/log.html">Vera's Commentary</a>
                </div>
"@
            }
        } elseif ($isSessions) {
            if (Test-Path "$sourceDir/*.jsonl") {
                $sessions = Get-ChildItem "$sourceDir/*.jsonl" -ErrorAction Stop | Sort-Object Name -Descending

                foreach ($session in $sessions) {
                    Write-Log "Converting session file: $($session.Name)"

                    if ($session.BaseName -notmatch '^\d{4}-\d{2}-\d{2}-\d{4}$') {
                        Write-Warning "Session file $($session.Name) does not match expected format YYYY-MM-DD-HHMM.jsonl"
                        continue
                    }

                    $date = $session.BaseName -replace "(\d{4})-(\d{2})-(\d{2})-(\d{2})(\d{2})", '$1-$2-$3 $4:$5'

                    $lines = Get-Content $session.FullName -Encoding UTF8 -ErrorAction Stop
                    $messages = @()

                    foreach ($line in $lines) {
                        $trimmed = $line.Trim()
                        if ([string]::IsNullOrWhiteSpace($trimmed)) {
                            continue
                        }

                        try {
                            $messages += $trimmed | ConvertFrom-Json
                        }
                        catch {
                            Write-Warning "Skipping invalid JSON line in $($session.Name): $trimmed"
                        }
                    }

                    if (-not $messages) {
                        Write-Warning "No valid messages found in $($session.Name)"
                        continue
                    }

                    $title = $null
                    foreach ($msg in $messages) {
                        if ($msg.PSObject.Properties.Match('title')) {
                            $candidate = $msg.title
                            if (-not [string]::IsNullOrWhiteSpace($candidate)) {
                                $title = $candidate.Trim()
                                break
                            }
                        }

                        if ($msg.PSObject.Properties.Match('meta')) {
                            $meta = $msg.meta
                            if ($meta -and $meta.PSObject.Properties.Match('title')) {
                                $candidate = $meta.title
                                if (-not [string]::IsNullOrWhiteSpace($candidate)) {
                                    $title = $candidate.Trim()
                                    break
                                }
                            }
                        }

                        if ($msg.PSObject.Properties.Match('type') -and $msg.type -eq 'meta' -and $msg.PSObject.Properties.Match('summary')) {
                            $candidate = $msg.summary
                            if (-not [string]::IsNullOrWhiteSpace($candidate)) {
                                $title = $candidate.Trim()
                                break
                            }
                        }
                    }

                    if (-not $title) {
                        $title = "Session $date"
                    }

                    $encodedTitle = [System.Web.HttpUtility]::HtmlEncode($title)

                    $sessionContent = @()
                    foreach ($msg in $messages) {
                        $role = 'message'
                        if ($msg.PSObject.Properties.Match('role')) {
                            $role = $msg.role
                        } elseif ($msg.PSObject.Properties.Match('type')) {
                            $role = $msg.type
                        }

                        if ([string]::IsNullOrWhiteSpace($role)) {
                            $role = 'message'
                        }

                        $timestamp = if ($msg.PSObject.Properties.Match('timestamp')) { $msg.timestamp } else { $null }

                        $contentValue = $null
                        if ($msg.PSObject.Properties.Match('content')) {
                            $contentValue = $msg.content
                        } elseif ($msg.PSObject.Properties.Match('text')) {
                            $contentValue = $msg.text
                        }

                        if ($contentValue -is [System.Collections.IEnumerable] -and -not ($contentValue -is [string])) {
                            $contentValue = ($contentValue | ForEach-Object { $_.ToString() }) -join "`n"
                        }

                        $contentString = if ($contentValue) { $contentValue.ToString() } else { '' }
                        $encodedContent = [System.Web.HttpUtility]::HtmlEncode($contentString)
                        $encodedRole = [System.Web.HttpUtility]::HtmlEncode($role)

                        $roleClass = ($role -replace "[^a-zA-Z0-9]", "-").ToLowerInvariant()
                        if ([string]::IsNullOrWhiteSpace($roleClass)) {
                            $roleClass = "message"
                        }

                        $timestampHtml = ''
                        if ($timestamp) {
                            $encodedTimestamp = [System.Web.HttpUtility]::HtmlEncode($timestamp.ToString())
                            $timestampHtml = "<div class=\"session-timestamp\">$encodedTimestamp</div>"
                        }

                        $sessionContent += @"
        <div class="session-turn session-$roleClass">
            <div class="session-role">$encodedRole</div>
            $timestampHtml
            <pre>$encodedContent</pre>
        </div>
"@
                    }

                    $contentHtml = $sessionContent -join ""

                    $outputDirPath = Join-Path (Get-Location) $outputDir
                    $outputFile = Join-Path $outputDirPath "$($session.BaseName).html"
                    if (-not (Test-Path $outputDirPath)) {
                        New-Item -ItemType Directory -Path $outputDirPath -Force | Out-Null
                    }

                    Write-Log "Generating session HTML file: $outputFile"
                    $html = $template.Replace('{{title}}', $encodedTitle)
                    $html = $html.Replace('{{date}}', [System.Web.HttpUtility]::HtmlEncode($date))
                    $html = $html.Replace('{{content}}', $contentHtml)

                    [System.IO.File]::WriteAllText($outputFile, $html, [System.Text.UTF8Encoding]::new($false))

                    $entries += @"
                    <div class="weblog-entry">
                        <span class="weblog-date">[$date]</span>
                        <a href="./$outputDir/$($session.BaseName).html">$encodedTitle</a>
                    </div>
"@
                }
            }
        } else {
            # Handle regular text files
            if (Test-Path "$sourceDir/*.txt") {
                $posts = Get-ChildItem "$sourceDir/*.txt" -ErrorAction Stop | Sort-Object Name -Descending
                
                foreach ($post in $posts) {
                    Write-Log "Converting file: $($post.Name)"
                    
                    # Verify filename format
                    if ($post.BaseName -notmatch '^\d{4}-\d{2}-\d{2}-\d{4}$') {
                        Write-Warning "File $($post.Name) does not match expected format YYYY-MM-DD-HHMM.txt"
                        continue
                    }
                    
                    # Parse filename for date
                    $date = $post.BaseName -replace "(\d{4})-(\d{2})-(\d{2})-(\d{2})(\d{2})", '$1-$2-$3 $4:$5'
                    
                    # Read content with UTF8 encoding
                    $content = Get-Content -Raw -Encoding UTF8 $post.FullName -ErrorAction Stop
                    
                    # Split title and content
                    $contentParts = $content -split "`n", 2
                    if ($contentParts.Count -lt 2) {
                        Write-Warning "File $($post.Name) does not have title and content separated by newline"
                        continue
                    }
                    $title = $contentParts[0].Trim()
                    $postContent = $contentParts[1].Trim()
                    
                    # Apply template without HTML encoding the content
                    $html = $template `
                        -replace "{{date}}", $date `
                        -replace "{{title}}", $title `
                        -replace "{{content}}", $postContent
                    
                    # Generate output filename and ensure directory exists
                    $outputDirPath = Join-Path (Get-Location) $outputDir
                    $outputFile = Join-Path $outputDirPath "$($post.BaseName).html"
                    if (-not (Test-Path $outputDirPath)) {
                        New-Item -ItemType Directory -Path $outputDirPath -Force | Out-Null
                    }
                    
                    Write-Log "Generating HTML file: $outputFile"
                    # Save the file with UTF8 encoding without BOM
                    [System.IO.File]::WriteAllText($outputFile, $html, [System.Text.UTF8Encoding]::new($false))
                    
                    # Add to entries with minimal HTML encoding
                    $entries += @"
                    <div class="weblog-entry">
                        <span class="weblog-date">[$date]</span>
                        <a href="./$outputDir/$($post.BaseName).html">$title</a>
                    </div>
"@
                }
            }
        }
        
        return $entries
    }

    # Convert each section
    Write-Log "Converting weblogs section"
    [string[]]$weblogEntries = Convert-Section "_weblogs" "weblogs" '(<div class="folder">weblogs</div>\s*<div class="indent">)(.*?)(\s*</div>\s*\s*<div class="folder">dialogues</div>)'

    Write-Log "Converting dialogues section"
    [string[]]$dialogueEntries = Convert-Section "_dialogues" "dialogues" '(<div class="folder">dialogues</div>\s*<div class="indent">)(.*?)(\s*</div>\s*\s*<div class="folder">sessions</div>)'

    Write-Log "Converting sessions section"
    [string[]]$sessionEntries = Convert-Section "_sessions" "sessions" '(<div class="folder">sessions</div>\s*<div class="indent">)(.*?)(\s*</div>\s*\s*<div class="folder">vera</div>)' -Template $sessionTemplate -IsSessions

    Write-Log "Converting Vera's commentary"
    [string[]]$veraEntries = Convert-Section "_vera" "vera" '(<div class="folder">vera</div>\s*<div class="indent">)(.*?)(\s*</div>\s*\s*<div class="file">projects</div>)' -Template $veraTemplate -IsVera

    # Verify index.html exists
    if (-not (Test-Path "index.html")) {
        throw "index.html not found"
    }

    # Update index.html
    Write-Log "Updating index.html"
    $indexHtml = Get-Content -Raw "index.html" -ErrorAction Stop

    # Update weblogs section
    Write-Log "Updating weblogs section in index.html"
    $indexHtml = $indexHtml -replace '(?s)(<div class="folder">weblogs</div>\s*<div class="indent">)(.*?)(\s*</div>\s*\s*<div class="folder">dialogues</div>)', "`$1`n$($weblogEntries -join "`n")`$3"

    # Update dialogues section
    Write-Log "Updating dialogues section in index.html"
    $indexHtml = $indexHtml -replace '(?s)(<div class="folder">dialogues</div>\s*<div class="indent">)(.*?)(\s*</div>\s*\s*<div class="folder">sessions</div>)', "`$1`n$($dialogueEntries -join "`n")`$3"

    # Update sessions section
    Write-Log "Updating sessions section in index.html"
    $indexHtml = $indexHtml -replace '(?s)(<div class="folder">sessions</div>\s*<div class="indent">)(.*?)(\s*</div>\s*\s*<div class="folder">vera</div>)', "`$1`n$($sessionEntries -join "`n")`$3"

    # Update Vera section
    Write-Log "Updating Vera section in index.html"
    $indexHtml = $indexHtml -replace '(?s)(<div class="folder">vera</div>\s*<div class="indent">)(.*?)(\s*</div>\s*\s*<div class="file">projects</div>)', "`$1`n$($veraEntries -join "`n")`$3"

    # Update index.html with UTF8 encoding
    Write-Log "Writing updated index.html"
    [System.IO.File]::WriteAllText("index.html", $indexHtml, [System.Text.UTF8Encoding]::new($false))

    Write-Log "Build completed successfully"
}
catch {
    Write-Log "Error occurred: $($_.Exception.Message)"
    throw
}

if ($LASTEXITCODE -ne 0) {
    Write-Log "Build failed with exit code: $LASTEXITCODE"
    exit $LASTEXITCODE
} else {
    Write-Log "Build process completed with success"
    exit 0
} 
