#encoding: utf-8
#
# Represents a single taxon on BugGuide
#
# One thing to keep in mind is that this will generally be instantiated from
# search results, so for certain methods, like `ancestry`, it will need to
# perform an additional request to retrieve the relevant data.
#
# Several methods are intended for
# compatability with the DarwinCore SimpleMultimedia extention (http://rs.gbif.org/terms/1.0/Multimedia).
#

require 'ferrum'

class BugGuide::Taxon
  NAME_PATTERN = /[\w\s\-\'\.]+/
  attr_accessor :id, :url
  attr_reader :name, :scientific_name, :common_name

  def initialize(options = {})
    options.each do |k,v|
      send("#{k}=", v)
    end
    self.url ||= "https://bugguide.net/node/view/#{id}"
    @taxonomy_html = nil
    @rank = nil
    @ancestors = nil
  end

  def name=(new_name)
    if new_name =~ /subgenus/i
      self.scientific_name ||= new_name.gsub(/subgenus/i, '')[/[^\(]+/, 0]
    elsif matches = new_name.match(/group .*\((#{NAME_PATTERN})\)/i)
      self.scientific_name ||= matches[1]
    elsif matches = new_name.match(/(#{NAME_PATTERN}) \((#{NAME_PATTERN})\)/)
      self.scientific_name ||= matches[1]
      self.common_name ||= matches[2]
    else
      self.scientific_name ||= new_name[/[^\(]+/, 0]
    end
    @name = new_name.strip if new_name
  end

  def scientific_name=(new_name)
    @scientific_name = new_name.strip if new_name
  end

  def common_name=(new_name)
    @common_name = new_name.strip if new_name
  end

  def rank=(new_rank)
    @rank = new_rank.downcase
    @rank = nil if @rank == 'no taxon'
  end

  # Taxonomic rank, e.g. kingdom, phylum, order, etc.
  def rank
    return @rank if @rank
    @rank = taxonomy_html.css('.bgpage-roots a').last['title'].downcase
  end

  # All ancestor taxa of this taxon, or its classification if you prefer that terminology.
  def ancestors
    return @ancestors if @ancestors
    @ancestors = []
    nbsp = Nokogiri::HTML("&nbsp;").text
    @ancestors = taxonomy_html.css('.bgpage-roots a').map do |a|
      next unless a['href'] =~ /node\/view\/\d+\/tree/
      t = BugGuide::Taxon.new(
        id: a['href'].split('/')[-2],
        name: a.text.gsub(nbsp, ' '),
        url: a['href'],
        rank: a['title']
      )
      if name_matches = t.name.match(/(#{NAME_PATTERN})\s+\((#{NAME_PATTERN})\)/)
        t.common_name = name_matches[1]
        t.scientific_name = name_matches[2]
      elsif name_matches = t.name.match(/(#{NAME_PATTERN})\s+\-\s+(#{NAME_PATTERN})/)
        t.common_name = name_matches[2]
        t.scientific_name = name_matches[1]
      end
      next if t.scientific_name == scientific_name
      t
    end.compact
  end

  # HTML source of the taxon's taxonomy page on BugGuide as a Nokogiri document
  def taxonomy_html
    return @taxonomy_html if @taxonomy_html
    open("https://bugguide.net/node/view/#{id}/tree") do |response|
      @taxonomy_html = Nokogiri::HTML(response.read)
    end
  end

# ----------
# MY STUFF!!!
  # Search for taxa, returns matching BugGuide::Taxon instances
def self.search(name, options = {})
	puts "DEBUG: Options received: #{options.inspect}"
  sleep(1)
  
  begin
    require 'ferrum'
    
    browser = Ferrum::Browser.new(
      headless: true,  # Keep false so you can watch it work
      timeout: 30,
      browser_options: {
        'user-agent' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36'
      }
    )
    
    # Go to the advanced search page
    puts "Going to advanced search page..."
    browser.go_to("https://bugguide.net/adv_search/bgsearch.php")
    sleep(2)
    
    # Find the taxon field
    puts "Typing '#{name}' into Taxon ID field..."
    taxon_input = browser.at_css('input[name="taxon"]')
    
    if taxon_input
      taxon_input.focus.type(name)
      
      # Wait for autocomplete dropdown and click the first suggestion
      puts "Waiting for autocomplete dropdown..."
      sleep(2)
      
      # The autocomplete dropdown uses class 'ac_results'
      ac_result = browser.at_css('.ac_results li')
      if ac_result
        puts "  - Clicking: #{ac_result.text}"
        ac_result.click
        sleep(1)
      else
        puts "  - No autocomplete dropdown found. Trying fallback..."
        # Fallback: try typing more to trigger it
        taxon_input.type(" ")
        sleep(2)
        ac_result = browser.at_css('.ac_results li')
        if ac_result
          ac_result.click
        end
      end
    else
      puts "Could not find taxon input!"
      browser.quit
      return []
    end

## --- State/province selection    
# Select state/province if provided
if options[:state]
  state_code = options[:state]
  puts "Selecting state: #{state_code}"
  
  # Find the select element
  location_select = browser.at_css('select[name="location[]"]')
  
  if location_select
    # First, clear any existing selections by clicking them
    location_select.css('option[selected]').each do |selected|
      selected.click
    end
    
    # Now select BC
    bc_option = location_select.at_css("option[value='#{state_code}']")
    if bc_option
      bc_option.click
      puts "  - Clicked #{state_code} option"
      sleep(1)
      
      # Verify it's selected
      if bc_option.attribute('selected')
        puts "  - #{state_code} is now selected!"
      else
        puts "  - Warning: #{state_code} may not be selected"
      end
    else
      puts "  - Could not find option for #{state_code}"
    end
  else
    puts "  - Could not find location select element"
  end
end

# -----    
    # Submit the form
    puts "Submitting form..."
    submit_button = browser.at_css('input[type="submit"][value="Go!"]')
    if submit_button
      submit_button.click
    else
      browser.execute("document.getElementById('bgsearch').submit()")
    end
    
    # Wait for results
    puts "Waiting for results page..."
    sleep(5)
    browser.network.wait_for_idle
    
    current_url = browser.current_url
    puts "Current URL: #{current_url}"
    
    # Save page for debugging
    File.open("/tmp/bugguide_results.html", "w") do |f|
      f.write(browser.body)
    end
    puts "Page saved to /tmp/bugguide_results.html"
    
    doc = Nokogiri::HTML(browser.body)
    browser.quit
    
#----- ADDED NEW PARSING METHOD, SINCE ON ADV PAGE -----
    # ADDED NEW PARSING METHOD, SINCE ON ADV PAGE -----
    # Parse results - look for the Guide Placement column (last td with a link)
    results = []

    # Results are in a table. Each row has the photo, ID, title, date, location, and Guide Placement
    doc.css('table tr').each do |row|
      # Get all cells in the row
      cells = row.css('td')
      
      # The Guide Placement is the last cell, which contains a link
      if cells.length >= 7
        guide_cell = cells.last
        link = guide_cell.at_css('a')
        
        if link
          href = link['href']
          text = link.text.strip
          
          # Extract the taxon name (remove italics tags if present)
          taxon_name = link.at_css('i') ? link.at_css('i').text.strip : text
          
          if href && href.include?('/node/view/') && taxon_name.length > 0
            results << { name: taxon_name, url: href }
          end
        end
      end
    end

    # Get unique taxa by URL
    unique_taxa = results.uniq { |r| r[:url] }

    if unique_taxa.empty?
      puts "No results found. Check /tmp/bugguide_results.html"
    else
      puts "\nFound #{unique_taxa.size} unique taxa:"
      unique_taxa.each do |t|
        puts "  #{t[:name]}"
      end
    end

    unique_taxa.map { |t| Taxon.new_from_name_and_url(t[:name], t[:url]) }
      
  rescue => e
    puts "Error: #{e.message}"
    puts e.backtrace if ENV['DEBUG']
    []
  end
end

# Find a single BugGuide taxon given its node ID
def self.find(id)
  taxon = BugGuide::Taxon.new(id: id)
  taxon.name = taxon.taxonomy_html.css('.node-title h1').text
  taxon.scientific_name = taxon.taxonomy_html.css('.node-title i').text
  taxon.common_name = taxon.taxonomy_html.css('.node-title').text.split('-').last
  taxon
end

# DarwinCore mapping

# DarwinCore-compliant taxon ID
alias_method :taxonID, :id

# DarwinCore-compliant scientific name
alias_method :scientificName, :scientific_name

# DarwinCore-compliant common name
alias_method :vernacularName, :common_name

# DarwinCore-compliant rank
alias_method :taxonRank, :rank

# DarwinCore-compliant taxonomic classification
def higherClassification
  ancestors.map(&:scientific_name).join(' | ')
end

end
