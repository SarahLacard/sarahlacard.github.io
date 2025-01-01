# Build script for generating entries
Write-Host "Building site entries..."

# Ensure directories exist
@("weblogs", "dialogues", "_raw-data") | ForEach-Object {
    if (-not (Test-Path $_)) {
        New-Item -ItemType Directory -Path $_
    }
}

# Read template
$template = Get-Content -Raw "_templates/post.html"

# Function to process entries for a section
function Process-Section {
    param (
        [string]$sourceDir,
        [string]$outputDir,
        [string]$sectionPattern
    )
    
    $entries = @()
    
    # Get all text files from source directory
    if (Test-Path "$sourceDir/*.txt") {
        $posts = Get-ChildItem "$sourceDir/*.txt" | Sort-Object Name -Descending
        
        foreach ($post in $posts) {
            Write-Host "Processing $($post.Name)..."
            
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
$weblogEntries = Process-Section "_posts" "weblogs" '(<div class="folder">weblogs</div>\s*<div class="indent">)(.*?)(\s*</div>\s*\s*<div class="folder">dialogues</div>)'
$dialogueEntries = Process-Section "_dialogues" "dialogues" '(<div class="folder">dialogues</div>\s*<div class="indent">)(.*?)(\s*</div>\s*\s*<div class="folder">raw data</div>)'
$rawDataEntries = Process-Section "_raw-data" "_raw-data" '(<div class="folder">raw data</div>\s*<div class="indent">)(.*?)(\s*</div>\s*\s*<div class="file">)'

# Update index.html
$indexHtml = Get-Content -Raw "index.html"

# Update weblogs section
$indexHtml = $indexHtml -replace '(?s)(<div class="folder">weblogs</div>\s*<div class="indent">)(.*?)(\s*</div>\s*\s*<div class="folder">dialogues</div>)', "`$1`n$($weblogEntries -join "`n")`$3"

# Update dialogues section
$indexHtml = $indexHtml -replace '(?s)(<div class="folder">dialogues</div>\s*<div class="indent">)(.*?)(\s*</div>\s*\s*<div class="folder">raw data</div>)', "`$1`n$($dialogueEntries -join "`n")`$3"

# Update raw data section
$indexHtml = $indexHtml -replace '(?s)(<div class="folder">raw data</div>\s*<div class="indent">)(.*?)(\s*</div>\s*\s*<div class="file">)', "`$1`n$($rawDataEntries -join "`n")`$3"

$indexHtml | Out-File -FilePath "index.html" -Encoding UTF8

Write-Host "Build complete!" 