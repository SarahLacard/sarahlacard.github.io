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

# Function to clean up orphaned HTML files
function Remove-OrphanedHtml {
    param (
        [string]$sourceDir,
        [string]$outputDir
    )
    
    Write-Log "Cleaning up orphaned HTML files in $outputDir"
    
    # Get all HTML files
    if (Test-Path "$outputDir/*.html") {
        Get-ChildItem "$outputDir/*.html" | ForEach-Object {
            $htmlFile = $_
            $sourceFile = if ($sourceDir -eq "_vera") {
                Join-Path $sourceDir "log.md"
            } else {
                Join-Path $sourceDir ($htmlFile.BaseName + ".txt")
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
    @("_weblogs", "_dialogues", "_vera", "_templates", "weblogs", "dialogues", "vera") | ForEach-Object {
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

    # Verify template files exist
    @("_templates/post.html", "_templates/vera.html") | ForEach-Object {
        if (-not (Test-Path $_)) {
            throw "Required template file not found: $_"
        }
    }

    # Read templates
    Write-Log "Reading templates"
    $postTemplate = Get-Content -Raw "_templates/post.html" -ErrorAction Stop
    $veraTemplate = Get-Content -Raw "_templates/vera.html" -ErrorAction Stop

    # Function to convert entries for a section
    function Convert-Section {
        param (
            [string]$sourceDir,
            [string]$outputDir,
            [string]$sectionPattern,
            [string]$template = $postTemplate,
            [switch]$isVera
        )
        
        Write-Log "Converting section: $sourceDir -> $outputDir"
        $entries = @()
        
        if ($isVera) {
            # Handle Vera's commentary
            $veraLog = Join-Path $sourceDir "log.md"
            if (Test-Path $veraLog) {
                Write-Log "Converting Vera's commentary"
                
                # Read and convert markdown content
                $content = Get-Content -Raw $veraLog -ErrorAction Stop
                
                # Apply template
                $html = $template -replace "{{content}}", $content
                
                # Generate output file
                $outputFile = Join-Path $outputDir "log.html"
                Write-Log "Generating HTML file: $outputFile"
                $html | Out-File -FilePath $outputFile -Encoding UTF8 -ErrorAction Stop
                
                # Add to entries
                $entries += @"
                <div class="weblog-entry">
                    <span class="weblog-date">$(Get-Date -Format "[yyyy-MM-dd HH:mm]")</span>
                    <a href="./$outputDir/log.html">Vera's Commentary</a>
                </div>
"@
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
                    
                    # Read content
                    $content = Get-Content -Raw $post.FullName -ErrorAction Stop
                    
                    # Split title and content
                    $contentParts = $content -split "`n", 2
                    if ($contentParts.Count -lt 2) {
                        Write-Warning "File $($post.Name) does not have title and content separated by newline"
                        continue
                    }
                    $title = $contentParts[0].Trim()
                    $postContent = $contentParts[1].Trim()
                    
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
        }
        
        return $entries
    }

    # Convert each section
    Write-Log "Converting weblogs section"
    [string[]]$weblogEntries = Convert-Section "_weblogs" "weblogs" '(<div class="folder">weblogs</div>\s*<div class="indent">)(.*?)(\s*</div>\s*\s*<div class="folder">dialogues</div>)'
    
    Write-Log "Converting dialogues section"
    [string[]]$dialogueEntries = Convert-Section "_dialogues" "dialogues" '(<div class="folder">dialogues</div>\s*<div class="indent">)(.*?)(\s*</div>\s*\s*<div class="folder">vera</div>)'
    
    Write-Log "Converting Vera's commentary"
    [string[]]$veraEntries = Convert-Section "_vera" "vera" '(<div class="folder">vera</div>\s*<div class="indent">)(.*?)(\s*</div>\s*\s*<div class="file">)' -Template $veraTemplate -IsVera

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
    $indexHtml = $indexHtml -replace '(?s)(<div class="folder">dialogues</div>\s*<div class="indent">)(.*?)(\s*</div>\s*\s*<div class="folder">vera</div>)', "`$1`n$($dialogueEntries -join "`n")`$3"

    # Update Vera section
    Write-Log "Updating Vera section in index.html"
    $indexHtml = $indexHtml -replace '(?s)(<div class="folder">vera</div>\s*<div class="indent">)(.*?)(\s*</div>\s*\s*<div class="file">)', "`$1`n$($veraEntries -join "`n")`$3"

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