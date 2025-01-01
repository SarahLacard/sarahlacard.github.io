# <a href="https://sarahlacard.github.io">sarahlacard.github.io</a>

Central hub for Sarah's projects and development work.

## Quick Start
1. Clone the repository
2. Content is automatically built by GitHub Actions on push
3. View the site at sarahlacard.github.io

## Project Structure
- _posts/: Weblog entries
- _dialogues/: Conversation logs
- _raw-data/: Raw data files
- _templates/: HTML templates
- weblogs/, dialogues/: Generated HTML output
- build.ps1: Build script (runs via GitHub Actions)
- .github/workflows/: GitHub Actions configuration

## Build Process
The site uses GitHub Actions to:
1. Run build.ps1 automatically when changes are pushed
2. Convert .txt files to HTML using templates
3. Update index.html with new entries
4. Generate proper directory structure

Note: Local builds are not necessary unless testing changes.

## Projects
- [newyears25](https://github.com/sarahlacard/newyears25): Development branch (dev-test)
- (Future projects will be listed here)

## Contributing
1. Create content in appropriate directory (_posts/, _dialogues/, etc.)
2. Commit and push changes
3. GitHub Actions will automatically rebuild the site
4. Check Actions tab for build status

## Data Usage Notes
- Batch commits to minimize transfers
- Use direct Ethernet for large file transfers between machines
- Test changes locally before pushing when possible
