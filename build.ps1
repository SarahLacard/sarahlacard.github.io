# Build script for generating weblog entries
Write-Host "Building weblog entries..."

# Ensure weblogs directory exists
if (-not (Test-Path "weblogs")) {
    New-Item -ItemType Directory -Path "weblogs"
}

# Read template
$template = Get-Content -Raw "_templates/post.html"

# Get all text files from _posts
$posts = Get-ChildItem "_posts/*.txt" | Sort-Object Name -Descending

# Array to store entries for index.html
$indexEntries = @()

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
    $outputFile = "weblogs/$($post.BaseName).html"
    
    # Save the file
    $html | Out-File -FilePath $outputFile -Encoding UTF8
    
    # Add to index entries
    $indexEntries += @"
            <div class="weblog-entry">
                <span class="weblog-date">[$date]</span>
                <a href="./weblogs/$($post.BaseName).html">$title</a>
            </div>
"@
}

# Update index.html
$indexHtml = Get-Content -Raw "index.html"
$indexPattern = '(?s)(<div class="folder">weblogs</div>\s*<div class="indent">)(.*?)(\s*</div>\s*\s*<div class="file">)'
$newIndexContent = $indexHtml -replace $indexPattern, "`$1`n$($indexEntries -join "`n")`$3"
$newIndexContent | Out-File -FilePath "index.html" -Encoding UTF8

Write-Host "Build complete!" 