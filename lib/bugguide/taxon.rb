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
require 'nokogiri'
require 'open-uri'
require 'cgi'

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

  # Create a new taxon from name and URL
  def self.new_from_name_and_url(name, url)
    id = url.match(/\/node\/view\/(\d+)/)
    id = id ? id[1] : nil
    taxon = new(name: name, url: url)
    taxon.id = id if id
    taxon
  end

  # Search for taxa, returns matching BugGuide::Taxon instances
  def self.search(name, options = {})
    
    sleep(1)
    
    begin
      browser = Ferrum::Browser.new(
        headless: true,
        timeout: 30,
        browser_options: {
          'user-agent' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36'
        }
      )
      
      # Go to the advanced search page
      browser.go_to("https://bugguide.net/adv_search/bgsearch.php")
      sleep(2)
      
      # Find the taxon field
      taxon_input = browser.at_css('input[name="taxon"]')
      
      if taxon_input
        taxon_input.focus.type(name)
        
        # Wait for autocomplete dropdown and click the first suggestion
        sleep(2)
        
        ac_result = browser.at_css('.ac_results li')
        if ac_result
          taxon_id = ac_result.text.match(/^(\d+)/)[1]
          ac_result.click
          sleep(1)
        else
          puts "  No autocomplete dropdown found. Trying fallback..."
          taxon_input.type(" ")
          sleep(2)
          ac_result = browser.at_css('.ac_results li')
          if ac_result
            taxon_id = ac_result.text.match(/^(\d+)/)[1]
            puts "  Selected taxon ID: #{taxon_id} (#{name})"
            ac_result.click
          end
        end
      else
        puts "Error: Could not find taxon input!"
        browser.quit
        return []
      end

      # Select state/province if provided
      if options[:state]
        state_code = options[:state]
        
        location_select = browser.at_css('select[name="location[]"]')
        
        if location_select
          bc_option = location_select.at_css("option[value='#{state_code}']")
          if bc_option
            bc_option.click
            sleep(1)
          else
            puts "  Warning: Could not find option for #{state_code}"
          end
        else
          puts "  Warning: Could not find location select element"
        end
      end
      
      # Submit the form
      submit_button = browser.at_css('input[type="submit"][value="Go!"]')
      if submit_button
        submit_button.click
      else
        browser.execute("document.getElementById('bgsearch').submit()")
      end
      
      # Wait for results
      sleep(5)
      browser.network.wait_for_idle
      
      # Save page for debugging
      File.open("/tmp/bugguide_results.html", "w") do |f|
        f.write(browser.body)
      end
      
      doc = Nokogiri::HTML(browser.body)
      browser.quit
      
      # Parse results - look for the Guide Placement column
      results = []
      
      doc.css('table tr').each do |row|
        cells = row.css('td')
        
        if cells.length >= 7
          guide_cell = cells.last
          link = guide_cell.at_css('a')
          
          if link
            href = link['href']
            taxon_name = link.at_css('i') ? link.at_css('i').text.strip : link.text.strip
            
            if href && href.include?('/node/view/') && taxon_name.length > 0
              results << { name: taxon_name, url: href }
            end
          end
        end
      end
      
      # Get unique taxa by URL
      unique_taxa = results.uniq { |r| r[:url] }
      
      if unique_taxa.empty?
        puts "No results found."
      end
      
      # Return the taxa without printing (CLI will handle output)
      unique_taxa.map { |t| new_from_name_and_url(t[:name], t[:url]) }
        
    rescue => e
      puts "Error: #{e.message}"
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
  alias_method :taxonID, :id
  alias_method :scientificName, :scientific_name
  alias_method :vernacularName, :common_name
  alias_method :taxonRank, :rank

  def higherClassification
    ancestors.map(&:scientific_name).join(' | ')
  end

end
