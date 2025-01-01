# sarahlacard.github.io

Central hub for Sarah's projects and development work.

## Quick Start
1. Clone the repository
2. Run build.ps1 to generate the site
3. Open index.html in your browser

## Project Structure
- _posts/: Weblog entries
- _dialogues/: Conversation logs
- _raw-data/: Raw data files
- _templates/: HTML templates
- weblogs/, dialogues/: Generated HTML output
- build.ps1: Build script
- .github/workflows/: GitHub Actions configuration

## Build Process
The site uses a PowerShell build script (build.ps1) that:
1. Converts .txt files to HTML using templates
2. Updates index.html with new entries
3. Generates proper directory structure

## Projects
- [newyears25](https://github.com/sarahlacard/newyears25): Development branch (dev-test)
- (Future projects will be listed here)

## Contributing
1. Create content in appropriate directory (_posts/, _dialogues/, etc.)
2. Run build.ps1 to generate HTML
3. Commit and push changes
4. GitHub Actions will automatically rebuild the site
