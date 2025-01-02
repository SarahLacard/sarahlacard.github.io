# Build script for generating entries
$ErrorActionPreference = "Stop"
$VerbosePreference = "Continue"

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

try {
    Write-Log "Starting build..."

    # Verify required directories exist
    @("_weblogs", "_dialogues", "_raw-data", "_templates", "weblogs", "dialogues", "raw-data") | ForEach-Object {
        Write-Log "Checking directory: $_"
        if (-not (Test-Path $_)) {
            Write-Log "Creating directory: $_"
            New-Item -ItemType Directory -Path $_ -ErrorAction Stop
        }
    }

    # Verify template files exist
    @("_templates/post.html", "_templates/raw-data.html") | ForEach-Object {
        if (-not (Test-Path $_)) {
            throw "Required template file not found: $_"
        }
    }

    # Read templates
    Write-Log "Reading templates"
    $postTemplate = Get-Content -Raw "_templates/post.html" -ErrorAction Stop
    $rawDataTemplate = Get-Content -Raw "_templates/raw-data.html" -ErrorAction Stop

    # Function to convert entries for a section
    function Convert-Section {
        param (
            [string]$sourceDir,
            [string]$outputDir,
            [string]$sectionPattern,
            [string]$template = $postTemplate,
            [switch]$isRawData
        )
        
        Write-Log "Converting section: $sourceDir -> $outputDir"
        $entries = @()
        
        # Get all text files from source directory
        if (Test-Path "$sourceDir/*.txt") {
            $posts = Get-ChildItem "$sourceDir/*.txt" -ErrorAction Stop | Sort-Object Name -Descending
            
            foreach ($post in $posts) {
                Write-Log "Converting file: $($post.Name)"
                
                # Verify filename format
                if ($post.BaseName -notmatch '^\d{4}-\d{2}-\d{2}-\d{4}$') {
                    Write-Warning "File $($post.Name) does not match expected format YYYY-MM-DD-HHMM.txt"
                    continue
                }
                
                # Parse filename for date (YYYY-MM-DD-HHMM.txt)
                $date = $post.BaseName -replace "(\d{4})-(\d{2})-(\d{2})-(\d{2})(\d{2})", '$1-$2-$3 $4:$5'
                
                # Read content
                $content = Get-Content -Raw $post.FullName -ErrorAction Stop

                if ($isRawData) {
                    # For raw data, use first line as title and keep all content
                    $title = $post.BaseName
                    $postContent = $content
                } else {
                    # For posts/dialogues, split title and content
                    $contentParts = $content -split "`n", 2
                    if ($contentParts.Count -lt 2) {
                        Write-Warning "File $($post.Name) does not have title and content separated by newline"
                        continue
                    }
                    $title = $contentParts[0].Trim()
                    $postContent = $contentParts[1].Trim()
                }
                
                # Apply template
                $html = $template `
                    -replace "{{date}}", [System.Web.HttpUtility]::HtmlEncode($date) `
                    -replace "{{title}}", [System.Web.HttpUtility]::HtmlEncode($title) `
                    -replace "{{content}}", $postContent
                
                # Generate output filename
                $outputFile = "$outputDir/$($post.BaseName).html"
                
                Write-Log "Generating HTML file: $outputFile"
                # Save the file
                $html | Out-File -FilePath $outputFile -Encoding UTF8 -ErrorAction Stop
                
                # Add to entries
                $entries += @"
                <div class="weblog-entry">
                    <span class="weblog-date">[$([System.Web.HttpUtility]::HtmlEncode($date))]</span>
                    <a href="./$outputDir/$($post.BaseName).html">$([System.Web.HttpUtility]::HtmlEncode($title))</a>
                </div>
"@
            }
        }
        
        return $entries
    }

    # Convert each section
    # Note: The following variables are used in string replacements later in the script
    Write-Log "Converting weblogs section"
    [string[]]$weblogEntries = Convert-Section "_weblogs" "weblogs" '(<div class="folder">weblogs</div>\s*<div class="indent">)(.*?)(\s*</div>\s*\s*<div class="folder">dialogues</div>)'
    
    Write-Log "Converting dialogues section"
    [string[]]$dialogueEntries = Convert-Section "_dialogues" "dialogues" '(<div class="folder">dialogues</div>\s*<div class="indent">)(.*?)(\s*</div>\s*\s*<div class="folder">raw data</div>)'
    
    Write-Log "Converting raw data section"
    [string[]]$rawDataEntries = Convert-Section "_raw-data" "raw-data" '(<div class="folder">raw data</div>\s*<div class="indent">)(.*?)(\s*</div>\s*\s*<div class="file">)' -Template $rawDataTemplate -IsRawData

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
    $indexHtml = $indexHtml -replace '(?s)(<div class="folder">dialogues</div>\s*<div class="indent">)(.*?)(\s*</div>\s*\s*<div class="folder">raw data</div>)', "`$1`n$($dialogueEntries -join "`n")`$3"

    # Update raw data section
    Write-Log "Updating raw data section in index.html"
    $indexHtml = $indexHtml -replace '(?s)(<div class="folder">raw data</div>\s*<div class="indent">)(.*?)(\s*</div>\s*\s*<div class="file">)', "`$1`n$($rawDataEntries -join "`n")`$3"

    Write-Log "Writing updated index.html"
    $indexHtml | Out-File -FilePath "index.html" -Encoding UTF8 -ErrorAction Stop

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