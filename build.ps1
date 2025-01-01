# Build script for generating entries
$ErrorActionPreference = "Stop"
$VerbosePreference = "Continue"

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] $Message"
    Write-Verbose $logMessage
    Add-Content -Path "build.log" -Value $logMessage
}

try {
    Write-Log "Starting build..."

    # Ensure directories exist
    @("weblogs", "dialogues", "_raw-data") | ForEach-Object {
        Write-Log "Checking directory: $_"
        if (-not (Test-Path $_)) {
            Write-Log "Creating directory: $_"
            New-Item -ItemType Directory -Path $_
        }
    }

    # Read template
    Write-Log "Reading template file"
    $template = Get-Content -Raw "_templates/post.html"

    # Function to process entries for a section
    function Process-Section {
        param (
            [string]$sourceDir,
            [string]$outputDir,
            [string]$sectionPattern
        )
        
        Write-Log "Processing section: $sourceDir -> $outputDir"
        $entries = @()
        
        # Get all text files from source directory
        if (Test-Path "$sourceDir/*.txt") {
            $posts = Get-ChildItem "$sourceDir/*.txt" | Sort-Object Name -Descending
            
            foreach ($post in $posts) {
                Write-Log "Processing file: $($post.Name)"
                
                # Parse filename for date (YYYY-MM-DD-HHMM.txt)
                $date = $post.BaseName -replace "(\d{4})-(\d{2})-(\d{2})-(\d{2})(\d{2})", '$1-$2-$3 $4:$5'
                
                # Read content
                $content = Get-Content -Raw $post.FullName
                
                # First line is title
                $title = ($content -split "`n")[0].Trim()
                # Rest is content
                $postContent = ($content -split "`n", 2)[1].Trim()
                
                # Apply template
                $html = $template `
                    -replace "{{date}}", $date `
                    -replace "{{title}}", $title `
                    -replace "{{content}}", $postContent
                
                # Generate output filename
                $outputFile = "$outputDir/$($post.BaseName).html"
                
                Write-Log "Generating HTML file: $outputFile"
                # Save the file
                $html | Out-File -FilePath $outputFile -Encoding UTF8
                
                # Add to entries
                $entries += @"
                <div class="weblog-entry">
                    <span class="weblog-date">[$date]</span>
                    <a href="./$outputDir/$($post.BaseName).html">$title</a>
                </div>
"@
            }
        }
        
        return $entries
    }

    # Process each section
    Write-Log "Processing weblogs section"
    $weblogEntries = Process-Section "_posts" "weblogs" '(<div class="folder">weblogs</div>\s*<div class="indent">)(.*?)(\s*</div>\s*\s*<div class="folder">dialogues</div>)'
    
    Write-Log "Processing dialogues section"
    $dialogueEntries = Process-Section "_dialogues" "dialogues" '(<div class="folder">dialogues</div>\s*<div class="indent">)(.*?)(\s*</div>\s*\s*<div class="folder">raw data</div>)'
    
    Write-Log "Processing raw data section"
    $rawDataEntries = Process-Section "_raw-data" "_raw-data" '(<div class="folder">raw data</div>\s*<div class="indent">)(.*?)(\s*</div>\s*\s*<div class="file">)'

    # Update index.html
    Write-Log "Updating index.html"
    $indexHtml = Get-Content -Raw "index.html"

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
    $indexHtml | Out-File -FilePath "index.html" -Encoding UTF8

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