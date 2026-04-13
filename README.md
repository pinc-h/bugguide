# BugGuide

Ruby gem for scraping data from BugGuide.net, an excellent online community of entomologists sharing information about terrestrial arthropods in North America. Sadly, BugGuide doesn't have an API, so this gem is little more than a scraper focusing on their advanced search feature. This Ruby Gem was originally developed by Ken-ichi Ueda, which I have updated and simplified with the help of AI. Mistakes likely abound. Let me know if it works for you.

Currently this command-line program only generates checklists for a given taxon and state/province by scraping BugGuide.

### 2026 Updates (Alex Pinch)

What needed updating was:  
- **Cloudflare Bypass**: Replaced `open-uri` with `ferrum` (headless Chromium browser) to handle Cloudflare's bot protection.  
- **Fixed Advanced Search**: Updated to use BugGuide's autocomplete-based taxon search form.  
- **Metadata included in output**: Output includes generation timestamp and query parameters as comments.  

### Requirements

-   Ruby 3.2+
-   Chromium browser (installed automatically by ferrum on first run)
-   Bundler

### Installation

Clone and install locally:

``` bash
git clone https://github.com/pinc-h/bugguide.git
cd bugguide
gem build bugguide.gemspec
gem install ./bugguide-0.1.4.gem
```

If having trouble installing, you can run directly:

``` bash
git clone https://github.com/pinc-h/bugguide.git
cd bugguide
bundle install
ruby -I lib bin/bugguide checklist Bombus -s BC
```

### Usage

Generate checklists of taxa for a given location:

``` bash
$ bugguide checklist Epeolus -s BC
# BugGuide Checklist Generator. Alex Pinch, modified from Ken-ichi Ueda. April 2026.
# Generated on 2026-04-13 14:32:15
# Searching for Epeolus in BC...

Found 4 taxa:

TAXON ID   NAME
-----------------------------------------
1436814    Epeolus olympiellus
15028      Epeolus
446249     Epeolus compactus
1575727    Epeolus minimus
```

For CSV output:

``` bash
$ bugguide checklist Epeolus -s BC -f csv
# BugGuide Checklist Generator. Alex Pinch, modified from Ken-ichi Ueda. April 2026.
# Generated on 2026-04-13 14:32:15
# Searching for Epeolus in BC
TAXON ID,NAME
1436814,Epeolus olympiellus
15028,Epeolus
446249,Epeolus compactus
1575727,Epeolus minimus
```

### Options/Flags

| Option              | Description                                      |
|---------------------|--------------------------------------------------|
| `-s, --state STATE` | 2-letter code of a US state or Canadian province |
| `-f, --format csv`  | Output as CSV (default is formatted table)       |

------------------------------------------------------------------------

### Credits

-   Original gem by [Ken-ichi Ueda](https://github.com/kueda)
-   2026 updates and Cloudflare bypass by [Alex Pinch](https://github.com/pinc-h)  
